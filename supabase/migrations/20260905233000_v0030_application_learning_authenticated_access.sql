-- DayVector 0.0.30: the aggregate learning RPCs are a signed-in feature.
--
-- Votes continue to carry only app-scoped SHA-256 hashes and are never linked
-- to an account in storage. Restricting execution to authenticated sessions
-- prevents unauthenticated traffic from manufacturing community signals.

revoke all on function public.submit_application_category_vote(
  text, text, text, text, boolean
) from anon;

revoke all on function public.get_application_category_consensus(
  text, text
) from anon;

grant execute on function public.submit_application_category_vote(
  text, text, text, text, boolean
) to authenticated;

grant execute on function public.get_application_category_consensus(
  text, text
) to authenticated;
