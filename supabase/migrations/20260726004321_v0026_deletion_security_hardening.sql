drop policy if exists account_deletion_requests_insert_own
  on public.account_deletion_requests;
create policy account_deletion_requests_insert_own
  on public.account_deletion_requests for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists account_deletion_requests_update_own
  on public.account_deletion_requests;
create policy account_deletion_requests_update_own
  on public.account_deletion_requests for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function private.enforce_account_deletion_request()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.id := (select auth.uid());
    new.user_id := (select auth.uid());
    new.requested_at := statement_timestamp();
    new.scheduled_for := statement_timestamp() + interval '30 days';
    new.status := 'scheduled';
    new.cancelled_at := null;
  else
    new.id := old.id;
    new.user_id := old.user_id;
    if new.status = 'scheduled' and old.status <> 'scheduled' then
      new.requested_at := statement_timestamp();
      new.scheduled_for := statement_timestamp() + interval '30 days';
      new.cancelled_at := null;
    elsif new.status = 'cancelled' and old.status = 'scheduled' then
      new.cancelled_at := statement_timestamp();
      new.scheduled_for := old.scheduled_for;
    else
      new.requested_at := old.requested_at;
      new.scheduled_for := old.scheduled_for;
      new.cancelled_at := old.cancelled_at;
    end if;
  end if;
  return new;
end;
$$;

revoke insert, update, delete on public.account_deletion_requests from anon;
revoke delete on public.account_deletion_requests from authenticated;
grant select, insert, update on public.account_deletion_requests
  to authenticated;

drop trigger if exists enforce_account_deletion_request
  on public.account_deletion_requests;
create trigger enforce_account_deletion_request
  before insert or update on public.account_deletion_requests
  for each row execute function private.enforce_account_deletion_request();

alter function public.schedule_account_deletion(uuid, text)
  security invoker;
alter function public.cancel_account_deletion(uuid)
  security invoker;
