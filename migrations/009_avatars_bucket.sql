-- Private owner/walker avatars and dog reference photos, also required on a new project.
-- Existing deployments already created this bucket using the backend SQL runbook.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;
