-- Evaluate the authenticated user once per statement instead of once per
-- realtime.messages row. This keeps the private per-user runtime channel
-- policy efficient without broadening access.
drop policy if exists taskmaster_runtime_broadcast_receive
  on realtime.messages;

create policy taskmaster_runtime_broadcast_receive
  on realtime.messages
  for select
  to authenticated
  using (
    topic =
      'taskmaster:user:' || (select auth.uid())::text || ':runtime'
  );
