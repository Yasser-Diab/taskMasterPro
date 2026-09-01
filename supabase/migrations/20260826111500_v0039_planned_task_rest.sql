-- DayVector v0.0.29: canonical optional rest inside a task plan.
--
-- The value intentionally travels in the existing task data/execution_settings
-- JSON objects. Those objects already participate in the guarded task command,
-- revision, conflict, snapshot, and Realtime convergence paths. Creating a
-- separate row or command type would let the task and its rest diverge.

alter table public.task_occurrences
  drop constraint if exists task_occurrences_planned_rest_duration_ms_check;

alter table public.task_occurrences
  add constraint task_occurrences_planned_rest_duration_ms_check
  check (
    case
      when not (data ? 'planned_rest_duration_ms') then true
      when pg_catalog.jsonb_typeof(data -> 'planned_rest_duration_ms') <> 'number'
        then false
      else (data ->> 'planned_rest_duration_ms')::numeric
        between 0 and 2147483647
    end
  ) not valid;

comment on column public.task_occurrences.data is
  'Canonical task settings. planned_rest_duration_ms reserves optional rest inside the occupied task window without counting it as expected work.';

alter table public.task_templates
  drop constraint if exists task_templates_planned_rest_duration_ms_check;

alter table public.task_templates
  add constraint task_templates_planned_rest_duration_ms_check
  check (
    case
      when not (execution_settings ? 'planned_rest_duration_ms') then true
      when pg_catalog.jsonb_typeof(
        execution_settings -> 'planned_rest_duration_ms'
      ) <> 'number' then false
      else (execution_settings ->> 'planned_rest_duration_ms')::numeric
        between 0 and 2147483647
    end
  ) not valid;

comment on column public.task_templates.execution_settings is
  'Canonical execution settings inherited by generated task occurrences, including optional planned_rest_duration_ms.';
