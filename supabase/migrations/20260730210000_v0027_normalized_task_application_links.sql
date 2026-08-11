-- TaskMaster Pro v0.0.27: normalized, idempotent task application links.
--
-- `application_catalog` remains the canonical application identity used by
-- Activity history. A task connection and a per-user naming/classification
-- override are separate user-owned records. Every task link carries compact
-- display snapshots so a receiving device never needs a second request merely
-- to render an accessible label.

create or replace function private.normalize_application_key(
  p_platform text,
  p_raw_identifier text
)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select coalesce(
    nullif(
      pg_catalog.btrim(
        pg_catalog.regexp_replace(
          pg_catalog.lower(pg_catalog.btrim(p_raw_identifier)),
          '[^a-z0-9]+',
          '_',
          'g'
        ),
        '_'
      ),
      ''
    ),
    'unknown'
  )
$$;

revoke all on function private.normalize_application_key(text, text)
  from public, anon, authenticated;

alter table public.application_catalog
  add column if not exists normalized_application_key text,
  add column if not exists default_display_name text,
  add column if not exists icon_reference text,
  add column if not exists category text;

update public.application_catalog
set normalized_application_key = private.normalize_application_key(
      platform,
      application_identifier
    ),
    default_display_name = coalesce(
      nullif(pg_catalog.btrim(default_display_name), ''),
      nullif(pg_catalog.btrim(display_name), ''),
      nullif(pg_catalog.btrim(application_identifier), ''),
      'Unknown application'
    ),
    icon_reference = coalesce(
      nullif(pg_catalog.btrim(icon_reference), ''),
      nullif(pg_catalog.btrim(icon_path), '')
    )
where normalized_application_key is null
   or pg_catalog.btrim(normalized_application_key) = ''
   or default_display_name is null
   or pg_catalog.btrim(default_display_name) = '';

alter table public.application_catalog
  alter column normalized_application_key set not null,
  alter column default_display_name set not null;

-- Merge pre-existing catalog aliases before enforcing normalized identity.
-- Rules that would become semantically duplicated are tombstoned first so the
-- existing active-rule uniqueness invariant is never violated.
with catalog_aliases as (
  select
    catalog.id,
    catalog.user_id,
    pg_catalog.first_value(catalog.id) over (
      partition by
        catalog.user_id,
        pg_catalog.lower(catalog.platform),
        catalog.normalized_application_key
      order by catalog.created_at, catalog.id
    ) as canonical_id
  from public.application_catalog as catalog
  where catalog.deleted_at is null
),
ranked_rules as (
  select
    rule.id,
    pg_catalog.row_number() over (
      partition by
        rule.user_id,
        aliases.canonical_id,
        rule.scope_type,
        coalesce(
          rule.scope_id,
          '00000000-0000-0000-0000-000000000000'::uuid
        )
      order by rule.updated_at desc, rule.created_at desc, rule.id
    ) as semantic_rank
  from public.application_rules as rule
  join catalog_aliases as aliases
    on aliases.user_id = rule.user_id
   and aliases.id = rule.application_id
  where rule.deleted_at is null
)
update public.application_rules as rule
set deleted_at = pg_catalog.statement_timestamp(),
    data = rule.data || pg_catalog.jsonb_build_object(
      'superseded_by_v0027', true,
      'repair_reason', 'normalized_application_alias'
    )
from ranked_rules
where ranked_rules.id = rule.id
  and ranked_rules.semantic_rank > 1;

with catalog_aliases as (
  select
    catalog.id,
    catalog.user_id,
    pg_catalog.first_value(catalog.id) over (
      partition by
        catalog.user_id,
        pg_catalog.lower(catalog.platform),
        catalog.normalized_application_key
      order by catalog.created_at, catalog.id
    ) as canonical_id
  from public.application_catalog as catalog
  where catalog.deleted_at is null
)
update public.application_rules as rule
set application_id = aliases.canonical_id
from catalog_aliases as aliases
where aliases.user_id = rule.user_id
  and aliases.id = rule.application_id
  and aliases.id <> aliases.canonical_id
  and rule.deleted_at is null;

with catalog_aliases as (
  select
    catalog.id,
    catalog.user_id,
    pg_catalog.first_value(catalog.id) over (
      partition by
        catalog.user_id,
        pg_catalog.lower(catalog.platform),
        catalog.normalized_application_key
      order by catalog.created_at, catalog.id
    ) as canonical_id
  from public.application_catalog as catalog
  where catalog.deleted_at is null
)
update public.activity_segments as segment
set application_id = aliases.canonical_id
from catalog_aliases as aliases
where aliases.user_id = segment.user_id
  and aliases.id = segment.application_id
  and aliases.id <> aliases.canonical_id
  and segment.deleted_at is null;

with catalog_aliases as (
  select
    catalog.id,
    catalog.user_id,
    pg_catalog.first_value(catalog.id) over (
      partition by
        catalog.user_id,
        pg_catalog.lower(catalog.platform),
        catalog.normalized_application_key
      order by catalog.created_at, catalog.id
    ) as canonical_id
  from public.application_catalog as catalog
  where catalog.deleted_at is null
)
update public.classification_feedback as feedback
set application_id = aliases.canonical_id
from catalog_aliases as aliases
where aliases.user_id = feedback.user_id
  and aliases.id = feedback.application_id
  and aliases.id <> aliases.canonical_id
  and feedback.deleted_at is null;

with catalog_aliases as (
  select
    catalog.id,
    pg_catalog.first_value(catalog.id) over (
      partition by
        catalog.user_id,
        pg_catalog.lower(catalog.platform),
        catalog.normalized_application_key
      order by catalog.created_at, catalog.id
    ) as canonical_id
  from public.application_catalog as catalog
  where catalog.deleted_at is null
)
update public.application_catalog as catalog
set deleted_at = pg_catalog.statement_timestamp(),
    data = catalog.data || pg_catalog.jsonb_build_object(
      'superseded_by_v0027', true,
      'repair_reason', 'normalized_application_alias',
      'canonical_application_id', aliases.canonical_id
    )
from catalog_aliases as aliases
where aliases.id = catalog.id
  and aliases.id <> aliases.canonical_id;

create unique index if not exists application_catalog_normalized_key_v0027_idx
  on public.application_catalog (
    user_id,
    pg_catalog.lower(platform),
    normalized_application_key
  )
  where deleted_at is null;

create table if not exists public.user_application_overrides (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  application_id uuid not null,
  custom_display_name text,
  custom_category text,
  classification text,
  status text not null default 'active',
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, application_id)
    references public.application_catalog (user_id, id),
  unique (user_id, id)
);

create unique index if not exists user_application_overrides_identity_v0027_idx
  on public.user_application_overrides (user_id, application_id)
  where deleted_at is null;

create table if not exists public.task_application_links (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  task_occurrence_id uuid not null,
  application_id uuid not null,
  relationship_type text not null default 'supporting',
  display_name_snapshot text not null default 'Unknown application',
  raw_identifier_snapshot text,
  normalized_application_key_snapshot text,
  icon_reference_snapshot text,
  status text not null default 'active',
  position numeric(20, 10) not null default 0,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, task_occurrence_id)
    references public.task_occurrences (user_id, id),
  foreign key (user_id, application_id)
    references public.application_catalog (user_id, id),
  unique (user_id, id)
);

create unique index if not exists task_application_links_identity_v0027_idx
  on public.task_application_links (
    user_id,
    task_occurrence_id,
    application_id
  )
  where deleted_at is null;

create index if not exists task_application_links_task_v0027_idx
  on public.task_application_links (
    user_id,
    task_occurrence_id,
    position,
    updated_at
  )
  where deleted_at is null;

create index if not exists task_application_links_application_v0027_idx
  on public.task_application_links (user_id, application_id)
  where deleted_at is null;

-- Reject malformed cross-account rules. They are retained as tombstones for
-- diagnostics and cannot be transformed into a visible task link.
update public.application_rules as rule
set deleted_at = pg_catalog.statement_timestamp(),
    data = rule.data || pg_catalog.jsonb_build_object(
      'tombstoned_by_v0027', true,
      'repair_reason', 'cross_account_application_reference'
    )
where rule.deleted_at is null
  and rule.scope_type = 'task'
  and exists (
    select 1
    from public.application_catalog as catalog
    where catalog.id = rule.application_id
      and catalog.user_id <> rule.user_id
  );

-- A legacy task rule can exist without catalog metadata. Preserve its UUID and
-- history by creating an explicit unknown identity owned by the same account.
insert into public.application_catalog (
  id,
  user_id,
  platform,
  application_identifier,
  normalized_application_key,
  display_name,
  default_display_name,
  classification,
  created_by_device_id,
  updated_by_device_id,
  data
)
select distinct on (rule.user_id, rule.application_id)
  rule.application_id,
  rule.user_id,
  coalesce(nullif(rule.data ->> 'platform', ''), 'unknown'),
  'legacy-missing:' || rule.application_id::text,
  private.normalize_application_key(
    coalesce(nullif(rule.data ->> 'platform', ''), 'unknown'),
    'legacy-missing:' || rule.application_id::text
  ),
  coalesce(
    nullif(rule.data ->> 'display_name_snapshot', ''),
    'Unknown application'
  ),
  coalesce(
    nullif(rule.data ->> 'display_name_snapshot', ''),
    'Unknown application'
  ),
  coalesce(nullif(rule.classification, ''), 'unknown'),
  rule.created_by_device_id,
  rule.updated_by_device_id,
  pg_catalog.jsonb_build_object(
    'recovered_by_v0027', true,
    'repair_reason', 'missing_application_metadata',
    'reported_raw_identifier', coalesce(
      nullif(rule.data ->> 'application_identifier', ''),
      nullif(rule.data ->> 'raw_identifier_snapshot', '')
    )
  )
from public.application_rules as rule
join public.task_occurrences as task
  on task.user_id = rule.user_id
 and task.id = rule.scope_id
 and task.deleted_at is null
where rule.deleted_at is null
  and rule.scope_type = 'task'
  and rule.scope_id is not null
  and not exists (
    select 1
    from public.application_catalog as catalog
    where catalog.id = rule.application_id
  )
order by rule.user_id, rule.application_id, rule.created_at, rule.id
on conflict (id) do nothing;

-- Convert the old task-scoped classification rule into one normalized link.
-- The original rule stays available to Activity learning; unlinking a task
-- never deletes the shared application identity or historical classifications.
insert into public.task_application_links (
  id,
  user_id,
  task_occurrence_id,
  application_id,
  relationship_type,
  display_name_snapshot,
  raw_identifier_snapshot,
  normalized_application_key_snapshot,
  icon_reference_snapshot,
  status,
  position,
  created_at,
  updated_at,
  created_by_device_id,
  updated_by_device_id,
  last_command_id,
  data
)
select distinct on (rule.user_id, rule.scope_id, rule.application_id)
  rule.id,
  rule.user_id,
  rule.scope_id,
  rule.application_id,
  'supporting',
  coalesce(
    nullif(pg_catalog.btrim(override_row.custom_display_name), ''),
    nullif(pg_catalog.btrim(catalog.default_display_name), ''),
    nullif(pg_catalog.btrim(catalog.display_name), ''),
    nullif(pg_catalog.btrim(catalog.application_identifier), ''),
    'Unknown application'
  ),
  catalog.application_identifier,
  catalog.normalized_application_key,
  coalesce(catalog.icon_reference, catalog.icon_path),
  'active',
  0,
  rule.created_at,
  rule.updated_at,
  rule.created_by_device_id,
  rule.updated_by_device_id,
  rule.last_command_id,
  pg_catalog.jsonb_build_object(
    'migrated_from_application_rule_id', rule.id,
    'classification', rule.classification,
    'automatic_credit', rule.automatic_credit
  )
from public.application_rules as rule
join public.task_occurrences as task
  on task.user_id = rule.user_id
 and task.id = rule.scope_id
 and task.deleted_at is null
join public.application_catalog as catalog
  on catalog.user_id = rule.user_id
 and catalog.id = rule.application_id
 and catalog.deleted_at is null
left join public.user_application_overrides as override_row
  on override_row.user_id = rule.user_id
 and override_row.application_id = rule.application_id
 and override_row.deleted_at is null
where rule.deleted_at is null
  and rule.scope_type = 'task'
  and rule.scope_id is not null
order by
  rule.user_id,
  rule.scope_id,
  rule.application_id,
  rule.updated_at desc,
  rule.created_at desc,
  rule.id
on conflict (id) do nothing;

drop trigger if exists prepare_user_application_overrides
  on public.user_application_overrides;
create trigger prepare_user_application_overrides
before insert or update on public.user_application_overrides
for each row execute function private.prepare_synchronized_record();

drop trigger if exists prepare_task_application_links
  on public.task_application_links;
create trigger prepare_task_application_links
before insert or update on public.task_application_links
for each row execute function private.prepare_synchronized_record();

drop trigger if exists log_user_application_overrides
  on public.user_application_overrides;
create trigger log_user_application_overrides
after insert or update on public.user_application_overrides
for each row execute function private.log_synchronized_change();

drop trigger if exists log_task_application_links
  on public.task_application_links;
create trigger log_task_application_links
after insert or update on public.task_application_links
for each row execute function private.log_synchronized_change();

alter table public.user_application_overrides enable row level security;
alter table public.user_application_overrides force row level security;
alter table public.task_application_links enable row level security;
alter table public.task_application_links force row level security;

drop policy if exists owner_select_user_application_overrides
  on public.user_application_overrides;
create policy owner_select_user_application_overrides
  on public.user_application_overrides for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists owner_insert_user_application_overrides
  on public.user_application_overrides;
create policy owner_insert_user_application_overrides
  on public.user_application_overrides for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists owner_update_user_application_overrides
  on public.user_application_overrides;
create policy owner_update_user_application_overrides
  on public.user_application_overrides for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists owner_delete_user_application_overrides
  on public.user_application_overrides;
create policy owner_delete_user_application_overrides
  on public.user_application_overrides for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists owner_select_task_application_links
  on public.task_application_links;
create policy owner_select_task_application_links
  on public.task_application_links for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists owner_insert_task_application_links
  on public.task_application_links;
create policy owner_insert_task_application_links
  on public.task_application_links for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists owner_update_task_application_links
  on public.task_application_links;
create policy owner_update_task_application_links
  on public.task_application_links for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists owner_delete_task_application_links
  on public.task_application_links;
create policy owner_delete_task_application_links
  on public.task_application_links for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.user_application_overrides to authenticated;
grant select, insert, update, delete
  on public.task_application_links to authenticated;
revoke all on public.user_application_overrides from anon;
revoke all on public.task_application_links from anon;

create or replace function public.connect_application_to_task(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_application_id uuid,
  p_link_id uuid,
  p_task_occurrence_id uuid,
  p_platform text,
  p_raw_identifier text,
  p_detected_display_name text,
  p_relationship_type text default 'supporting'
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_result jsonb;
  normalized_platform text;
  normalized_key text;
  safe_raw_identifier text;
  safe_display_name text;
  canonical_application public.application_catalog%rowtype;
  canonical_link public.task_application_links%rowtype;
  override_name text;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null
     or p_device_id is null
     or p_application_id is null
     or p_link_id is null
     or p_task_occurrence_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_device_sequence < 1 then
    raise exception 'invalid_device_sequence' using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':command:' || p_command_id::text,
      0
    )
  );

  select command.result
  into existing_result
  from public.processed_commands as command
  where command.user_id = owner_id
    and command.command_id = p_command_id;
  if found then
    return existing_result;
  end if;

  if not exists (
    select 1
    from public.task_occurrences as task
    where task.user_id = owner_id
      and task.id = p_task_occurrence_id
      and task.deleted_at is null
  ) then
    raise exception 'task_not_available' using errcode = '23503';
  end if;

  normalized_platform := coalesce(
    nullif(pg_catalog.lower(pg_catalog.btrim(p_platform)), ''),
    'unknown'
  );
  safe_raw_identifier := coalesce(
    nullif(pg_catalog.btrim(p_raw_identifier), ''),
    'unknown:' || p_application_id::text
  );
  normalized_key := private.normalize_application_key(
    normalized_platform,
    safe_raw_identifier
  );
  safe_display_name := coalesce(
    nullif(pg_catalog.btrim(p_detected_display_name), ''),
    nullif(pg_catalog.btrim(safe_raw_identifier), ''),
    'Unknown application'
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':application:' || normalized_platform || ':' ||
      normalized_key,
      0
    )
  );

  select application.*
  into canonical_application
  from public.application_catalog as application
  where application.user_id = owner_id
    and pg_catalog.lower(application.platform) = normalized_platform
    and application.normalized_application_key = normalized_key
    and application.deleted_at is null
  order by application.created_at, application.id
  limit 1
  for update;

  if not found then
    insert into public.application_catalog (
      id,
      user_id,
      platform,
      application_identifier,
      normalized_application_key,
      display_name,
      default_display_name,
      classification,
      first_seen_at,
      last_seen_at,
      created_by_device_id,
      updated_by_device_id,
      last_command_id
    )
    values (
      p_application_id,
      owner_id,
      normalized_platform,
      pg_catalog.lower(safe_raw_identifier),
      normalized_key,
      safe_display_name,
      safe_display_name,
      'direct_task_work',
      pg_catalog.statement_timestamp(),
      pg_catalog.statement_timestamp(),
      p_device_id,
      p_device_id,
      p_command_id
    )
    returning * into canonical_application;
  else
    update public.application_catalog as application
    set display_name = case
          when nullif(pg_catalog.btrim(application.display_name), '') is null
            then safe_display_name
          else application.display_name
        end,
        default_display_name = case
          when nullif(
            pg_catalog.btrim(application.default_display_name),
            ''
          ) is null
            or application.default_display_name = 'Unknown application'
            then safe_display_name
          else application.default_display_name
        end,
        last_seen_at = pg_catalog.statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where application.user_id = owner_id
      and application.id = canonical_application.id
    returning * into canonical_application;
  end if;

  select nullif(pg_catalog.btrim(override_row.custom_display_name), '')
  into override_name
  from public.user_application_overrides as override_row
  where override_row.user_id = owner_id
    and override_row.application_id = canonical_application.id
    and override_row.deleted_at is null
  limit 1;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':task-application:' ||
      p_task_occurrence_id::text || ':' || canonical_application.id::text,
      0
    )
  );

  select link.*
  into canonical_link
  from public.task_application_links as link
  where link.user_id = owner_id
    and link.task_occurrence_id = p_task_occurrence_id
    and link.application_id = canonical_application.id
    and link.deleted_at is null
  order by link.created_at, link.id
  limit 1
  for update;

  if not found then
    -- Reconnecting after removal revives the same permanent link UUID. This
    -- avoids a local primary-key collision and preserves link history.
    select link.*
    into canonical_link
    from public.task_application_links as link
    where link.user_id = owner_id
      and link.id = p_link_id
    for update;

    if found then
      update public.task_application_links as link
      set task_occurrence_id = p_task_occurrence_id,
          application_id = canonical_application.id,
          relationship_type = coalesce(
            nullif(pg_catalog.btrim(p_relationship_type), ''),
            'supporting'
          ),
          display_name_snapshot = coalesce(
            override_name,
            nullif(
              pg_catalog.btrim(canonical_application.default_display_name),
              ''
            ),
            nullif(pg_catalog.btrim(canonical_application.display_name), ''),
            nullif(pg_catalog.btrim(safe_display_name), ''),
            'Unknown application'
          ),
          raw_identifier_snapshot = safe_raw_identifier,
          normalized_application_key_snapshot = normalized_key,
          icon_reference_snapshot = coalesce(
            canonical_application.icon_reference,
            canonical_application.icon_path
          ),
          status = 'active',
          deleted_at = null,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          data = link.data || pg_catalog.jsonb_build_object(
            'classification', 'direct_task_work',
            'automatic_credit', true
          )
      where link.user_id = owner_id
        and link.id = p_link_id
      returning * into canonical_link;
    else
      insert into public.task_application_links (
        id,
        user_id,
        task_occurrence_id,
        application_id,
        relationship_type,
        display_name_snapshot,
        raw_identifier_snapshot,
        normalized_application_key_snapshot,
        icon_reference_snapshot,
        status,
        created_by_device_id,
        updated_by_device_id,
        last_command_id,
        data
      )
      values (
        p_link_id,
        owner_id,
        p_task_occurrence_id,
        canonical_application.id,
        coalesce(
          nullif(pg_catalog.btrim(p_relationship_type), ''),
          'supporting'
        ),
        coalesce(
          override_name,
          nullif(
            pg_catalog.btrim(canonical_application.default_display_name),
            ''
          ),
          nullif(pg_catalog.btrim(canonical_application.display_name), ''),
          nullif(pg_catalog.btrim(safe_display_name), ''),
          'Unknown application'
        ),
        safe_raw_identifier,
        normalized_key,
        coalesce(
          canonical_application.icon_reference,
          canonical_application.icon_path
        ),
        'active',
        p_device_id,
        p_device_id,
        p_command_id,
        pg_catalog.jsonb_build_object(
          'classification', 'direct_task_work',
          'automatic_credit', true
        )
      )
      returning * into canonical_link;
    end if;
  else
    update public.task_application_links as link
    set relationship_type = coalesce(
          nullif(pg_catalog.btrim(p_relationship_type), ''),
          link.relationship_type
        ),
        display_name_snapshot = coalesce(
          override_name,
          nullif(
            pg_catalog.btrim(canonical_application.default_display_name),
            ''
          ),
          nullif(pg_catalog.btrim(canonical_application.display_name), ''),
          nullif(pg_catalog.btrim(link.display_name_snapshot), ''),
          safe_display_name,
          'Unknown application'
        ),
        raw_identifier_snapshot = coalesce(
          nullif(pg_catalog.btrim(link.raw_identifier_snapshot), ''),
          safe_raw_identifier
        ),
        normalized_application_key_snapshot = normalized_key,
        icon_reference_snapshot = coalesce(
          canonical_application.icon_reference,
          canonical_application.icon_path,
          link.icon_reference_snapshot
        ),
        status = 'active',
        deleted_at = null,
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = link.data || pg_catalog.jsonb_build_object(
          'classification', 'direct_task_work',
          'automatic_credit', true
        )
    where link.user_id = owner_id
      and link.id = canonical_link.id
    returning * into canonical_link;
  end if;

  -- Preserve Activity learning as a separate record. The task link does not
  -- use this rule as its display identity.
  if exists (
    select 1
    from public.application_rules as rule
    where rule.user_id = owner_id
      and rule.application_id = canonical_application.id
      and rule.scope_type = 'task'
      and rule.scope_id = p_task_occurrence_id
      and rule.deleted_at is null
  ) then
    update public.application_rules as rule
    set classification = 'direct_task_work',
        target_type = 'task_occurrence',
        target_id = p_task_occurrence_id,
        contribution_type = 'active_work_seconds',
        automatic_credit = true,
        priority = greatest(rule.priority, 200),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = rule.data || pg_catalog.jsonb_build_object(
          'rule_origin', 'user_connected',
          'task_application_link_id', canonical_link.id
        )
    where rule.user_id = owner_id
      and rule.application_id = canonical_application.id
      and rule.scope_type = 'task'
      and rule.scope_id = p_task_occurrence_id
      and rule.deleted_at is null;
  else
    insert into public.application_rules (
      id,
      user_id,
      application_id,
      scope_type,
      scope_id,
      classification,
      target_type,
      target_id,
      contribution_type,
      automatic_credit,
      priority,
      created_by_device_id,
      updated_by_device_id,
      last_command_id,
      data
    )
    values (
      pg_catalog.gen_random_uuid(),
      owner_id,
      canonical_application.id,
      'task',
      p_task_occurrence_id,
      'direct_task_work',
      'task_occurrence',
      p_task_occurrence_id,
      'active_work_seconds',
      true,
      200,
      p_device_id,
      p_device_id,
      p_command_id,
      pg_catalog.jsonb_build_object(
        'rule_origin', 'user_connected',
        'task_application_link_id', canonical_link.id
      )
    );
  end if;

  result_payload := pg_catalog.jsonb_build_object(
    'status', 'accepted',
    'entity_type', 'task_application_links',
    'entity_id', canonical_link.id,
    'link_id', canonical_link.id,
    'user_id', owner_id,
    'task_occurrence_id', canonical_link.task_occurrence_id,
    'application_id', canonical_application.id,
    'platform', canonical_application.platform,
    'raw_identifier', canonical_link.raw_identifier_snapshot,
    'normalized_key', canonical_application.normalized_application_key,
    'display_name', coalesce(
      override_name,
      nullif(pg_catalog.btrim(canonical_application.default_display_name), ''),
      nullif(pg_catalog.btrim(canonical_application.display_name), ''),
      nullif(pg_catalog.btrim(canonical_link.display_name_snapshot), ''),
      'Unknown application'
    ),
    'display_name_snapshot', canonical_link.display_name_snapshot,
    'icon_reference', coalesce(
      canonical_application.icon_reference,
      canonical_application.icon_path,
      canonical_link.icon_reference_snapshot
    ),
    'relationship_type', canonical_link.relationship_type,
    'revision', canonical_link.revision,
    'created_at', canonical_link.created_at,
    'updated_at', canonical_link.updated_at,
    'deleted_at', canonical_link.deleted_at
  );

  insert into public.processed_commands (
    user_id,
    command_id,
    device_id,
    device_sequence,
    entity_type,
    entity_id,
    command_type,
    base_revision,
    status,
    result,
    created_by_device_id,
    updated_by_device_id,
    last_command_id
  )
  values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'task_application_links',
    canonical_link.id,
    'create',
    0,
    'accepted',
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function public.connect_application_to_task(
  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text
) from public, anon;
grant execute on function public.connect_application_to_task(
  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text
) to authenticated;

create or replace function public.remove_application_from_task(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_link_id uuid,
  p_base_revision bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_result jsonb;
  canonical_link public.task_application_links%rowtype;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null or p_device_id is null or p_link_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_device_sequence < 1 then
    raise exception 'invalid_device_sequence' using errcode = '23514';
  end if;
  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':command:' || p_command_id::text,
      0
    )
  );

  select command.result
  into existing_result
  from public.processed_commands as command
  where command.user_id = owner_id
    and command.command_id = p_command_id;
  if found then
    return existing_result;
  end if;

  select link.*
  into canonical_link
  from public.task_application_links as link
  where link.user_id = owner_id
    and link.id = p_link_id
  for update;

  if found and canonical_link.deleted_at is null then
    update public.task_application_links as link
    set deleted_at = pg_catalog.statement_timestamp(),
        status = 'removed',
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where link.user_id = owner_id
      and link.id = p_link_id
    returning * into canonical_link;
  end if;

  result_payload := pg_catalog.jsonb_build_object(
    'status', 'accepted',
    'entity_type', 'task_application_links',
    'entity_id', p_link_id,
    'link_id', p_link_id,
    'revision', coalesce(canonical_link.revision, p_base_revision, 0),
    'deleted', true,
    'deleted_at', coalesce(
      canonical_link.deleted_at,
      pg_catalog.statement_timestamp()
    )
  );

  insert into public.processed_commands (
    user_id,
    command_id,
    device_id,
    device_sequence,
    entity_type,
    entity_id,
    command_type,
    base_revision,
    status,
    result,
    created_by_device_id,
    updated_by_device_id,
    last_command_id
  )
  values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'task_application_links',
    p_link_id,
    'delete',
    p_base_revision,
    'accepted',
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function public.remove_application_from_task(
  uuid, uuid, bigint, uuid, bigint
) from public, anon;
grant execute on function public.remove_application_from_task(
  uuid, uuid, bigint, uuid, bigint
) to authenticated;

comment on table public.task_application_links is
  'User-owned normalized task connections. Display snapshots keep every link renderable without a metadata request.';
comment on table public.user_application_overrides is
  'Private per-user names and classifications for canonical application identities.';
comment on function public.connect_application_to_task is
  'Atomic idempotent application identity, task link, and Activity-rule connection.';
comment on function public.remove_application_from_task is
  'Idempotent task-link tombstone operation that preserves application identities and Activity history.';
