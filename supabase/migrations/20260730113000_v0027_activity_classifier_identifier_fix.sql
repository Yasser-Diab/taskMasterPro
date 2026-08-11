-- Fix the already-deployed v0.0.27 Activity classifier without rewriting
-- applied migration history. The original expression used the same name for a
-- PL/pgSQL variable and a table column, so PostgreSQL rejected the query as
-- ambiguous when that branch executed.

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

  -- The clean baseline already defines the fully repaired function. Historical
  -- upgrades still need the textual repair below, but a fresh schema must not
  -- fail merely because there is nothing left to rewrite.
  canonical_definition :=
    position('<<activity_classifier>>' in lower(original_definition)) > 0
    and position('from public.application_catalog as catalog' in lower(original_definition)) > 0
    and position('lower(catalog.application_identifier) =' in lower(original_definition)) > 0
    and position('activity_classifier.application_identifier' in lower(original_definition)) > 0;

  if not canonical_definition then
    repaired_definition := replace(
      original_definition,
      'from public.application_catalog
        where user_id = owner_id',
      'from public.application_catalog as application
        where user_id = owner_id'
    );
    repaired_definition := replace(
      repaired_definition,
      'and lower(application_identifier) = application_identifier',
      'and lower(application.application_identifier) = application_identifier'
    );

    if repaired_definition = original_definition then
      raise exception
        'Activity classifier repair could not locate the ambiguous expression';
    end if;

    execute repaired_definition;
  end if;
end;
$repair$;
