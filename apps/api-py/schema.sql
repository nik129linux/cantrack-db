-- CanTrack database schema for Supabase Postgres.
-- Run this once against the project's SQL Editor (or via `psql`/migration tool).
-- Column names/types match exactly what apps/api-py/src/cantrack_api/routers/{dogs,routes}.py query —
-- this file is the source of truth for the schema those routers assume exists.

create extension if not exists vector;

create table if not exists public.dogs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  breed text,
  notes text,
  embedding vector(512),
  created_at timestamptz not null default now()
);

create index if not exists dogs_owner_id_idx on public.dogs (owner_id);

create table if not exists public.routes (
  id uuid primary key default gen_random_uuid(),
  walker_id uuid not null references auth.users (id) on delete cascade,
  stops jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists routes_walker_id_idx on public.routes (walker_id);

create table if not exists public.checkins (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes (id) on delete cascade,
  dog_id uuid not null references public.dogs (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists checkins_route_id_idx on public.checkins (route_id);

-- RLS is ENABLED with NO policies on purpose. The publishable/anon key ships inside the web bundle,
-- so anyone can call the REST API of this project directly; with RLS on and no policy those calls get
-- nothing. The API uses the service-role key, which bypasses RLS, and enforces access control itself
-- (every query is scoped by the caller's id). The browser never reads these tables: it only uses
-- supabase.auth for login. If the web app ever needs direct table access, add explicit policies first.
alter table public.dogs enable row level security;
alter table public.routes enable row level security;
alter table public.checkins enable row level security;

-- S1: the marketplace — walker profiles, the dog questionnaire and walk requests.
-- Column names/types match what apps/api-py/src/cantrack_api/routers/{walker_profiles,requests}.py
-- and the dogs profile endpoint query.

create table if not exists public.walker_profiles (
  walker_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  bio text,
  service_area text,
  price_per_walk integer not null check (price_per_walk >= 0),
  created_at timestamptz not null default now()
);

-- The S1 questionnaire (8 answers, validated by pydantic in the API):
-- size, temperament, energy, leash_trained, allergies, medical_notes,
-- vet_contact, emergency_contact.
alter table public.dogs add column if not exists profile jsonb;

create table if not exists public.walk_requests (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  walker_id uuid not null references public.walker_profiles (walker_id) on delete cascade,
  dog_id uuid not null references public.dogs (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  requested_time timestamptz not null,
  pickup_lat double precision not null,
  pickup_lng double precision not null,
  price_cop integer not null,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create index if not exists walk_requests_owner_id_idx on public.walk_requests (owner_id);
create index if not exists walk_requests_walker_status_idx on public.walk_requests (walker_id, status);
create index if not exists walk_requests_dog_status_idx on public.walk_requests (dog_id, status);

alter table public.walker_profiles enable row level security;
alter table public.walk_requests enable row level security;

-- S3: checkout with photos to the owner, the AI usage log and the private photo bucket.
-- Column names/types match exactly what apps/api-py/src/cantrack_api/routers/checkouts.py queries.
-- NOTE (PR 2 of S3): Nico runs this file by hand in the Supabase SQL Editor before the API is
-- deployed; the bucket insert needs the storage schema, which only exists on a real project.

-- note and ai_note are SEPARATE columns on purpose (PR #8 review): ai_note is what the vision
-- model said (read-only provenance), note is the walker's own text (the only field PATCH writes,
-- the only one the owner ever sees). dog_visible/ai_status carry the model's last answer state.
create table if not exists public.checkouts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.walk_requests (id) on delete cascade,
  dog_id uuid not null references public.dogs (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  walker_id uuid not null references auth.users (id) on delete cascade,
  photo_paths jsonb not null default '[]'::jsonb,
  ai_note text,
  note text,
  dog_visible boolean,
  ai_status text not null check (ai_status in ('ok', 'unavailable', 'quota')),
  status text not null default 'draft' check (status in ('draft', 'sent')),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  -- One checkout per request: the API's 409 is a check-then-insert, and two tabs (or a
  -- double tap on a flaky network) would otherwise race two drafts for the same walk.
  unique (request_id)
);

create index if not exists checkouts_owner_status_sent_idx on public.checkouts (owner_id, status, sent_at desc);
create index if not exists checkouts_walker_created_idx on public.checkouts (walker_id, created_at desc);
create index if not exists checkouts_dog_status_idx on public.checkouts (dog_id, status);

-- The AI quota counts CALLS, attributed by the time of each call (not by the checkout's
-- created_at): one row per answered vision call, 60 per walker per UTC calendar month.
create table if not exists public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  walker_id uuid not null references auth.users (id) on delete cascade,
  used_at timestamptz not null default now()
);

create index if not exists ai_usage_walker_used_idx on public.ai_usage (walker_id, used_at);

alter table public.checkouts enable row level security;
alter table public.ai_usage enable row level security;

-- The checkout photos live in a PRIVATE bucket; the API serves them only as signed URLs
-- (3600 s) and never calls get_public_url. Idempotent: re-running this file is safe.
insert into storage.buckets (id, name, public)
values ('checkout-photos', 'checkout-photos', false)
on conflict (id) do nothing;

-- S4: walk bidding (FR-23..FR-27). Column names match routers/bidding.py.
alter table public.walk_requests drop constraint if exists walk_requests_status_check;
alter table public.walk_requests add constraint walk_requests_status_check
  check (status in ('pending', 'accepted', 'declined', 'cancelled',
                    'open', 'assigned', 'in_walk', 'done', 'expired'));
alter table public.walk_requests alter column walker_id drop not null;
alter table public.walk_requests add column if not exists duration_hours double precision not null default 1.0;
alter table public.walk_requests add column if not exists window_end timestamptz;
alter table public.walk_requests add column if not exists deadline_at timestamptz;

create table if not exists public.walk_offers (
  id uuid primary key default gen_random_uuid(),
  walk_request_id uuid not null references public.walk_requests (id) on delete cascade,
  walker_id uuid not null references auth.users (id) on delete cascade,
  price_cop integer not null check (price_cop >= 0),
  eta_min double precision not null check (eta_min >= 0),
  distance_km double precision not null check (distance_km >= 0),
  created_at timestamptz not null default now(),
  unique (walk_request_id, walker_id)
);
create index if not exists walk_offers_request_idx on public.walk_offers (walk_request_id);

create table if not exists public.walker_positions (
  walker_id uuid primary key references auth.users (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.dog_pack_links (
  id uuid primary key default gen_random_uuid(),
  dog_a uuid not null references public.dogs (id) on delete cascade,
  dog_b uuid not null references public.dogs (id) on delete cascade,
  unique (dog_a, dog_b)
);

create table if not exists public.walk_graph_edges (
  id uuid primary key default gen_random_uuid(),
  from_stop text not null,
  to_stop text not null,
  minutes double precision not null check (minutes >= 0)
);
create index if not exists walk_graph_edges_from_idx on public.walk_graph_edges (from_stop);

create table if not exists public.walk_route_stops (
  id uuid primary key default gen_random_uuid(),
  walk_request_id uuid not null references public.walk_requests (id) on delete cascade,
  dog_id uuid not null references public.dogs (id) on delete cascade,
  stop_key text not null,
  pickup_time timestamptz not null,
  position integer not null
);
create index if not exists walk_route_stops_request_idx on public.walk_route_stops (walk_request_id);

create table if not exists public.walker_cancel_buckets (
  walker_id uuid primary key references auth.users (id) on delete cascade,
  remaining integer not null check (remaining >= 0),
  period_start timestamptz not null default now()
);

create table if not exists public.walk_ratings (
  id uuid primary key default gen_random_uuid(),
  walk_request_id uuid not null references public.walk_requests (id) on delete cascade,
  walker_id uuid not null references auth.users (id) on delete cascade,
  rating double precision not null check (rating >= 1 and rating <= 5),
  created_at timestamptz not null default now(),
  unique (walk_request_id)
);
create index if not exists walk_ratings_walker_idx on public.walk_ratings (walker_id, created_at desc);

create table if not exists public.walk_timeline (
  id uuid primary key default gen_random_uuid(),
  walk_request_id uuid not null references public.walk_requests (id) on delete cascade,
  kind text not null,
  at timestamptz not null,
  payload jsonb not null default '{}'::jsonb
);
create index if not exists walk_timeline_request_idx on public.walk_timeline (walk_request_id, at);

create table if not exists public.walk_gps_points (
  id uuid primary key default gen_random_uuid(),
  walk_request_id uuid not null references public.walk_requests (id) on delete cascade,
  at_epoch double precision not null,
  lat double precision not null,
  lng double precision not null
);
create index if not exists walk_gps_points_request_idx on public.walk_gps_points (walk_request_id, at_epoch);

alter table public.walk_offers enable row level security;
alter table public.walker_positions enable row level security;
alter table public.dog_pack_links enable row level security;
alter table public.walk_graph_edges enable row level security;
alter table public.walk_route_stops enable row level security;
alter table public.walker_cancel_buckets enable row level security;
alter table public.walk_ratings enable row level security;
alter table public.walk_timeline enable row level security;
alter table public.walk_gps_points enable row level security;
-- RLS stays policy-free on purpose (service-role API + caller-scoped queries, same as S1); the RLS audit is Plan 3.

-- Owner tabs (same SQL as migrations/002_owner_tabs.sql).
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

-- =============================================================================
-- PR0 security: RLS is DENY-ALL again (no policies on any table).
--
-- The 2026-10-13 "defence in depth" policies were `for all`, so with the anon key
-- that ships in the web bundle plus their own login token a user could write
-- straight to Supabase REST and skip every business rule: set a walk to done,
-- change its price, refill their cancel tokens, delete their AI usage, rate
-- themselves 5 stars, edit an offer after bidding, fake GPS history.
--
-- The browser only uses supabase.auth (login); it never reads or writes a table.
-- The API uses the service-role key, which bypasses RLS, and scopes every query
-- to the caller. With RLS enabled and no policy, anon/authenticated get nothing.
-- If the web app ever needs direct table access, add a narrow `for select`
-- policy for that one table, never `for all`.
--
-- The drops keep this file idempotent and remove the old policies from a
-- database that already has them (same SQL as migrations/001_deny_all_rls.sql).
-- =============================================================================
drop policy if exists "dogs_owner_all" on public.dogs;
drop policy if exists "routes_walker_all" on public.routes;
drop policy if exists "checkins_via_route" on public.checkins;
drop policy if exists "walker_profiles_self" on public.walker_profiles;
drop policy if exists "walk_requests_party" on public.walk_requests;
drop policy if exists "checkouts_party" on public.checkouts;
drop policy if exists "ai_usage_walker" on public.ai_usage;
drop policy if exists "walk_offers_party" on public.walk_offers;
drop policy if exists "walker_positions_self" on public.walker_positions;
drop policy if exists "dog_pack_links_via_dog" on public.dog_pack_links;
drop policy if exists "walk_graph_edges_read" on public.walk_graph_edges;
drop policy if exists "walk_route_stops_via_request" on public.walk_route_stops;
drop policy if exists "walker_cancel_buckets_self" on public.walker_cancel_buckets;
drop policy if exists "walk_ratings_party" on public.walk_ratings;
drop policy if exists "walk_timeline_via_request" on public.walk_timeline;
drop policy if exists "walk_gps_points_via_request" on public.walk_gps_points;
