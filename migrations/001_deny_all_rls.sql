-- 001: return every RLS table to deny-all (drop the `for all` policies of 4454cd1).
-- Safe to re-run. Verify afterwards with:
--   select count(*) from pg_policies where schemaname = 'public';   -- expect 0
begin;
drop policy if exists "dogs_owner_all" on public.dogs;
drop policy if exists "routes_walker_all" on public.routes;
drop policy if exists "checkins_via_route" on public.checkins;
drop policy if exists "walker_profiles_self" on public.walker_profiles;
drop policy if exists "walk_requests_party" on public.walk_requests;
drop policy if exists "checkouts_party" on public.checkouts;
drop policy if exists "ai_usage_walker" on public.ai_usage;
drop policy if exists "walk_offers_party" on public.walk_offers;
drop policy if exists "walker_positions_self" on public.walker_positions;
drop policy if exists "dog_pack_links_via_dog" on public.dog_pack_links;
drop policy if exists "walk_graph_edges_read" on public.walk_graph_edges;
drop policy if exists "walk_route_stops_via_request" on public.walk_route_stops;
drop policy if exists "walker_cancel_buckets_self" on public.walker_cancel_buckets;
drop policy if exists "walk_ratings_party" on public.walk_ratings;
drop policy if exists "walk_timeline_via_request" on public.walk_timeline;
drop policy if exists "walk_gps_points_via_request" on public.walk_gps_points;
commit;
