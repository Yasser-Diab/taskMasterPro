-- Explicit, idempotent task-to-roadmap hierarchy relationships.
-- Tasks remain independently owned task occurrences; unlinking never deletes
-- the task or its history.

alter table public.roadmap_checkpoints
  add column if not exists milestone_id uuid
  references public.roadmap_milestones(id);

create table if not exists public.roadmap_task_links (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  roadmap_id uuid not null references public.roadmaps(id),
  phase_id uuid references public.roadmap_phases(id),
  milestone_id uuid references public.roadmap_milestones(id),
  checkpoint_id uuid references public.roadmap_checkpoints(id),
  task_id uuid not null references public.task_occurrences(id),
  relationship_type text not null default 'primary',
  contribution_rule text not null default 'completion_only'
    check (
      contribution_rule in (
        'none',
        'completion_only',
        'approved_effort',
        'configured_percentage',
        'manual_review'
      )
    ),
  progress_weight numeric(12, 4) not null default 1
    check (progress_weight >= 0),
  title text not null default 'Task connection',
  status text not null default 'active',
  position numeric(20, 10) not null default 0,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, id)
);

create unique index if not exists roadmap_task_links_identity_idx
  on public.roadmap_task_links (
    user_id,
    roadmap_id,
    task_id,
    coalesce(phase_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(milestone_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(checkpoint_id, '00000000-0000-0000-0000-000000000000'::uuid),
    relationship_type
  )
  where deleted_at is null;

create index if not exists roadmap_task_links_roadmap_idx
  on public.roadmap_task_links (user_id, roadmap_id, phase_id, position)
  where deleted_at is null;

create index if not exists roadmap_task_links_task_idx
  on public.roadmap_task_links (user_id, task_id)
  where deleted_at is null;

create or replace function private.validate_roadmap_task_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.roadmaps roadmap
    where roadmap.id = new.roadmap_id
      and roadmap.user_id = new.user_id
      and roadmap.deleted_at is null
  ) then
    raise exception 'invalid_roadmap_relationship';
  end if;

  if not exists (
    select 1
    from public.task_occurrences task
    where task.id = new.task_id
      and task.user_id = new.user_id
      and task.deleted_at is null
  ) then
    raise exception 'invalid_task_relationship';
  end if;

  if new.phase_id is not null and not exists (
    select 1
    from public.roadmap_phases phase
    where phase.id = new.phase_id
      and phase.user_id = new.user_id
      and phase.roadmap_id = new.roadmap_id
      and phase.deleted_at is null
  ) then
    raise exception 'phase_does_not_belong_to_roadmap';
  end if;

  if new.milestone_id is not null and not exists (
    select 1
    from public.roadmap_milestones milestone
    where milestone.id = new.milestone_id
      and milestone.user_id = new.user_id
      and milestone.roadmap_id = new.roadmap_id
      and milestone.deleted_at is null
      and (
        new.phase_id is null
        or milestone.phase_id is null
        or milestone.phase_id = new.phase_id
      )
  ) then
    raise exception 'milestone_does_not_belong_to_roadmap';
  end if;

  if new.checkpoint_id is not null and not exists (
    select 1
    from public.roadmap_checkpoints checkpoint
    where checkpoint.id = new.checkpoint_id
      and checkpoint.user_id = new.user_id
      and checkpoint.roadmap_id = new.roadmap_id
      and checkpoint.deleted_at is null
      and (
        new.phase_id is null
        or checkpoint.phase_id is null
        or checkpoint.phase_id = new.phase_id
      )
  ) then
    raise exception 'checkpoint_does_not_belong_to_roadmap';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_roadmap_task_link
  on public.roadmap_task_links;
create trigger validate_roadmap_task_link
before insert or update on public.roadmap_task_links
for each row execute function private.validate_roadmap_task_link();

drop trigger if exists prepare_roadmap_task_links
  on public.roadmap_task_links;
create trigger prepare_roadmap_task_links
before insert or update on public.roadmap_task_links
for each row execute function private.prepare_synchronized_record();

drop trigger if exists log_roadmap_task_links
  on public.roadmap_task_links;
create trigger log_roadmap_task_links
after insert or update on public.roadmap_task_links
for each row execute function private.log_synchronized_change();

alter table public.roadmap_task_links enable row level security;
alter table public.roadmap_task_links force row level security;

drop policy if exists owner_select_roadmap_task_links
  on public.roadmap_task_links;
create policy owner_select_roadmap_task_links
  on public.roadmap_task_links for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists owner_insert_roadmap_task_links
  on public.roadmap_task_links;
create policy owner_insert_roadmap_task_links
  on public.roadmap_task_links for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists owner_update_roadmap_task_links
  on public.roadmap_task_links;
create policy owner_update_roadmap_task_links
  on public.roadmap_task_links for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists owner_delete_roadmap_task_links
  on public.roadmap_task_links;
create policy owner_delete_roadmap_task_links
  on public.roadmap_task_links for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.roadmap_task_links to authenticated;
revoke all on public.roadmap_task_links from anon;

create or replace function public.apply_roadmap_task_link_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_entity_id uuid,
  p_base_revision bigint,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  current_revision bigint;
  existing_result jsonb;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'unsupported_operation';
  end if;

  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':' || p_command_id::text, 0)
  );

  select result into existing_result
  from public.processed_commands
  where user_id = owner_id and command_id = p_command_id;

  if found then
    return existing_result;
  end if;

  select revision into current_revision
  from public.roadmap_task_links
  where user_id = owner_id and id = p_entity_id
  for update;

  if p_operation = 'create' and current_revision is null then
    if p_base_revision <> 0 then
      result_payload := jsonb_build_object(
        'status', 'conflict',
        'reason', 'missing_entity',
        'server_revision', null
      );
    else
      insert into public.roadmap_task_links (
        id,
        user_id,
        roadmap_id,
        phase_id,
        milestone_id,
        checkpoint_id,
        task_id,
        relationship_type,
        contribution_rule,
        progress_weight,
        title,
        status,
        position,
        created_by_device_id,
        updated_by_device_id,
        last_command_id
      )
      values (
        p_entity_id,
        owner_id,
        (p_payload ->> 'roadmap_id')::uuid,
        nullif(p_payload ->> 'phase_id', '')::uuid,
        nullif(p_payload ->> 'milestone_id', '')::uuid,
        nullif(p_payload ->> 'checkpoint_id', '')::uuid,
        (p_payload ->> 'task_id')::uuid,
        coalesce(p_payload ->> 'relationship_type', 'primary'),
        coalesce(p_payload ->> 'contribution_rule', 'completion_only'),
        coalesce((p_payload ->> 'progress_weight')::numeric, 1),
        coalesce(p_payload ->> 'title', 'Task connection'),
        coalesce(p_payload ->> 'status', 'active'),
        coalesce((p_payload ->> 'position')::numeric, 0),
        p_device_id,
        p_device_id,
        p_command_id
      );
      result_payload := jsonb_build_object(
        'status', 'accepted',
        'entity_type', 'roadmap_task_links',
        'entity_id', p_entity_id,
        'revision', 1
      );
    end if;
  elsif current_revision is null then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'missing_entity',
      'server_revision', null
    );
  elsif current_revision <> p_base_revision then
    insert into public.sync_conflicts (
      user_id,
      command_id,
      entity_type,
      entity_id,
      conflict_type,
      base_revision,
      server_revision,
      local_payload,
      server_payload,
      created_by_device_id,
      updated_by_device_id
    )
    values (
      owner_id,
      p_command_id,
      'roadmap_task_links',
      p_entity_id,
      'revision_mismatch',
      p_base_revision,
      current_revision,
      p_payload,
      jsonb_build_object('revision', current_revision),
      p_device_id,
      p_device_id
    )
    on conflict (user_id, command_id, entity_id) do nothing;
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'revision_mismatch',
      'server_revision', current_revision
    );
  elsif p_operation = 'delete' then
    update public.roadmap_task_links
    set deleted_at = statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where user_id = owner_id and id = p_entity_id;
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', 'roadmap_task_links',
      'entity_id', p_entity_id,
      'revision', current_revision + 1,
      'deleted', true
    );
  else
    update public.roadmap_task_links
    set roadmap_id = coalesce(
          (p_payload ->> 'roadmap_id')::uuid,
          roadmap_id
        ),
        phase_id = case
          when p_payload ? 'phase_id'
            then nullif(p_payload ->> 'phase_id', '')::uuid
          else phase_id
        end,
        milestone_id = case
          when p_payload ? 'milestone_id'
            then nullif(p_payload ->> 'milestone_id', '')::uuid
          else milestone_id
        end,
        checkpoint_id = case
          when p_payload ? 'checkpoint_id'
            then nullif(p_payload ->> 'checkpoint_id', '')::uuid
          else checkpoint_id
        end,
        task_id = coalesce((p_payload ->> 'task_id')::uuid, task_id),
        relationship_type = coalesce(
          p_payload ->> 'relationship_type',
          relationship_type
        ),
        contribution_rule = coalesce(
          p_payload ->> 'contribution_rule',
          contribution_rule
        ),
        progress_weight = coalesce(
          (p_payload ->> 'progress_weight')::numeric,
          progress_weight
        ),
        title = coalesce(p_payload ->> 'title', title),
        status = coalesce(p_payload ->> 'status', status),
        position = coalesce((p_payload ->> 'position')::numeric, position),
        deleted_at = null,
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where user_id = owner_id and id = p_entity_id;
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', 'roadmap_task_links',
      'entity_id', p_entity_id,
      'revision', current_revision + 1
    );
  end if;

  insert into public.processed_commands (
    user_id,
    command_id,
    device_id,
    device_sequence,
    entity_type,
    entity_id,
    command_type,
    base_revision,
    status,
    result,
    created_by_device_id,
    updated_by_device_id,
    last_command_id
  )
  values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'roadmap_task_links',
    p_entity_id,
    p_operation,
    p_base_revision,
    case
      when result_payload ->> 'status' = 'accepted'
        then 'accepted'::public.sync_command_status
      else 'conflict'::public.sync_command_status
    end,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function public.apply_roadmap_task_link_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;

grant execute on function public.apply_roadmap_task_link_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

comment on function public.apply_roadmap_task_link_command is
  'Idempotent revision-checked command endpoint for task-to-roadmap hierarchy links.';
