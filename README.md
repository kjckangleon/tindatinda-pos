# TindaTinda POS

Multi-tenant point-of-sale MVP for sari-sari stores in the Philippines. **Read [AGENTS.md](./AGENTS.md) before modifying the project.**

- Production: https://tindatinda-pos.vercel.app
- Stack: React 18, TypeScript, Vite 6, Supabase Auth/PostgreSQL/Storage, Vercel serverless API, Vitest, Playwright
- Currency: Philippine pesos; database prices, payments and totals are **integer centavos**, not floating-point pesos.

## How it works

1. A user signs in with Supabase email/password authentication. Accounts are provisioned by authorized administrators.
2. The app reads stores available to the user and checks platform-admin permissions using the `is_platform_admin` RPC and `/api/admin/me`.
3. The **Super Admin** can create stores, create users, assign or remove store memberships, view registered users, and manage manual subscriptions.
4. A store member selects an accessible store. Each store has separate products, stock, sales, and staff memberships.
5. Owners/managers can manage products and staff (manager-created accounts are limited to cashiers). Cashiers can operate checkout. Access is enforced by PostgreSQL RLS and database functions, not just hidden UI.
6. Checkout calls the `checkout_cash` SQL function with a UUID idempotency key. The database locks product rows, validates stock and payment, creates a sale and sale lines, deducts stock, and records inventory movements atomically.
7. Subscription management is **manual**: a platform admin records plans/payments. Users see expiry reminders. **Do not assume the current UI enforces subscription-based access denial**.

## User roles

| Role | Scope | Intended access |
| --- | --- | --- |
| Platform Super Admin | All stores | Provision stores/users, assign store access, manage subscriptions |
| Store owner | Assigned store(s) | Manage products and store staff, use POS |
| Store manager | Assigned store(s) | Manage products, create cashier accounts, use POS |
| Cashier | Assigned store(s) | Use POS and read permitted store data |

One user may belong to multiple stores. A store can be created without an owner; assign an existing Auth user afterward via **Super Admin → Store Access**. The Registered Users **Assign** shortcut fills and scrolls to that form; saving requires **Assign / Update Access**.

## Core features

- Login/logout and account password change
- Super Admin: stores, Auth user provisioning, registered-user directory, store membership assignment/removal
- Product catalog with optional barcodes and client-compressed WebP photos (up to 256 KiB)
- Cart, cash checkout, change calculation, stock decrement, sale history
- Manual plans: trial (7 days), monthly, quarterly, annual, lifetime, custom; payment ledger and expiry reminders
- Responsive desktop/mobile UI
- Automated build, unit tests and unauthenticated desktop/mobile browser smoke tests

**Not yet implemented / not guaranteed:** camera barcode scanning, offline sales, receipt printing, refunds, payment gateway/webhooks, automated invitations, complete audit logs, production-grade observability, and full authenticated end-to-end regression coverage.

## Architecture

```text
Browser (React/Vite)
  ├─ Supabase Auth → user session
  ├─ Supabase PostgreSQL → stores/products/sales via RLS
  ├─ Supabase RPC → is_platform_admin, admin_create_store,
  │                  admin_assign_store_member, checkout_cash, etc.
  ├─ Supabase Storage → public product-images bucket
  └─ Vercel /api/admin/* → privileged user/subscription operations
                                └─ server-side Supabase secret key
```

Main locations:
- `src/main.tsx`: application UI and most state/flows
- `src/style.css`: responsive styling
- `src/lib/admin-role.ts`: admin-role resolver
- `api/admin/me.js`: current-user platform role verification
- `api/admin/create-user.js`: privileged Auth user provisioning
- `api/admin/subscriptions.js`: registered-user directory and subscription management
- `supabase/schema.sql`: initial database schema, RLS and RPCs
- `supabase/migrations/003_user_subscriptions.sql`: subscription tables
- `supabase/migrations/004_product_images.sql`: product image column/storage policies
- `supabase/migrations/005_fix_platform_admin_read.sql`: authenticated admin-role read permissions
- `tests/`: Vitest unit tests
- `e2e/`: Playwright browser tests
- `.github/workflows/regression.yml`: CI

## Development

Requirements: Node.js 22 and npm.

```bash
npm install
npm run dev
npm run build
npm run test:unit
npx playwright install chromium
npm run test:e2e
```

Create a local `.env.local` (never commit it):

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_SUPABASE_KEY
```

For Vercel, set those two public variables plus **`SUPABASE_SERVICE_ROLE_KEY`** in server-side environment settings. Never prefix the secret key with `VITE_`, expose it to the browser, paste it in logs, or commit it. Deploying changes to environment variables may require a redeployment.

### Database bootstrap

For a **new** Supabase project:
1. Execute `supabase/schema.sql` in the Supabase SQL Editor.
2. Create the first platform administrator in Supabase Authentication.
3. Insert that Auth user's UUID into `public.platform_admins` using a privileged SQL session.
4. Apply applicable migrations under `supabase/migrations/` in order (003, 004, 005). Inspect migration contents and current database state before rerunning; not all statements are idempotent.
5. Set the Vercel environment variables and deploy.

**Never run schema resets or destructive SQL against production without explicit approval and backups.** Existing databases may already have some migrations applied.

### Tests and CI

`.github/workflows/regression.yml` supports manual `workflow_dispatch`, PRs and pushes to `main`. It runs:
1. `npm install`
2. `npm run build`
3. `npm run test:unit` (Vitest is scoped to `tests/`)
4. Install Playwright Chromium and run `npm run test:e2e` (Playwright is scoped to `e2e/`)

Browser smoke tests use **placeholder Supabase configuration** and do not write to production. Both desktop Chromium and mobile-sized Chromium are covered; the mobile profile is not a real iPhone/Safari test. For authenticated, store-assignment, subscription or checkout E2E tests, create an isolated Supabase test project and fixtures first. Passing current CI does **not** prove all POS workflows work.

GitHub API-authored commits may not trigger push workflows; use **Actions → Regression tests → Run workflow → main** if necessary. Protect `main` with required status checks when feasible.

## Security and operational notes

- RLS and security-definer RPCs are the authorization boundary; frontend role checks are only UX.
- The server-side Supabase secret key is privileged: never use it client-side.
- API endpoints must authenticate the Bearer session and verify authorization before privileged operations.
- Product photos are stored in a **public** bucket; do not upload sensitive images.
- No automatic payment processing: subscription amounts/methods are manually entered.
- Review existing schema, RPCs and policies before altering access control or checkout semantics.
- Consult [AGENTS.md](./AGENTS.md) for agent-specific working rules and regression checklist.
