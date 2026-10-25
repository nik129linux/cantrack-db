-- 005: deleting a walker account must not erase the OWNERS' history (Ley 1581 deletion, W5).
-- Before: walk_requests.walker_id -> walker_profiles ON DELETE CASCADE and checkouts.walker_id ->
-- auth.users ON DELETE CASCADE, so removing one walker deleted every owner's walk and walk report
-- that walker had touched. Now the rows stay and only lose the link to the walker.
-- The API also detaches the rows itself before deleting; this is the database-side guarantee.
begin;

alter table public.walk_requests drop constraint if exists walk_requests_walker_id_fkey;
alter table public.walk_requests add constraint walk_requests_walker_id_fkey
  foreign key (walker_id) references public.walker_profiles (walker_id) on delete set null;

alter table public.checkouts alter column walker_id drop not null;
alter table public.checkouts drop constraint if exists checkouts_walker_id_fkey;
alter table public.checkouts add constraint checkouts_walker_id_fkey
  foreign key (walker_id) references auth.users (id) on delete set null;

commit;
