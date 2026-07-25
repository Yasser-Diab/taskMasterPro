-- Keep the existing, tested generic command procedure intact and extend only
-- its table allowlist for the two remaining activity subsystem records.
do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.apply_entity_command(uuid,uuid,bigint,text,uuid,bigint,text,jsonb)'::regprocedure
  )
  into function_definition;

  if function_definition not like '%''contribution_roadmap_effects''%' then
    function_definition := replace(
      function_definition,
      quote_literal('activity_contributions') || ',',
      quote_literal('activity_contributions') || ',' || chr(10) ||
        '    ' || quote_literal('contribution_roadmap_effects') || ',' || chr(10) ||
        '    ' || quote_literal('activity_review_queue') || ','
    );
    execute function_definition;
  end if;
end
$migration$;

revoke all on function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) from public, anon;

grant execute on function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) to authenticated;
