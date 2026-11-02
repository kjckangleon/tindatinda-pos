-- Run once in Supabase SQL Editor before using Subscription Management.
create table if not exists public.user_subscriptions (
 user_id uuid primary key references auth.users(id) on delete cascade,
 plan text not null check (plan in ('trial','monthly','quarterly','annual','lifetime','custom')),
 starts_at timestamptz not null default now(),
 expires_at timestamptz,
 amount_cents bigint not null default 0 check (amount_cents >= 0),
 payment_method text not null default 'manual',
 notes text not null default '',
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null,
 constraint lifetime_has_no_expiry check ((plan = 'lifetime') = (expires_at is null))
);
create table if not exists public.subscription_payments (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 plan text not null,
 amount_cents bigint not null check (amount_cents >= 0),
 payment_method text not null,
 notes text not null default '',
 starts_at timestamptz not null,
 expires_at timestamptz,
 recorded_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
alter table public.user_subscriptions enable row level security;
alter table public.subscription_payments enable row level security;
revoke all on public.user_subscriptions from anon,authenticated;
revoke all on public.subscription_payments from anon,authenticated;
-- Service-role API handles all reads/writes after verifying platform_admins.
