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

-- RLS: the API uses the service-role key (bypasses RLS), so these tables can stay
-- with RLS disabled for now — access control is enforced in apps/api-py's routers,
-- not at the Postgres layer. Revisit before anything but the API talks to this DB
-- directly (e.g. if apps/web is ever given direct table access with the anon key).
alter table public.dogs disable row level security;
alter table public.routes disable row level security;
alter table public.checkins disable row level security;

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

alter table public.walker_profiles disable row level security;
alter table public.walk_requests disable row level security;
