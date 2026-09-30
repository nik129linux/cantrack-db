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
