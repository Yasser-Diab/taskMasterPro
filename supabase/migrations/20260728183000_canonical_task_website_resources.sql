-- Website resources created by early v0.0.26 builds used the non-canonical
-- `website` type even though the clients open web resources as `url`.
-- Advance the revision so every signed-in device receives the repaired rows.
update public.task_resources
set
  resource_type = 'url',
  data = coalesce(data, '{}'::jsonb) || jsonb_build_object(
    'resource_type',
    'url'
  ),
  revision = revision + 1,
  updated_at = now()
where deleted_at is null
  and resource_type = 'website'
  and storage_location = 'url'
  and storage_path ~* '^https?://';
