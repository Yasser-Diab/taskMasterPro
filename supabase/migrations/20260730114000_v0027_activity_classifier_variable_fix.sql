-- Qualify the PL/pgSQL variable with the function's implicit outer block
-- label. Qualifying only the table column is insufficient because PostgreSQL
-- still considers an unqualified right-hand identifier ambiguous.

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

  -- A clean baseline already contains the completed alias and explicit block
  -- label. Keep this historical repair idempotent for fresh deployments.
  canonical_definition :=
    position('<<activity_classifier>>' in lower(original_definition)) > 0
    and position('from public.application_catalog as catalog' in lower(original_definition)) > 0
    and position('lower(catalog.application_identifier) =' in lower(original_definition)) > 0
    and position('activity_classifier.application_identifier' in lower(original_definition)) > 0;

  if not canonical_definition then
    repaired_definition := replace(
      original_definition,
      'from public.application_catalog as application',
      'from public.application_catalog as catalog'
    );
    repaired_definition := replace(
      repaired_definition,
      'and lower(application.application_identifier) = application_identifier',
      'and lower(catalog.application_identifier) =
            classify_activity_review_v0027.application_identifier'
    );

    if repaired_definition = original_definition then
      raise exception
        'Activity classifier variable repair could not locate the expression';
    end if;

    execute repaired_definition;
  end if;
end;
$repair$;
