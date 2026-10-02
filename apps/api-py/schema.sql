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
