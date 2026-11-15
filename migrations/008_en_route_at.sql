-- 008: the moment the walker tapped "Voy en camino" on an assigned walk.
-- Until then the owner cannot see where the walker is; from then until check-in the owner
-- sees the walker's position and the street route to the pickup. Null = not on the way yet.
-- NOT applied live: run it with the Supabase SQL editor or psql before deploying the backend.
begin;

alter table public.walk_requests add column if not exists en_route_at timestamptz;

comment on column public.walk_requests.en_route_at is
  'When the assigned walker tapped "Voy en camino"; the owner may follow the approach from then until check-in.';

commit;
