-- 002: tables and columns for the owner tabs (Inicio, Explorar, Mis paseos, Perfil).
-- Additive only. RLS enabled with NO policy (deny-all for anon/authenticated, see 001):
-- the API reads and writes these with the service-role key, scoped to the caller.
-- Verify afterwards:
--   select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;   -- expect 0
begin;

-- Perfil (PR4): one row per owner. display_name is nullable because consent can be
-- recorded before the owner fills in a name.
create table if not exists public.owner_profiles (
  owner_id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) between 1 and 80),
  phone text check (char_length(phone) <= 24),
  avatar_path text,
  home_lat double precision check (home_lat between -90 and 90),
  home_lng double precision check (home_lng between -180 and 180),
  home_label text check (char_length(home_label) <= 120),
  consent_version text check (char_length(consent_version) <= 20),
  consent_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.owner_profiles enable row level security;

-- Explorar (PR2): the typed-request assistant's daily quota, reserved before each call.
create table if not exists public.owner_ai_usage (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  feature text not null default 'request_parse',
  used_at timestamptz not null default now()
);
create index if not exists owner_ai_usage_owner_used_idx on public.owner_ai_usage (owner_id, used_at);
alter table public.owner_ai_usage enable row level security;

-- Mis paseos (PR3): the walk report, written once at check-out (FR-21).
alter table public.walk_requests add column if not exists report_status text
  check (report_status in ('ok', 'unavailable', 'disabled'));
alter table public.walk_requests add column if not exists report_text text
  check (char_length(report_text) <= 600);
alter table public.walk_requests add column if not exists report_distance_km double precision
  check (report_distance_km >= 0);
alter table public.walk_requests add column if not exists report_duration_min integer
  check (report_duration_min >= 0);

commit;
