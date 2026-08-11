-- v0.0.26: raw Activity observations stay on the source device by default.
--
-- Approved contribution summaries retain stable local source identifiers for
-- retry deduplication, but the corresponding private raw segment and local
-- attribution are intentionally not required to exist in Supabase.
do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select conname
    from pg_constraint
    where conrelid = 'public.activity_contributions'::regclass
      and contype = 'f'
      and confrelid in (
        'public.activity_segments'::regclass,
        'public.activity_attributions'::regclass
      )
  loop
    execute format(
      'alter table public.activity_contributions drop constraint %I',
      constraint_name
    );
  end loop;
end
$$;

comment on table public.activity_segments is
  'Optional detailed Activity history. Normal clients keep raw observations device-local and upload them only after explicit opt-in.';

comment on table public.activity_contributions is
  'Privacy-minimized, user-approved task or roadmap contribution summaries. Source identifiers are stable deduplication references and do not require uploaded raw observations.';

create or replace function public.apply_activity_contribution_batch(
  p_commands jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  item jsonb;
  result_items jsonb := '[]'::jsonb;
  command_result jsonb;
begin
  if jsonb_typeof(p_commands) <> 'array' then
    raise exception 'invalid_contribution_batch';
  end if;
  if jsonb_array_length(p_commands) < 1
      or jsonb_array_length(p_commands) > 20 then
    raise exception 'invalid_contribution_batch_size';
  end if;

  for item in select value from jsonb_array_elements(p_commands)
  loop
    command_result := public.apply_entity_command(
      (item ->> 'command_id')::uuid,
      (item ->> 'device_id')::uuid,
      (item ->> 'device_sequence')::bigint,
      'activity_contributions',
      (item ->> 'entity_id')::uuid,
      coalesce((item ->> 'base_revision')::bigint, 0),
      coalesce(item ->> 'operation', 'create'),
      coalesce(item -> 'payload', '{}'::jsonb)
    );
    result_items := result_items || jsonb_build_array(
      jsonb_build_object(
        'command_id', item ->> 'command_id',
        'result', command_result
      )
    );
  end loop;
  return result_items;
end
$$;

revoke all on function public.apply_activity_contribution_batch(jsonb)
  from public;
grant execute on function public.apply_activity_contribution_batch(jsonb)
  to authenticated;

comment on function public.apply_activity_contribution_batch(jsonb) is
  'Applies up to twenty privacy-minimized Activity contributions with stable command IDs in one authenticated request.';
