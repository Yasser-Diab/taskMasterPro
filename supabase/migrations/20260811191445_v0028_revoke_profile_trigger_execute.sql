-- This function is an implementation detail of the profiles trigger, not a
-- callable Data API/RPC surface. PostgreSQL grants EXECUTE to PUBLIC by
-- default, so remove both that inherited grant and the direct API-role grants.
-- The existing trigger remains attached to public.profiles and continues to
-- enforce the birth-date constraint without exposing a direct invocation path.
revoke execute on function public.validate_profile_birth_date() from public;
revoke execute on function public.validate_profile_birth_date() from anon;
revoke execute on function public.validate_profile_birth_date() from authenticated;
