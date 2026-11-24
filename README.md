# CanTrack Database

Supabase PostgreSQL schema, pgvector extension, row-level security and numbered migrations.

## Fresh Supabase project

Run `apps/api-py/schema.sql` using an administrative connection to the new Supabase project.
It includes the accumulated table definitions and private `checkout-photos` and `avatars`
storage buckets. The `avatars` bucket holds profile and dog reference photos.
The schema expects Supabase's `auth` and `storage` schemas; it is not a plain PostgreSQL bootstrap.

## Existing project

Review and run only missing migrations in order, `001` through `009`.
Migration `009` records the avatar bucket previously created by a backend SQL runbook.
Legacy profile, dog-note and walker-experience additions are also recorded under `supplemental/`;
review those when upgrading an older database. They are already included in the fresh schema.
The application must access private data through its authenticated backend; the service-role
key stays server-side. Never expose it in frontend variables.

The repository does not contain production Auth users, uploaded photos, passwords, or a data backup.
Authentication provider settings and email redirect URLs must be configured separately.
No SQL in this delivery was applied to production during source synchronization.

## Tests

Clone this repository beside `cantrack-backend`, keeping the directory name `cantrack-db`.
The backend's strict Supabase fake reads `apps/api-py/schema.sql` during its test suite.

## Project repositories

| Component | Repository |
|---|---|
| Complete source | https://github.com/nik129linux/cantrack |
| Frontend | https://github.com/nik129linux/cantrack-frontend |
| Backend | https://github.com/nik129linux/cantrack-backend |
| Database | https://github.com/nik129linux/cantrack-db |
| AI package | https://github.com/nik129linux/cantrack-ai |
