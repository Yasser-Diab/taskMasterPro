with owner as (
  select '4bd3e32d-1dcd-48ed-9f64-9099675047f1'::uuid as id
),
seed_roadmaps as (
  select roadmap.*
  from public.roadmaps as roadmap, owner
  where roadmap.user_id = owner.id
    and roadmap.data ->> 'v0027_seed_key' in (
      'full_stack_programming',
      'german_professional_fluency'
    )
    and roadmap.deleted_at is null
),
seed_tasks as (
  select task.*
  from public.task_occurrences as task, owner
  where task.user_id = owner.id
    and task.data ? 'v0027_seed_key'
    and task.deleted_at is null
),
seed_templates as (
  select template.*
  from public.task_templates as template, owner
  where template.user_id = owner.id
    and template.data ->> 'installed_release' = '0.0.27'
    and template.description =
      'Sustainable recurring study timetable for TaskMaster Pro v0.0.27'
    and template.deleted_at is null
)
select
  (select count(*) from seed_roadmaps) as roadmaps,
  (
    select jsonb_agg(title order by title)
    from seed_roadmaps
  ) as roadmap_names,
  (
    select count(*)
    from public.roadmap_phases as phase, owner
    where phase.user_id = owner.id
      and phase.data ? 'v0027_seed_key'
      and phase.deleted_at is null
  ) as phases,
  (
    select count(*)
    from public.roadmap_milestones as milestone, owner
    where milestone.user_id = owner.id
      and milestone.data ? 'v0027_seed_key'
      and milestone.deleted_at is null
  ) as milestones,
  (
    select count(*)
    from public.roadmap_checkpoints as checkpoint, owner
    where checkpoint.user_id = owner.id
      and checkpoint.data ? 'v0027_seed_key'
      and checkpoint.deleted_at is null
  ) as checkpoints,
  (select count(*) from seed_tasks) as task_occurrences,
  (select count(*) from seed_templates) as recurring_templates,
  (
    select count(*)
    from public.task_resources as resource, owner
    where resource.user_id = owner.id
      and (
        resource.data ? 'v0027_seed_key'
      )
      and resource.deleted_at is null
  ) as url_resources,
  (
    select count(*)
    from seed_tasks as task
    where not exists (
      select 1
      from public.task_resources as resource
      where resource.user_id = task.user_id
        and resource.task_occurrence_id = task.id
        and resource.resource_type = 'url'
        and resource.deleted_at is null
    )
  ) as tasks_missing_url,
  (
    select count(*)
    from seed_tasks as task
    where task.roadmap_id is null
      or task.roadmap_phase_id is null
  ) as tasks_missing_roadmap_relationship,
  (
    select count(*)
    from public.sync_conflicts as conflict, owner
    where conflict.user_id = owner.id
      and conflict.resolution_status = 'unresolved'
  ) as unresolved_sync_conflicts;
