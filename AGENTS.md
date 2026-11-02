# AI Agent Guide — TindaTinda POS

**Read this file and [README.md](./README.md) before making changes.** Treat repository code and SQL as source of truth; do not assume documentation is more current than implementation.

## Project objective
A responsive, multi-tenant sari-sari store POS SaaS with centralized platform administration and isolated store data. Production is https://tindatinda-pos.vercel.app.

## Stack and structure
- React 18 + TypeScript + Vite in `src/main.tsx` (currently a large single-file UI); styles in `src/style.css`.
- Supabase Auth, PostgreSQL RLS, RPC functions, Storage.
- Vercel serverless API in `api/admin/`; secrets remain server-side.
- SQL: `supabase/schema.sql` and migrations in `supabase/migrations/`.
- Vitest unit tests in `tests/`; Playwright tests in `e2e/`; GitHub Actions `.github/workflows/regression.yml`.

## First steps for an agent
1. Read `README.md`, this file, `package.json`, and the files relevant to the requested change.
2. Inspect current code and SQL before proposing changes; do not infer behavior from labels alone.
3. Identify affected user roles, store isolation boundaries, and database permissions.
4. Make the smallest safe change; add regression tests for the bug or feature.
5. Run `npm run build`, `npm run test:unit`, and `npm run test:e2e` where available.
6. Review CI and deployment status; never claim tests/deployment passed unless verified.
7. Summarize files changed, test results, migration requirements, and remaining limitations.

## Invariants — do not break
- **Tenant isolation:** every store-scoped operation must be authorized for the current store. A user may belong to multiple stores.
- **Authorization:** do not trust client-side role checks. Validate sessions and roles in server API / RLS / RPCs.
- **Secrets:** `SUPABASE_SERVICE_ROLE_KEY` is server-only. Never expose it through `VITE_*`, client code, test artifacts, output, or commits.
- **Money:** integer centavos in database/API; format PHP only for display.
- **Checkout:** preserve atomic `checkout_cash` RPC behavior, row locks, stock checks, sale lines, inventory movements, and UUID idempotency.
- **Subscriptions:** manual plan and payment recording; do not assert expiry blocks access without implementing and testing enforcement.
- **Existing data:** no production resets, destructive migrations, bulk deletes, or credential changes without explicit user authorization.
- **Accessibility/mobile:** test controls at mobile widths; actions should have visible feedback. The Registered Users Assign button prepopulates and scrolls to Store Access; a separate submit saves.
- **Test isolation:** no live production Auth user creation, store mutations, payments, or sales in automated tests.

## Important flows and entrypoints
- Login and store selection: `src/main.tsx`, Supabase Auth, `stores` RLS.
- Super Admin role: `is_platform_admin` RPC, `/api/admin/me`, `src/lib/admin-role.ts`.
- Store creation: `admin_create_store` SQL RPC.
- Store membership: `admin_assign_store_member`, `admin_list_store_members`, `admin_remove_store_member` SQL RPCs; inspect migrations/current schema for definitions.
- User creation: `/api/admin/create-user` with Bearer session + secret-backed Auth admin client.
- Registered users: `GET /api/admin/subscriptions?scope=users` (independent of subscription table).
- Subscriptions: `GET/POST /api/admin/subscriptions`; `GET ?scope=me` for signed-in user's plan; migrations 003.
- Product photos: browser compresses to WebP <=256 KiB, Supabase Storage `product-images`, migration 004.
- Checkout: `checkout_cash` SQL RPC; `sales`, `sale_lines`, `products`, `inventory_movements`.

## Regression testing guidance
- `npm run build`: TypeScript + Vite.
- `npm run test:unit`: Vitest `tests/` only; **do not allow Vitest to discover `e2e/*.spec.ts`**.
- `npm run test:e2e`: Playwright `e2e/` only. Desktop Chromium + mobile-sized Chromium.
- CI uses placeholders for unauthenticated smoke tests. Do not insert production Supabase keys into CI.
- Add isolated Supabase test environment before testing authenticated role management, subscription writes, or checkout.
- Test positive and negative permissions, invalid sessions, cross-store access, double checkout, stock limits, mobile scroll/interaction, and renewal expiry behavior as coverage expands.
- GitHub connector commits may not automatically start CI; manual workflow dispatch is enabled.

## Common pitfalls already encountered
- Missing `package-lock.json` caused GitHub Actions setup-node cache failure. Current CI does **not** enable npm caching and uses `npm install`, not `npm ci`.
- Vitest initially collected Playwright specs; fixed by `vitest run tests`.
- Admin role verification may differ between authenticated RPC and server API if server credentials/config are wrong. Do not silently grant privileges based on a UI flag.
- Registered Users should fetch `?scope=users` without depending on migration 003 subscription tables.
- The Registered Users **Assign** shortcut must scroll to the Store Access form; it does not save access by itself.
- Migration 003 must exist before subscription management works. Existing migrations may already have been applied.

## Documentation upkeep
Update both `README.md` and `AGENTS.md` when changing architecture, setup, commands, access control, schema, API behavior, or CI. Avoid invented functionality or unverified deployment claims.
