-- Closes two Supabase security-advisor WARNs: handle_new_user() is a trigger
-- function, but SECURITY DEFINER functions in the public schema are exposed at
-- /rest/v1/rpc/<name> and were callable by anon and authenticated.
--
-- Postgres checks EXECUTE at CREATE TRIGGER time, not at fire time, so the
-- on_auth_user_created trigger keeps working after this revoke.

revoke all on function public.handle_new_user() from public, anon, authenticated;
