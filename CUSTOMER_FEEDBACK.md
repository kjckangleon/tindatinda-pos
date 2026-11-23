# Customer feedback and product decision history

Purpose: preserve customer-driven requirements, implementation choices, verification status, and follow-up work for future developers and AI agents. This is a product history, **not** a substitute for inspecting the current source code and database.

## 2026-11 — Ice temples (Emmanuel) feedback

### Stock movement history and automatic sales deduction
**Customer request:** View history of stock added and stock going out; each completed sales entry must automatically deduct the corresponding pack count from stock.

**Decision:** A completed checkout is a sale and deducts stock. Manual stock corrections and spoilage are **not** sales. Production adds stock. Editing or voiding sales must reconcile or restore stock through audited database operations. Pack sizes are 1 kg, 2 kg, 10 kg and 15 kg.

**Implementation:** Existing `ice_checkout_packs` Supabase RPC creates sale, decrements the matching `ice_pack_stock` row and inserts a negative `ice_pack_movements` record atomically, with stock checks and an idempotency request ID. `src/IceTemples.tsx` now displays the latest 500 movements (production, sale, adjustment, sale_correction, sale_void) with type filtering and Philippine timestamps. Recent sales excludes voided transactions. Commit `9f50cf3`; Vercel deployment was verified **READY**. Relevant migrations: `012_ice_pack_inventory.sql`, `013_ice_audited_corrections.sql`.

**Verification limits:** Database function definition and movement-history RLS policy were inspected without modifying production records. Vercel READY confirms deployment/build, **not** an authenticated end-to-end checkout/history test.

### Daily production compared with sales
**Customer request (Bisaya):** “Pwede naay daily total production rate para ma compare ang production comparing sa sales” — daily production totals compared with sales.

**Decision:** Compare daily production/stock-added kilograms with kilograms sold, using Asia/Manila dates and the report's date filters. Show daily table, chart and aggregate comparison. Formula: `sales kg / production kg × 100` when production > 0; otherwise N/A. This is a **ratio**, not a strict same-day sell-through metric, because sales may use previously produced stock. A ratio above 100% is possible.

**Implementation:** `src/IceSalesReports.tsx`, commit `a78a1f2`. Also fixes preexisting “Stock added” display bug that divided production kilograms by 100 a second time. Data sources: `ice_pack_movements` with reason `production` and nonvoided `ice_sales`. Existing report loads at most 5,000 production movement records and 5,000 sales records; large-history completeness/pagination needs follow-up.

**Verification limits:** At time of implementation Vercel was BUILDING; check latest deployment status. No live sales or stock were changed. Authenticated functional and mobile testing remain pending.

### Daily expenses and profit
**Customer request:** Record daily expenses with details and amount; allow deletion; compare sales and expenses to show profit.

**Implementation:** `014_ice_expenses.sql`, `src/IceExpenses.tsx`, and `src/IceSalesReports.tsx`; commits `0935e4c`, `e2c779b`, `adf0b1d`. Migration applied to production. Ice temples expenses are store-scoped and RLS-protected; the UI supports add/edit/delete and date-filtered totals. Report displays `sales − expenses` (a simple operating difference, **not** full accounting profit). Vercel commit `adf0b1d` was READY.

**Important:** Expense delete currently hard-deletes records. Consider soft delete with audit history before using as an accounting source of truth. Do not extend expenses to all stores without explicit approval and tenant-isolation review. Shared application code must never mean shared store data.

## Operating rules from this feedback

- Real customer feedback should be logged here with the original request, interpretation, decision, code/migration references, and verification status.
- Never create dummy production sales, expenses, inventory adjustments, or customer accounts merely to test a feature.
- Preserve transactional stock accuracy, store isolation, auditability and clear distinctions between production, sales, corrections and voids.
- Verify deployments and tests separately. Keep unresolved limitations visible; do not silently mark them complete.
- Before implementing new feedback, inspect current repository code, Supabase RPCs/RLS, and any affected production data shape.

## 2026-11-23 — Super Admin platform audit dashboard

**Owner request:** Add a weekly technical audit covering app, database, security and infrastructure, with a Super Admin dashboard, detailed reports and graphs.

**Phase 1 implementation:** `src/PlatformAudit.tsx` and Super Admin navigation in `src/main.tsx`, commits `c127f0d` and `c3870b3`. Read-only store operational snapshot: 30-day retail/ice sales and revenue, inventory/product counts, out-of-stock counts, store breakdown, and daily revenue chart. Data is read through signed-in Supabase permissions. Sales lists are capped at 1,000 per store/type and warn on truncation. No new SQL migrations or data writes.

**Outstanding:** Confirm deployment READY and authenticated UI behavior. Add privileged server-side observability integration for Vercel runtime/deployments, Supabase query health/slow queries/indexes, GitHub CI and dependency security; store weekly historical snapshots and trend charts; schedule the weekly audit after confirming time. Do not mistake this dashboard for completed infrastructure monitoring. Do not place privileged monitoring tokens in browser code.

## 2026-11-23 — Ice temples customer receivables / end-of-month collections

**Emmanuel request:** Sales checkout under Delivered By offers Paid / Not Paid. Delivered stock is deducted even when unpaid. Unpaid delivery list, outstanding balance by customer/store, all-time total to collect, date filtering, Mark Paid button. Most stores settle at month end, but some make partial payments.

**Implementation:** `015_ice_receivables.sql` and `016_disable_legacy_ice_checkout.sql` applied to production. New `ice_sales.paid_cents` with historical records backfilled as paid; payment ledger `ice_sale_payments`; atomic payment-aware `ice_checkout_packs_receivable` and partial/full `ice_record_payment` RPC. Legacy checkout RPC execute privilege revoked to enforce explicit payment status. Guard prevents voiding or changing totals after payments. `src/IceTemples.tsx` checkout paid/unpaid toggle; `src/IceReceivables.tsx` date/customer filters, per-store and all-time balances, partial and full settlement, recent payment history; `src/IceSalesReports.tsx` payment status and collections section. No test sales, stock mutations or payments made.

**Limitations:** Full-balance button is per delivery; paying an entire customer's multiple deliveries in one atomic action is not yet implemented. Payment history lists 500 most recent collection payments; paid-at-checkout payments are not in that ledger. Receivables calculation refuses to claim completeness beyond 20,000 loaded sales. Sale corrections are disabled in UI for outstanding bills until a payment-aware correction workflow is added. No refunds/payment reversal UI. Verify production deployment and authenticated flows before customer acceptance.

## 2026-11-23 — Financial accuracy is a release-blocking priority

**Owner priority:** Real clients may abandon the product if sales, profits, expenses, collections, or stock do not match reliable spreadsheet records. Financial integrity is more important than feature velocity.

**Acceptance requirements for future work:**
- Clearly distinguish sales/revenue, cash received, outstanding receivables, expenses and accounting profit; do not label sales minus recorded expenses as full accounting profit without complete cost coverage.
- Reconcile per-sale balances: amount due = sale total − recorded payments; never count settlement as a new sale or deduct stock twice.
- Reconcile inventory: opening stock + production + corrections + void returns − sold packs = closing stock, with an auditable movement trail.
- Test checkout, partial payments, full payments, duplicate requests, simultaneous payments, void/correction restrictions, date boundaries, rounding, cross-store access and report export.
- Maintain an isolated test environment with known expected totals. Compare outputs against independent spreadsheet/manual calculations before release.
- Make discrepancies visible, not silently adjusted. Preserve historical entries and use audit-backed corrections.
- Never run synthetic sales/payments or destructive fixes in production.

**Known risks to resolve:** current report's “Profit (sales − expenses)” is not necessarily accounting profit; legacy sales were initialized as paid during receivables migration; collection payments and paid-at-checkout amounts need consistent reporting; corrections/voids require payment-aware workflows; some report queries have pagination limits. Build/deployment success is not proof of financial correctness.

## 2026-11-23 — Emmanuel: historical sales dates

Customer reports no bugs so far and requests entering previous sales with editable transaction dates. Added `ice_sales.sale_date` (Philippine business date), a checkout date picker, audited `ice_change_sale_date` RPC, and sales/collections filters and CSV using the business date. `created_at` remains the immutable entry timestamp. Backfill uses existing Philippine created date. Allowed dates 2020-01-01 through today, with no future dates. Existing real sales untouched except date backfill. Caveat: backdated sales still deduct **current** pack stock, and do not reconstruct historical inventory snapshots. Production financial reconciliation and authenticated regression testing remain pending.
