-- A normal update command is never a restore command.  Without this guard an
-- old offline mutation could clear `deleted_at` after another device had
-- already deleted the record, effectively bringing a task back from deletion.
-- Explicit restore flows can opt in inside a trusted server transaction with
-- `set_config('taskmaster.allow_tombstone_restore', 'on', true)`.
create or replace function private.preserve_synchronized_tombstone()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.deleted_at is not null
      and new.deleted_at is null
      and coalesce(current_setting('taskmaster.allow_tombstone_restore', true), 'off') <> 'on' then
    new.deleted_at := old.deleted_at;
  end if;
  return new;
end;
$$;

do $$
declare
  table_record record;
begin
  for table_record in
    select table_name
    from information_schema.columns
    where table_schema = 'public' and column_name = 'deleted_at'
    group by table_name
  loop
    execute format(
      'drop trigger if exists aaa_preserve_synchronized_tombstone on public.%I',
      table_record.table_name
    );
    execute format(
      'create trigger aaa_preserve_synchronized_tombstone
       before update on public.%I
       for each row execute function private.preserve_synchronized_tombstone()',
      table_record.table_name
    );
  end loop;
end;
$$;
