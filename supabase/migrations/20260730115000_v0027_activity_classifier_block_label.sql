-- Give the function body an explicit PL/pgSQL block label so the local
-- application identifier can be distinguished from the catalog column.

do $repair$
declare
  classifier_signature regprocedure :=
    'taskmaster_internal.classify_activity_review_v0027(uuid,uuid,bigint,uuid,bigint,text,uuid,text,jsonb)'::regprocedure;
  original_definition text;
  repaired_definition text;
  canonical_definition boolean;
begin
  select pg_get_functiondef(classifier_signature)
  into original_definition;

  -- The current clean baseline is already labelled and fully qualified. Do
  -- not turn that valid final state into a migration failure.
  canonical_definition :=
    position('<<activity_classifier>>' in lower(original_definition)) > 0
    and position('from public.application_catalog as catalog' in lower(original_definition)) > 0
    and position('lower(catalog.application_identifier) =' in lower(original_definition)) > 0
    and position('activity_classifier.application_identifier' in lower(original_definition)) > 0;

  if not canonical_definition then
    repaired_definition := replace(
      original_definition,
      E'declare\n  owner_id uuid',
      E'<<activity_classifier>>\ndeclare\n  owner_id uuid'
    );
    repaired_definition := replace(
      repaired_definition,
      'classify_activity_review_v0027.application_identifier',
      'activity_classifier.application_identifier'
    );

    if repaired_definition = original_definition
        or position('<<activity_classifier>>' in repaired_definition) = 0 then
      raise exception
        'Activity classifier block-label repair could not locate the function body';
    end if;

    execute repaired_definition;
  end if;
end;
$repair$;
