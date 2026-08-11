-- The public wrapper is intentionally callable by authenticated clients, but
-- the atomic classifier touches several owner-scoped tables in one
-- transaction. Run its internal implementation with the migration owner while
-- keeping every row explicitly constrained to auth.uid() and a registered
-- account device.

alter function taskmaster_internal.classify_activity_review_v0027(
  uuid,
  uuid,
  bigint,
  uuid,
  bigint,
  text,
  uuid,
  text,
  jsonb
) security definer;

alter function taskmaster_internal.classify_activity_review_v0027(
  uuid,
  uuid,
  bigint,
  uuid,
  bigint,
  text,
  uuid,
  text,
  jsonb
) set search_path = '';

revoke all on function taskmaster_internal.classify_activity_review_v0027(
  uuid,
  uuid,
  bigint,
  uuid,
  bigint,
  text,
  uuid,
  text,
  jsonb
) from public, anon;

grant execute on function taskmaster_internal.classify_activity_review_v0027(
  uuid,
  uuid,
  bigint,
  uuid,
  bigint,
  text,
  uuid,
  text,
  jsonb
) to authenticated, service_role;

comment on function taskmaster_internal.classify_activity_review_v0027(
  uuid,
  uuid,
  bigint,
  uuid,
  bigint,
  text,
  uuid,
  text,
  jsonb
) is
  'Owner- and registered-device-scoped atomic Activity classification implementation.';
