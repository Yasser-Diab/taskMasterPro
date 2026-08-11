-- v0.0.27 canonical task areas and occurrence semantics.
--
-- Built-in task domains are still account-owned rows so every task foreign key
-- remains protected by the existing per-user RLS policies. UUID v5 identities
-- make offline seeding converge across devices without using names, locale, or
-- array positions as synchronization identity.

create extension if not exists "uuid-ossp" with schema extensions;

create or replace function private.seed_default_task_domains(
  p_user_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.task_domains (
    id,
    user_id,
    name,
    icon_name,
    color_value,
    position,
    data
  )
  select
    extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || p_user_id::text ||
      '/task-domain/' || seed.domain_key
    ),
    p_user_id,
    seed.canonical_name,
    seed.icon_name,
    seed.color_value,
    seed.position,
    jsonb_build_object(
      'built_in', true,
      'domain_key', seed.domain_key
    )
  from (
    values
      ('work', 'Work', 'work', -12490271, 0),
      ('learning', 'Learning', 'school', -16734065, 1),
      ('reading', 'Reading', 'book', -7447625, 2),
      ('health', 'Health', 'health', -1748141, 3),
      ('personal', 'Personal', 'person', -1926355, 4),
      ('family', 'Family', 'family_restroom', -5219130, 5),
      ('household', 'Household', 'home', -9728477, 6),
      ('finance', 'Finance', 'account_balance_wallet', -13726889, 7),
      ('fitness', 'Fitness', 'fitness_center', -1086377, 8),
      ('projects', 'Projects', 'rocket_launch', -11508535, 9),
      ('errands', 'Errands', 'shopping_bag', -6655934, 10)
  ) as seed(
    domain_key,
    canonical_name,
    icon_name,
    color_value,
    position
  )
  on conflict (id) do update
  set deleted_at = null,
      archived_at = null,
      data = public.task_domains.data || excluded.data;
$$;

revoke all on function private.seed_default_task_domains(uuid)
  from public, anon, authenticated;

create or replace function private.seed_default_task_domains_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.seed_default_task_domains(new.id);
  return new;
end;
$$;

drop trigger if exists taskmaster_seed_default_task_domains
  on auth.users;
create trigger taskmaster_seed_default_task_domains
after insert on auth.users
for each row
execute function private.seed_default_task_domains_for_new_user();

do $$
declare
  account record;
begin
  for account in select id from auth.users loop
    perform private.seed_default_task_domains(account.id);
  end loop;
end;
$$;

-- Early builds inserted five English starter rows with random UUIDs. Remap
-- only that exact built-in name/icon signature; user-created areas are never
-- inferred from a translated label.
with builtins(domain_key, canonical_name, icon_name) as (
  values
    ('work', 'Work', 'work'),
    ('learning', 'Learning', 'school'),
    ('reading', 'Reading', 'book'),
    ('health', 'Health', 'health'),
    ('personal', 'Personal', 'person')
),
legacy as (
  select
    domain.user_id,
    domain.id as legacy_id,
    extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    ) as canonical_id
  from public.task_domains domain
  join builtins
    on domain.name = builtins.canonical_name
   and domain.icon_name = builtins.icon_name
  where domain.deleted_at is null
    and domain.id <> extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    )
)
update public.task_occurrences occurrence
set domain_id = legacy.canonical_id
from legacy
where occurrence.user_id = legacy.user_id
  and occurrence.domain_id = legacy.legacy_id;

with builtins(domain_key, canonical_name, icon_name) as (
  values
    ('work', 'Work', 'work'),
    ('learning', 'Learning', 'school'),
    ('reading', 'Reading', 'book'),
    ('health', 'Health', 'health'),
    ('personal', 'Personal', 'person')
),
legacy as (
  select
    domain.user_id,
    domain.id as legacy_id,
    extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    ) as canonical_id
  from public.task_domains domain
  join builtins
    on domain.name = builtins.canonical_name
   and domain.icon_name = builtins.icon_name
  where domain.deleted_at is null
    and domain.id <> extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    )
)
update public.task_templates template
set domain_id = legacy.canonical_id
from legacy
where template.user_id = legacy.user_id
  and template.domain_id = legacy.legacy_id;

with builtins(domain_key, canonical_name, icon_name) as (
  values
    ('work', 'Work', 'work'),
    ('learning', 'Learning', 'school'),
    ('reading', 'Reading', 'book'),
    ('health', 'Health', 'health'),
    ('personal', 'Personal', 'person')
),
legacy as (
  select
    domain.user_id,
    domain.id as legacy_id,
    extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    ) as canonical_id
  from public.task_domains domain
  join builtins
    on domain.name = builtins.canonical_name
   and domain.icon_name = builtins.icon_name
  where domain.deleted_at is null
    and domain.id <> extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    )
)
update public.task_categories category
set domain_id = legacy.canonical_id
from legacy
where category.user_id = legacy.user_id
  and category.domain_id = legacy.legacy_id;

with builtins(domain_key, canonical_name, icon_name) as (
  values
    ('work', 'Work', 'work'),
    ('learning', 'Learning', 'school'),
    ('reading', 'Reading', 'book'),
    ('health', 'Health', 'health'),
    ('personal', 'Personal', 'person')
),
legacy as (
  select
    domain.user_id,
    domain.id as legacy_id,
    builtins.domain_key
  from public.task_domains domain
  join builtins
    on domain.name = builtins.canonical_name
   and domain.icon_name = builtins.icon_name
  where domain.deleted_at is null
    and domain.id <> extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://taskmasterpro.app/account/' || domain.user_id::text ||
      '/task-domain/' || builtins.domain_key
    )
)
update public.task_domains domain
set deleted_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    revision = revision + 1,
    data = data || jsonb_build_object(
      'replaced_by_builtin_key',
      legacy.domain_key
    )
from legacy
where domain.user_id = legacy.user_id
  and domain.id = legacy.legacy_id;

create unique index if not exists task_domains_user_builtin_key_unique
on public.task_domains (
  user_id,
  ((data ->> 'domain_key'))
)
where deleted_at is null
  and coalesce((data ->> 'built_in')::boolean, false);

create or replace function public.task_occurrence_is_overdue(
  p_status public.task_status,
  p_due_at timestamptz,
  p_deleted_at timestamptz,
  p_data jsonb,
  p_at timestamptz default statement_timestamp()
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    p_deleted_at is null
    and p_due_at is not null
    and p_due_at < p_at
    and p_status <> all (
      array[
        'completed',
        'cancelled',
        'archived'
      ]::public.task_status[]
    )
    and coalesce(p_data ->> 'occurrence_state', '') not in (
      'skipped',
      'replaced'
    )
    and coalesce((p_data ->> 'is_recurrence_template')::boolean, false) = false
    and coalesce(p_data ->> 'record_type', '') <> 'template';
$$;

revoke all on function public.task_occurrence_is_overdue(
  public.task_status,
  timestamptz,
  timestamptz,
  jsonb,
  timestamptz
) from public, anon;
grant execute on function public.task_occurrence_is_overdue(
  public.task_status,
  timestamptz,
  timestamptz,
  jsonb,
  timestamptz
) to authenticated;

create or replace view public.current_overdue_task_occurrences
with (security_invoker = true)
as
select occurrence.*
from public.task_occurrences occurrence
where occurrence.user_id = (select auth.uid())
  and public.task_occurrence_is_overdue(
    occurrence.status,
    occurrence.due_at,
    occurrence.deleted_at,
    occurrence.data,
    statement_timestamp()
  );

revoke all on public.current_overdue_task_occurrences from public, anon;
grant select on public.current_overdue_task_occurrences to authenticated;

comment on view public.current_overdue_task_occurrences is
  'Canonical open occurrences whose real due instant has passed. Recurrence templates, skipped/replaced rows, terminal statuses, and tombstones are excluded.';
