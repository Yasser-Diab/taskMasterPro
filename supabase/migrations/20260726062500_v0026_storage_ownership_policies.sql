-- TaskMaster Pro v0.0.26
-- Private avatar and task-resource access. Object paths are always rooted at
-- the authenticated account UUID, for example <user-id>/avatar.jpg.

drop policy if exists taskmaster_storage_select_own on storage.objects;
create policy taskmaster_storage_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id in ('avatars', 'task-resources')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists taskmaster_storage_insert_own on storage.objects;
create policy taskmaster_storage_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id in ('avatars', 'task-resources')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists taskmaster_storage_update_own on storage.objects;
create policy taskmaster_storage_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id in ('avatars', 'task-resources')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id in ('avatars', 'task-resources')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists taskmaster_storage_delete_own on storage.objects;
create policy taskmaster_storage_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id in ('avatars', 'task-resources')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
