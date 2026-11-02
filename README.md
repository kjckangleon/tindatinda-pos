# TindaTinda POS

Multi-tenant sari-sari store POS MVP powered by React, Supabase and Vercel.

## Setup
1. Create a Supabase project.
2. Run `supabase/schema.sql` in the SQL Editor.
3. Create the initial administrator in Supabase Auth (email/password), then insert their UUID into `platform_admins` using the SQL editor. **Never put the service-role key in Vercel frontend environment variables.**
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Vercel. These are public browser configuration values, not service-role credentials.
5. Deploy the Vite project to Vercel.

## MVP status
- Email/password login, super-admin store provisioning, store selection, product management, keyboard-wedge barcode input, and cash checkout.
- Store isolation is enforced with PostgreSQL row-level security.
- Checkout uses an atomic database function with idempotency key and stock locking.
- Camera scanning, offline sales, receipt printing, subscriptions and automated staff invitations are not implemented yet.
- For production, add audit logging, rate limits, invitation flows, tests, refunds, and full operational monitoring.
