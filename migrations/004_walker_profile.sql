-- 004: walker Perfil (W5). Phone, private avatar, Ley 1581 consent record, last edit time.
-- Same shape and bounds as owner_profiles. RLS stays deny-all (service-role access only).
begin;

alter table public.walker_profiles add column if not exists phone text check (char_length(phone) <= 24);
alter table public.walker_profiles add column if not exists avatar_path text;
alter table public.walker_profiles add column if not exists consent_version text check (char_length(consent_version) <= 20);
alter table public.walker_profiles add column if not exists consent_at timestamptz;
alter table public.walker_profiles add column if not exists updated_at timestamptz not null default now();

commit;
