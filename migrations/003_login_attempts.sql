-- 003: failed-login counter for the per-email lockout (5 failures / 15 min -> 15 min lock).
-- Keyed by sha256(lower(trim(email))): the raw email is never stored, and unknown emails
-- lock exactly like real ones, so the table cannot be used to enumerate accounts.
-- RLS on, no policy (deny-all), service-role access only.
begin;

create table if not exists public.auth_login_attempts (
  email_hash text primary key check (char_length(email_hash) = 64),
  failed_count integer not null default 0 check (failed_count >= 0),
  first_failed_at timestamptz,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.auth_login_attempts enable row level security;

commit;
