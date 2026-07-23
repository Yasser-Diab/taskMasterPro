begin;

-- Version 0.1.2: shared session commands, dynamic task execution models,
-- work demands, learning checkpoints, cycle sync, idle intervals, widgets, and
-- richer roadmap/break attribution state.

alter table public.tasks
  add column if not exists task_domain text not null default 'personal',
  add column if not exists execution_mode text not null default 'pomodoro_focus',
  add column if not exists progress_rule jsonb not null default '{}'::jsonb,
  add column if not exists restore_task_tabs_across_occurrences boolean not null default true,
  add column if not exists tab_restore_policy text not null default 'keep_all_tabs',
  add column if not exists revision bigint not null default 0,
  add column if not exists updated_by_device text;

alter table public.tasks
  drop constraint if exists tasks_task_domain_check,
  add constraint tasks_task_domain_check
  check (task_domain in (
    'work',
    'learning',
    'reading',
    'self_improvement',
    'household',
    'sport',
    'event',
    'personal',
    'custom'
  ));

alter table public.tasks
  drop constraint if exists tasks_execution_mode_check,
  add constraint tasks_execution_mode_check
  check (execution_mode in (
    'pomodoro_focus',
    'continuous_timer',
    'checklist',
    'reading_session',
    'habit',
    'event',
    'manual_completion',
    'hybrid'
  ));

alter table public.tasks
  drop constraint if exists tasks_tab_restore_policy_check,
  add constraint tasks_tab_restore_policy_check
  check (tab_restore_policy in (
    'keep_all_tabs',
    'keep_pinned_tabs_only',
    'clean_workspace',
    'ask_after_completion'
  ));

-- Backfill task domains from the real category relation:
-- public.tasks.category_id -> public.categories.id -> public.categories.name.
-- Task type takes precedence where it defines an unambiguous execution model.
with classified_tasks as (
  select
    t.id,
    t.task_type,
    t.task_domain as current_task_domain,
    t.execution_mode as current_execution_mode,
    lower(btrim(coalesce(c.name, ''))) as category_name
  from public.tasks as t
  left join public.categories as c
    on c.id = t.category_id
   and c.deleted_at is null
  where t.deleted_at is null
),
resolved_tasks as (
  select
    id,
    case
      when task_type = 'reading' then 'reading'
      when task_type = 'event' then 'event'

      when category_name in (
        'work',
        'main job',
        'project building'
      ) then 'work'

      when category_name in (
        'learning',
        'programming learning',
        'programming practice',
        'algorithms',
        'german'
      ) then 'learning'

      when category_name in (
        'reading',
        'programming books'
      ) then 'reading'

      when category_name in (
        'household',
        'shopping and errands'
      ) then 'household'

      when category_name in (
        'health',
        'health and exercise'
      ) then 'sport'

      when category_name in (
        'weekly review'
      ) then 'self_improvement'

      when category_name in (
        'family',
        'social',
        'friends and sisters',
        'personal administration',
        'rest and recreation'
      ) then 'personal'

      else current_task_domain
    end as resolved_task_domain,

    case
      when task_type = 'timed' then 'continuous_timer'
      when task_type = 'event' then 'event'
      when task_type = 'habit' then 'habit'
      when task_type = 'reading' then 'reading_session'
      when task_type in ('manual', 'completion_only') then 'manual_completion'
      else current_execution_mode
    end as resolved_execution_mode
  from classified_tasks
)
update public.tasks as t
set
  task_domain = r.resolved_task_domain,
  execution_mode = r.resolved_execution_mode
from resolved_tasks as r
where t.id = r.id
  and (
    t.task_domain is distinct from r.resolved_task_domain
    or t.execution_mode is distinct from r.resolved_execution_mode
  );

alter table public.sessions
  add column if not exists revision bigint not null default 0,
  add column if not exists stage text,
  add column if not exists current_segment_id uuid,
  add column if not exists planned_duration_seconds integer,
  add column if not exists last_resumed_at timestamptz,
  add column if not exists accumulated_active_seconds integer not null default 0,
  add column if not exists accumulated_paused_seconds integer not null default 0,
  add column if not exists source_device_id text;

alter table public.session_segments
  add column if not exists stage text,
  add column if not exists planned_duration_seconds integer,
  add column if not exists accumulated_active_seconds integer not null default 0,
  add column if not exists accumulated_paused_seconds integer not null default 0,
  add column if not exists completed_at timestamptz,
  add column if not exists transition_reason text,
  add column if not exists controlling_device_id text,
  add column if not exists last_checkpoint_at timestamptz;

alter table public.task_browser_tabs
  add column if not exists workspace_id uuid,
  add column if not exists tab_id text,
  add column if not exists page_title text,
  add column if not exists custom_title text,
  add column if not exists is_pinned boolean not null default false,
  add column if not exists is_open boolean not null default true,
  add column if not exists restore_across_occurrences boolean not null default true;

-- SQL Editor migrations do not carry an authenticated JWT, so auth.uid()
-- is NULL. Temporarily disable application ownership-validation triggers only
-- for this controlled metadata backfill. Constraint/FK triggers remain active.
alter table public.task_browser_tabs disable trigger user;

update public.task_browser_tabs
set page_title = coalesce(page_title, title),
    is_open = closed_at is null
where deleted_at is null;

alter table public.task_browser_tabs enable trigger user;

create index if not exists task_browser_tabs_workspace_idx
on public.task_browser_tabs(user_id, task_id, workspace_id, tab_order)
where deleted_at is null and is_open = true;

alter table public.roadmaps
  add column if not exists goal text not null default '',
  add column if not exists progress_method text not null default 'weighted_combination',
  add column if not exists progress_weights jsonb not null default '{}'::jsonb,
  add column if not exists completion_criteria jsonb not null default '{}'::jsonb,
  add column if not exists recommendations jsonb not null default '[]'::jsonb,
  add column if not exists archived_at timestamptz,
  add column if not exists revision bigint not null default 0;

alter table public.roadmaps
  drop constraint if exists roadmaps_progress_method_check,
  add constraint roadmaps_progress_method_check
  check (progress_method in (
    'milestones',
    'checkpoints',
    'linked_task_completion',
    'focused_effort',
    'reading_progress',
    'practice_contributions',
    'manual_evidence',
    'weighted_combination'
  ));

alter table public.roadmap_phases
  add column if not exists phase_order integer,
  add column if not exists title text,
  add column if not exists description text not null default '',
  add column if not exists progress_method text not null default 'weighted_combination',
  add column if not exists progress_weights jsonb not null default '{}'::jsonb,
  add column if not exists completion_criteria jsonb not null default '{}'::jsonb,
  add column if not exists dependencies jsonb not null default '[]'::jsonb,
  add column if not exists archived_at timestamptz,
  add column if not exists revision bigint not null default 0;

update public.roadmap_phases
set phase_order = coalesce(phase_order, phase_number),
    title = coalesce(title, objective)
where phase_order is null or title is null;

alter table public.roadmap_phases
  alter column phase_order set not null;

alter table public.roadmap_phases
  drop constraint if exists roadmap_phases_progress_method_check,
  add constraint roadmap_phases_progress_method_check
  check (progress_method in (
    'milestones',
    'checkpoints',
    'linked_task_completion',
    'focused_effort',
    'reading_progress',
    'practice_contributions',
    'manual_evidence',
    'weighted_combination'
  ));

drop index if exists roadmap_phases_roadmap_phase_number_unique;
create unique index if not exists roadmap_phases_roadmap_phase_order_unique
on public.roadmap_phases(roadmap_id, phase_order)
where deleted_at is null;

create table if not exists public.session_commands (
  command_id uuid primary key,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  session_id uuid not null references public.sessions(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  expected_revision bigint not null default 0,
  resulting_revision bigint,
  command_type text not null,
  device_id text not null,
  client_occurred_at timestamptz not null,
  server_occurred_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'applied',
  error_message text,
  created_at timestamptz not null default now(),
  constraint session_commands_type_check
  check (command_type in (
    'start_task',
    'pause_task',
    'resume_task',
    'finish_task',
    'start_focus',
    'pause_focus',
    'resume_focus',
    'finish_focus',
    'jump_to_break',
    'start_break',
    'pause_break',
    'resume_break',
    'finish_break',
    'skip_break',
    'extend_break',
    'return_to_focus',
    'classify_break_activity'
  )),
  constraint session_commands_status_check
  check (status in ('applied', 'duplicate', 'revision_conflict', 'rejected'))
);

create index if not exists session_commands_session_revision_idx
on public.session_commands(user_id, session_id, resulting_revision desc);

create table if not exists public.work_demands (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  description text not null default '',
  priority text not null default 'normal',
  status text not null default 'open',
  weight numeric(10,3) not null default 1,
  original_due_date date,
  current_scheduled_date date,
  completed_at timestamptz,
  rollover_policy text not null default 'next_valid_work_occurrence',
  position integer not null default 0,
  tags text[] not null default '{}'::text[],
  attachments jsonb not null default '[]'::jsonb,
  notes text not null default '',
  overdue_dismissed_at timestamptz,
  overdue_dismissal_reason text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0,
  constraint work_demands_priority_check
  check (priority in ('critical', 'high', 'normal', 'low')),
  constraint work_demands_status_check
  check (status in ('open', 'in_progress', 'blocked', 'completed', 'cancelled')),
  constraint work_demands_rollover_policy_check
  check (rollover_policy in (
    'next_valid_work_occurrence',
    'keep_on_original_date',
    'manual_reschedule',
    'cancel_if_missed'
  ))
);

create index if not exists work_demands_task_position_idx
on public.work_demands(user_id, task_id, position)
where deleted_at is null;

create table if not exists public.learning_checkpoints (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  roadmap_id uuid references public.roadmaps(id) on delete set null,
  roadmap_phase_id uuid references public.roadmap_phases(id) on delete set null,
  title text not null,
  description text not null default '',
  target_date date,
  status text not null default 'open',
  evidence text,
  linked_resources jsonb not null default '[]'::jsonb,
  estimated_effort_minutes integer not null default 0,
  actual_focused_seconds integer not null default 0,
  notes text not null default '',
  completion_criteria text not null default '',
  position integer not null default 0,
  device_id text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0,
  constraint learning_checkpoints_status_check
  check (status in ('open', 'in_progress', 'completed', 'skipped', 'cancelled')),
  constraint learning_checkpoints_effort_check
  check (estimated_effort_minutes >= 0 and actual_focused_seconds >= 0)
);

create index if not exists learning_checkpoints_task_position_idx
on public.learning_checkpoints(user_id, task_id, position)
where deleted_at is null;

create table if not exists public.idle_intervals (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  idle_started_at timestamptz not null,
  idle_ended_at timestamptz,
  idle_reason text not null default 'unknown',
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0,
  constraint idle_intervals_reason_check
  check (idle_reason in (
    'no_input',
    'screen_locked',
    'device_sleep',
    'app_background',
    'manual_idle',
    'unknown'
  )),
  constraint idle_intervals_time_check
  check (idle_ended_at is null or idle_ended_at >= idle_started_at)
);

create index if not exists idle_intervals_session_time_idx
on public.idle_intervals(user_id, session_id, idle_started_at desc)
where deleted_at is null;

create table if not exists public.cycle_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  sync_enabled boolean not null default false,
  storage_mode text not null default 'device_only',
  typical_cycle_length_days integer not null default 28,
  typical_period_length_days integer not null default 5,
  prediction_enabled boolean not null default true,
  workload_assistance_enabled boolean not null default false,
  gentle_coaching_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  constraint cycle_settings_storage_mode_check
  check (storage_mode in ('device_only', 'sync_encrypted')),
  constraint cycle_settings_lengths_check
  check (
    typical_cycle_length_days between 15 and 60
    and typical_period_length_days between 1 and 14
  )
);

create table if not exists public.cycle_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  period_start_date date not null,
  period_end_date date,
  flow_level text,
  energy_level integer,
  symptoms text[] not null default '{}'::text[],
  notes text not null default '',
  confirmed boolean not null default true,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0,
  constraint cycle_entries_dates_check
  check (period_end_date is null or period_end_date >= period_start_date),
  constraint cycle_entries_flow_check
  check (flow_level is null or flow_level in ('none', 'light', 'medium', 'heavy')),
  constraint cycle_entries_energy_check
  check (energy_level is null or energy_level between 1 and 5)
);

create index if not exists cycle_entries_user_period_idx
on public.cycle_entries(user_id, period_start_date desc)
where deleted_at is null;

create table if not exists public.notification_device_preferences (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id text,
  mode text not null default 'all_signed_in_devices',
  selected_device_ids text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id),
  constraint notification_device_preferences_mode_check
  check (mode in ('all_signed_in_devices', 'active_device_only', 'selected_devices'))
);

create table if not exists public.widget_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id text not null,
  widget_kind text not null,
  snapshot jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id, device_id, widget_kind),
  constraint widget_snapshots_kind_check
  check (widget_kind in ('active_timer', 'today', 'coaching'))
);

alter table public.break_contributions
  add column if not exists source_break_segment_id uuid
    references public.session_segments(id) on delete set null,
  add column if not exists related_roadmap_id uuid
    references public.roadmaps(id) on delete set null,
  add column if not exists activity_type text,
  add column if not exists resource_id uuid
    references public.task_resources(id) on delete set null,
  add column if not exists attribution_method text,
  add column if not exists device_id text,
  add column if not exists revision bigint not null default 0;

alter table public.break_contributions
  drop constraint if exists break_contributions_type_check,
  add constraint break_contributions_type_check
  check (contribution_type in (
    'rest',
    'learning',
    'german',
    'reading',
    'exercise',
    'housework',
    'another_task',
    'other'
  ));

-- Same migration-only handling for the controlled legacy-value backfill.
alter table public.break_contributions disable trigger user;

update public.break_contributions
set contribution_type = 'learning'
where contribution_type = 'german';

alter table public.break_contributions enable trigger user;

create or replace function public.apply_session_command(
  p_command_id uuid,
  p_session_id uuid,
  p_task_id uuid,
  p_expected_revision bigint,
  p_command_type text,
  p_device_id text,
  p_client_occurred_at timestamptz,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions%rowtype;
  v_existing public.session_commands%rowtype;
  v_new_revision bigint;
  v_stage text;
  v_status text;
  v_segment_id uuid;
  v_planned_duration integer;
  v_last_resumed_at timestamptz;
  v_accumulated_active integer;
  v_accumulated_paused integer;
  v_occurred_at timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into v_existing
  from public.session_commands
  where command_id = p_command_id
    and user_id = v_user_id;

  if found then
    select * into v_session
    from public.sessions
    where id = p_session_id and user_id = v_user_id;

    return jsonb_build_object(
      'status', 'duplicate',
      'session_id', p_session_id,
      'task_id', p_task_id,
      'revision', coalesce(v_session.revision, v_existing.resulting_revision),
      'stage', v_session.stage,
      'session_state', v_session.status,
      'segment_id', v_session.current_segment_id,
      'planned_duration_seconds', v_session.planned_duration_seconds,
      'started_at_utc', v_session.started_at,
      'last_resumed_at_utc', v_session.last_resumed_at,
      'accumulated_active_seconds', v_session.accumulated_active_seconds,
      'accumulated_paused_seconds', v_session.accumulated_paused_seconds,
      'occurred_at_utc', v_existing.server_occurred_at,
      'source_device_id', v_existing.device_id
    );
  end if;

  select *
  into v_session
  from public.sessions
  where id = p_session_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'session_not_found' using errcode = 'P0002';
  end if;

  if coalesce(v_session.revision, 0) <> p_expected_revision then
    insert into public.session_commands (
      command_id,
      user_id,
      session_id,
      task_id,
      expected_revision,
      resulting_revision,
      command_type,
      device_id,
      client_occurred_at,
      server_occurred_at,
      payload,
      status,
      error_message
    ) values (
      p_command_id,
      v_user_id,
      p_session_id,
      p_task_id,
      p_expected_revision,
      v_session.revision,
      p_command_type,
      p_device_id,
      p_client_occurred_at,
      v_occurred_at,
      coalesce(p_payload, '{}'::jsonb),
      'revision_conflict',
      'Task state changed on another device.'
    );

    return jsonb_build_object(
      'status', 'revision_conflict',
      'message', 'Task state changed on another device. The latest state has been loaded.',
      'session_id', v_session.id,
      'task_id', v_session.task_id,
      'revision', v_session.revision,
      'stage', v_session.stage,
      'session_state', v_session.status,
      'segment_id', v_session.current_segment_id,
      'planned_duration_seconds', v_session.planned_duration_seconds,
      'started_at_utc', v_session.started_at,
      'last_resumed_at_utc', v_session.last_resumed_at,
      'accumulated_active_seconds', v_session.accumulated_active_seconds,
      'accumulated_paused_seconds', v_session.accumulated_paused_seconds,
      'occurred_at_utc', v_occurred_at,
      'source_device_id', v_session.source_device_id
    );
  end if;

  v_stage := case p_command_type
    when 'start_focus' then 'focus_running'
    when 'resume_focus' then 'focus_running'
    when 'pause_focus' then 'focus_paused'
    when 'finish_focus' then 'focus_completed_waiting'
    when 'jump_to_break' then 'break_running'
    when 'start_break' then 'break_running'
    when 'resume_break' then 'break_running'
    when 'pause_break' then 'break_paused'
    when 'finish_break' then 'break_completed_waiting'
    when 'skip_break' then 'focus_completed_waiting'
    when 'extend_break' then 'break_running'
    when 'return_to_focus' then 'focus_running'
    else coalesce(v_session.stage, 'idle')
  end;

  v_status := case p_command_type
    when 'start_task' then 'running'
    when 'resume_task' then 'running'
    when 'pause_task' then 'paused'
    when 'finish_task' then 'completed'
    when 'start_focus' then 'running'
    when 'resume_focus' then 'running'
    when 'pause_focus' then 'paused'
    when 'finish_focus' then 'paused'
    when 'jump_to_break' then 'running'
    when 'start_break' then 'running'
    when 'resume_break' then 'running'
    when 'pause_break' then 'paused'
    when 'finish_break' then 'paused'
    when 'return_to_focus' then 'running'
    else v_session.status
  end;

  v_segment_id := coalesce(
    nullif(p_payload->>'segment_id', '')::uuid,
    v_session.current_segment_id
  );
  v_planned_duration := coalesce(
    nullif(p_payload->>'planned_duration_seconds', '')::integer,
    v_session.planned_duration_seconds
  );
  v_last_resumed_at := case
    when p_command_type in (
      'start_task',
      'resume_task',
      'start_focus',
      'resume_focus',
      'jump_to_break',
      'start_break',
      'resume_break',
      'return_to_focus'
    ) then p_client_occurred_at
    else v_session.last_resumed_at
  end;
  v_accumulated_active := coalesce(
    nullif(p_payload->>'accumulated_active_seconds', '')::integer,
    v_session.accumulated_active_seconds,
    0
  );
  v_accumulated_paused := coalesce(
    nullif(p_payload->>'accumulated_paused_seconds', '')::integer,
    v_session.accumulated_paused_seconds,
    0
  );
  v_new_revision := coalesce(v_session.revision, 0) + 1;

  update public.sessions
  set task_id = coalesce(p_task_id, task_id),
      revision = v_new_revision,
      stage = v_stage,
      status = v_status,
      current_segment_id = v_segment_id,
      planned_duration_seconds = v_planned_duration,
      last_resumed_at = v_last_resumed_at,
      accumulated_active_seconds = v_accumulated_active,
      accumulated_paused_seconds = v_accumulated_paused,
      source_device_id = p_device_id,
      updated_at = v_occurred_at,
      ended_at = case when p_command_type = 'finish_task' then v_occurred_at else ended_at end
  where id = p_session_id
    and user_id = v_user_id
  returning * into v_session;

  insert into public.session_commands (
    command_id,
    user_id,
    session_id,
    task_id,
    expected_revision,
    resulting_revision,
    command_type,
    device_id,
    client_occurred_at,
    server_occurred_at,
    payload,
    status
  ) values (
    p_command_id,
    v_user_id,
    p_session_id,
    p_task_id,
    p_expected_revision,
    v_new_revision,
    p_command_type,
    p_device_id,
    p_client_occurred_at,
    v_occurred_at,
    coalesce(p_payload, '{}'::jsonb),
    'applied'
  );

  insert into public.sync_events (
    user_id,
    entity_type,
    entity_id,
    event_type,
    revision,
    device_id,
    payload,
    occurred_at
  ) values (
    v_user_id,
    'session',
    p_session_id::text,
    'session_command_applied',
    v_new_revision,
    p_device_id,
    jsonb_build_object(
      'session_id', v_session.id,
      'task_id', v_session.task_id,
      'revision', v_session.revision,
      'stage', v_session.stage,
      'session_state', v_session.status,
      'segment_id', v_session.current_segment_id,
      'planned_duration_seconds', v_session.planned_duration_seconds,
      'started_at_utc', v_session.started_at,
      'last_resumed_at_utc', v_session.last_resumed_at,
      'accumulated_active_seconds', v_session.accumulated_active_seconds,
      'accumulated_paused_seconds', v_session.accumulated_paused_seconds,
      'occurred_at_utc', v_occurred_at,
      'source_device_id', p_device_id
    ),
    v_occurred_at
  );

  return jsonb_build_object(
    'status', 'applied',
    'session_id', v_session.id,
    'task_id', v_session.task_id,
    'revision', v_session.revision,
    'stage', v_session.stage,
    'session_state', v_session.status,
    'segment_id', v_session.current_segment_id,
    'planned_duration_seconds', v_session.planned_duration_seconds,
    'started_at_utc', v_session.started_at,
    'last_resumed_at_utc', v_session.last_resumed_at,
    'accumulated_active_seconds', v_session.accumulated_active_seconds,
    'accumulated_paused_seconds', v_session.accumulated_paused_seconds,
    'occurred_at_utc', v_occurred_at,
    'source_device_id', p_device_id
  );
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'session_commands',
    'work_demands',
    'learning_checkpoints',
    'idle_intervals',
    'cycle_settings',
    'cycle_entries',
    'notification_device_preferences',
    'widget_snapshots'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);

    execute format('drop policy if exists %I on public.%I', table_name || '_select_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete_own', table_name);

    execute format(
      'create policy %I on public.%I for select to authenticated using (user_id = auth.uid())',
      table_name || '_select_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid())',
      table_name || '_insert_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name || '_update_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (user_id = auth.uid())',
      table_name || '_delete_own',
      table_name
    );
  end loop;
end $$;

grant select, insert, update, delete on public.session_commands to authenticated;
grant select, insert, update, delete on public.work_demands to authenticated;
grant select, insert, update, delete on public.learning_checkpoints to authenticated;
grant select, insert, update, delete on public.idle_intervals to authenticated;
grant select, insert, update, delete on public.cycle_settings to authenticated;
grant select, insert, update, delete on public.cycle_entries to authenticated;
grant select, insert, update, delete on public.notification_device_preferences to authenticated;
grant select, insert, update, delete on public.widget_snapshots to authenticated;
grant execute on function public.apply_session_command(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  text,
  timestamptz,
  jsonb
) to authenticated;
revoke all on function public.apply_session_command(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  text,
  timestamptz,
  jsonb
) from public, anon;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'session_commands'
    ) then
      alter publication supabase_realtime add table public.session_commands;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'widget_snapshots'
    ) then
      alter publication supabase_realtime add table public.widget_snapshots;
    end if;
  end if;
end $$;

commit;
