-- Profile sex/cycle preferences and durable Pomodoro segment state.

alter table public.profiles
  add column if not exists sex text,
  add column if not exists cycle_tracking_enabled boolean not null default false,
  add column if not exists cycle_data_sync_enabled boolean not null default false;

alter table public.profiles
  drop constraint if exists profiles_sex_check;

alter table public.profiles
  add constraint profiles_sex_check
  check (
    sex is null or sex in (
      'male',
      'female',
      'prefer_not_to_say',
      'custom'
    )
  );

alter table public.session_segments
  add column if not exists stage text,
  add column if not exists planned_duration_seconds integer
    check (
      planned_duration_seconds is null
      or planned_duration_seconds >= 0
    ),
  add column if not exists accumulated_active_seconds integer not null default 0
    check (accumulated_active_seconds >= 0),
  add column if not exists accumulated_paused_seconds integer not null default 0
    check (accumulated_paused_seconds >= 0),
  add column if not exists completed_at timestamptz,
  add column if not exists transition_reason text,
  add column if not exists controlling_device_id text,
  add column if not exists last_checkpoint_at timestamptz;

alter table public.session_segments
  drop constraint if exists session_segments_stage_check;

alter table public.session_segments
  add constraint session_segments_stage_check
  check (
    stage is null or stage in (
      'idle',
      'focus_ready',
      'focus_running',
      'focus_paused',
      'focus_completed_waiting',
      'break_ready',
      'break_running',
      'break_paused',
      'break_completed_waiting',
      'task_completed',
      'cancelled'
    )
  );

create index if not exists session_segments_user_stage_idx
on public.session_segments (
  user_id,
  stage,
  started_at desc
)
where deleted_at is null;

-- Supabase database-linter hardening. These functions were created across
-- earlier migrations; keep their search paths deterministic and avoid broad
-- anonymous PostgREST execution of SECURITY DEFINER routines.
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.set_updated_at()',
    'public._rrule_token(text, text)',
    'public._rrule_day_matches(date, text)',
    'public.normalize_task_resource_domain(text)',
    'public.handle_new_user_defaults()',
    'public.sync_profile_email_from_auth()',
    'public.is_owner(uuid)',
    'public.bootstrap_current_user()',
    'public.get_my_startup_state()',
    'public.export_my_data()',
    'public.request_account_deletion(text)',
    'public.cancel_account_deletion()',
    'public.owner_backend_diagnostics()',
    'public.install_owner_template_if_needed()',
    'public.install_owner_daily_schedule_if_needed()',
    'public.generate_task_occurrences(uuid, timestamptz, timestamptz)',
    'public.soft_delete_task(uuid)',
    'public.edit_task_with_scope(uuid, text, jsonb, jsonb, jsonb)',
    'public.skip_task_occurrence(uuid)',
    'public.set_task_recurrence_state(uuid, text)',
    'public.claim_active_session_control(uuid, uuid, text, boolean)',
    'public.release_active_session_control(uuid, text)'
  ] loop
    if to_regprocedure(fn) is not null then
      execute 'alter function ' || fn ||
        ' set search_path = public, extensions, auth, pg_temp';
      execute 'revoke all on function ' || fn || ' from public, anon';
    end if;
  end loop;

  foreach fn in array array[
    'public.set_updated_at()',
    'public._rrule_token(text, text)',
    'public._rrule_day_matches(date, text)',
    'public.normalize_task_resource_domain(text)',
    'public.handle_new_user_defaults()',
    'public.sync_profile_email_from_auth()'
  ] loop
    if to_regprocedure(fn) is not null then
      execute 'revoke all on function ' || fn || ' from authenticated';
    end if;
  end loop;

  foreach fn in array array[
    'public.is_owner(uuid)',
    'public.bootstrap_current_user()',
    'public.get_my_startup_state()',
    'public.export_my_data()',
    'public.request_account_deletion(text)',
    'public.cancel_account_deletion()',
    'public.owner_backend_diagnostics()',
    'public.install_owner_template_if_needed()',
    'public.install_owner_daily_schedule_if_needed()',
    'public.generate_task_occurrences(uuid, timestamptz, timestamptz)',
    'public.soft_delete_task(uuid)',
    'public.edit_task_with_scope(uuid, text, jsonb, jsonb, jsonb)',
    'public.skip_task_occurrence(uuid)',
    'public.set_task_recurrence_state(uuid, text)',
    'public.claim_active_session_control(uuid, uuid, text, boolean)',
    'public.release_active_session_control(uuid, text)'
  ] loop
    if to_regprocedure(fn) is not null then
      execute 'grant execute on function ' || fn || ' to authenticated';
    end if;
  end loop;
end;
$$;
