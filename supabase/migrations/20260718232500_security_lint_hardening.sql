-- Harden function execution surfaces reported by Supabase's database linter.
-- User-facing RPCs remain available to authenticated users; anonymous access is
-- removed so SECURITY DEFINER functions are not callable before sign-in.

alter function public.set_updated_at()
  set search_path = public, extensions, pg_temp;

alter function public._rrule_token(rule text, token text)
  set search_path = public, pg_temp;

alter function public._rrule_day_matches(day_to_check date, byday text)
  set search_path = public, pg_temp;

alter function public.normalize_task_resource_domain(input_url text)
  set search_path = public, pg_temp;

revoke all on function public.bootstrap_current_user() from public, anon;
revoke all on function public.cancel_account_deletion() from public, anon;
revoke all on function public.edit_task_with_scope(
  target_task_id uuid,
  edit_scope text,
  task_values jsonb,
  resource_values jsonb,
  reminder_values jsonb
) from public, anon;
revoke all on function public.export_my_data() from public, anon;
revoke all on function public.generate_task_occurrences(
  recurrence_id uuid,
  range_start timestamp with time zone,
  range_end timestamp with time zone
) from public, anon;
revoke all on function public.get_my_startup_state() from public, anon;
revoke all on function public.is_owner(check_user uuid) from public, anon;
revoke all on function public.owner_backend_diagnostics() from public, anon;
revoke all on function public.request_account_deletion(confirmation_text text)
  from public, anon;
revoke all on function public.set_task_recurrence_state(
  target_task_id uuid,
  requested_action text
) from public, anon;
revoke all on function public.skip_task_occurrence(target_task_id uuid)
  from public, anon;
revoke all on function public.soft_delete_task(task_id uuid) from public, anon;

grant execute on function public.bootstrap_current_user() to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;
grant execute on function public.edit_task_with_scope(
  target_task_id uuid,
  edit_scope text,
  task_values jsonb,
  resource_values jsonb,
  reminder_values jsonb
) to authenticated;
grant execute on function public.export_my_data() to authenticated;
grant execute on function public.generate_task_occurrences(
  recurrence_id uuid,
  range_start timestamp with time zone,
  range_end timestamp with time zone
) to authenticated;
grant execute on function public.get_my_startup_state() to authenticated;
grant execute on function public.is_owner(check_user uuid) to authenticated;
grant execute on function public.owner_backend_diagnostics() to authenticated;
grant execute on function public.request_account_deletion(confirmation_text text)
  to authenticated;
grant execute on function public.set_task_recurrence_state(
  target_task_id uuid,
  requested_action text
) to authenticated;
grant execute on function public.skip_task_occurrence(target_task_id uuid)
  to authenticated;
grant execute on function public.soft_delete_task(task_id uuid) to authenticated;

-- Trigger/internal functions do not need RPC execution grants.
revoke all on function public.handle_new_user_defaults() from public, anon, authenticated;
revoke all on function public.install_owner_daily_schedule_if_needed()
  from public, anon, authenticated;
revoke all on function public.install_owner_template_if_needed()
  from public, anon, authenticated;
revoke all on function public.sync_profile_email_from_auth()
  from public, anon, authenticated;
