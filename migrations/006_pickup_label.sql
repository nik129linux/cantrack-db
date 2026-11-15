-- 006: the address text the owner picked for a walk request (InDrive-style pickup field).
-- pickup_lat/pickup_lng stay the source of truth; the label is only what the walker reads.
begin;

alter table public.walk_requests add column if not exists pickup_label text
  check (char_length(pickup_label) <= 120);

commit;
