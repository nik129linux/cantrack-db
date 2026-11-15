-- 007: how the owner will pay a walk, chosen when publishing the request; shown to walkers.
-- Same statement as cantrack-backend docs/sql/2026-11-14_walk_request_payment_method.sql
-- (already applied live); kept here so a fresh database gets it from migrations/.
begin;

alter table public.walk_requests add column if not exists payment_method text
  check (payment_method in ('cash', 'nequi', 'card'));

comment on column public.walk_requests.payment_method is
  'How the owner will pay this walk (cash, nequi, card); shown to walkers on the request card.';

commit;
