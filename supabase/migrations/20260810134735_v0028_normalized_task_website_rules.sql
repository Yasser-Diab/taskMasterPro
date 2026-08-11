-- TaskMaster Pro v0.0.28: canonical, idempotent task website relationships.
--
-- A website relationship is a user-visible, many-to-many rule, not a device
-- observation.  Its semantic identity therefore belongs to the database:
-- (account, task, scope, canonical URL pattern).  Do not trust a client
-- connection key, cached host, or random row ID for that identity.

create or replace function private.normalize_task_website_host(p_value text)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  normalized text := pg_catalog.lower(pg_catalog.btrim(p_value));
begin
  normalized := pg_catalog.regexp_replace(
    normalized,
    '^[a-z][a-z0-9+.-]*://',
    ''
  );
  normalized := pg_catalog.regexp_replace(normalized, '^[^/?#]*@', '');
  normalized := pg_catalog.regexp_replace(normalized, '[/#?].*$', '');
  normalized := pg_catalog.regexp_replace(normalized, ':[0-9]+$', '');
  normalized := pg_catalog.regexp_replace(normalized, '^www[.]', '');
  normalized := pg_catalog.regexp_replace(normalized, '[.]+$', '');

  if normalized = '' or normalized !~ (
    '^(localhost|[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:[.]'
    '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)$'
  ) then
    return null;
  end if;
  return normalized;
end;
$$;

create or replace function private.task_website_registrable_domain(p_host text)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  parts text[] := pg_catalog.string_to_array(p_host, '.');
  part_count integer := coalesce(pg_catalog.array_length(parts, 1), 0);
  suffix text;
begin
  if part_count < 3 then
    return p_host;
  end if;

  suffix := parts[part_count - 1] || '.' || parts[part_count];
  if suffix in (
    'ac.uk', 'co.uk', 'gov.uk', 'ltd.uk', 'me.uk', 'net.uk', 'org.uk',
    'plc.uk', 'sch.uk', 'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
    'co.nz', 'org.nz', 'net.nz', 'co.jp', 'ne.jp', 'or.jp', 'com.br',
    'com.mx', 'com.tr', 'co.in', 'firm.in', 'net.in', 'org.in'
  ) then
    return parts[part_count - 2] || '.' || suffix;
  end if;
  return suffix;
end;
$$;

create or replace function private.normalize_task_website_path(p_value text)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  path_component text;
  parts text[] := array[]::text[];
  part_count integer;
begin
  foreach path_component in array pg_catalog.string_to_array(p_value, '/') loop
    if path_component = '' or path_component = '.' then
      continue;
    end if;
    if path_component = '..' then
      part_count := coalesce(pg_catalog.array_length(parts, 1), 0);
      if part_count > 0 then
        parts := parts[1:part_count - 1];
      end if;
      continue;
    end if;
    if pg_catalog.strpos(path_component, '*') > 0 then
      return null;
    end if;
    parts := pg_catalog.array_append(parts, path_component);
  end loop;

  if coalesce(pg_catalog.array_length(parts, 1), 0) = 0 then
    return '/';
  end if;
  return '/' || pg_catalog.array_to_string(parts, '/');
end;
$$;

create or replace function private.normalize_task_website_query(p_value text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select coalesce(
    pg_catalog.string_agg(part, '&' order by part),
    ''
  )
  from (
    select pg_catalog.btrim(item.value) as part
    from pg_catalog.regexp_split_to_table(p_value, '&') as item(value)
    where pg_catalog.btrim(item.value) <> ''
      and pg_catalog.lower(
        pg_catalog.split_part(pg_catalog.btrim(item.value), '=', 1)
      ) !~ '^utm_'
      and pg_catalog.lower(
        pg_catalog.split_part(pg_catalog.btrim(item.value), '=', 1)
      ) not in (
        'gclid', 'dclid', 'fbclid', 'msclkid', 'mc_cid', 'mc_eid',
        '_hsenc', '_hsmi'
      )
  ) as retained
$$;

-- Returns only server-derived canonical values.  The client can provide an
-- address and an explicit scope, but never the semantic key, host aliases,
-- registrable domain, or normalized path used to enforce uniqueness.
create or replace function private.canonical_task_website_rule(
  p_domain text,
  p_url_pattern text,
  p_match_scope text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  requested_host text := private.normalize_task_website_host(p_domain);
  normalized_scope text := case pg_catalog.lower(
    pg_catalog.btrim(coalesce(p_match_scope, ''))
  )
    when 'page' then 'page'
    when 'section' then 'section'
    when 'host' then 'host'
    when 'site' then 'site'
    else null
  end;
  raw_pattern text := pg_catalog.btrim(coalesce(p_url_pattern, ''));
  raw_without_scheme text;
  remainder text;
  fragmentless text;
  raw_path text;
  raw_query text;
  pattern_host text;
  expected_host text;
  registrable_domain text;
  normalized_path text;
  section_path text;
  canonical_url text;
  canonical_pattern text;
begin
  if requested_host is null or normalized_scope is null then
    return null;
  end if;
  registrable_domain := private.task_website_registrable_domain(requested_host);
  expected_host := case
    when normalized_scope = 'site' then registrable_domain
    else requested_host
  end;

  if raw_pattern = '' then
    if normalized_scope in ('host', 'site') then
      raw_pattern := expected_host || '/*';
    else
      return null;
    end if;
  end if;
  pattern_host := private.normalize_task_website_host(raw_pattern);
  if pattern_host is null or pattern_host <> expected_host then
    return null;
  end if;

  raw_without_scheme := pg_catalog.regexp_replace(
    pg_catalog.lower(raw_pattern),
    '^[a-z][a-z0-9+.-]*://',
    ''
  );
  remainder := pg_catalog.regexp_replace(raw_without_scheme, '^[^/?#]*', '');
  fragmentless := pg_catalog.split_part(remainder, '#', 1);
  raw_path := pg_catalog.split_part(fragmentless, '?', 1);
  raw_query := case
    when pg_catalog.strpos(fragmentless, '?') > 0
      then pg_catalog.split_part(fragmentless, '?', 2)
    else ''
  end;

  if normalized_scope in ('host', 'site') then
    normalized_path := '/';
    section_path := '/';
    canonical_url := expected_host || '/';
    canonical_pattern := expected_host || '/*';
  elsif normalized_scope = 'section' then
    if pg_catalog.strpos(raw_path, '*') > 0 then
      if pg_catalog.right(raw_path, 2) <> '/*' or
          pg_catalog.strpos(
            pg_catalog.left(raw_path, pg_catalog.length(raw_path) - 1),
            '*'
          ) > 0 then
        return null;
      end if;
      raw_path := pg_catalog.left(raw_path, pg_catalog.length(raw_path) - 2);
    end if;
    normalized_path := private.normalize_task_website_path(raw_path);
    if normalized_path is null then
      return null;
    end if;
    section_path := normalized_path;
    canonical_url := expected_host || normalized_path;
    canonical_pattern := expected_host || section_path || '/*';
  else
    if pg_catalog.strpos(raw_path, '*') > 0 then
      return null;
    end if;
    normalized_path := private.normalize_task_website_path(raw_path);
    if normalized_path is null then
      return null;
    end if;
    raw_query := private.normalize_task_website_query(raw_query);
    section_path := case
      when normalized_path = '/' then '/'
      else coalesce(
        nullif(
          pg_catalog.regexp_replace(normalized_path, '/[^/]+$', ''),
          ''
        ),
        '/'
      )
    end;
    canonical_url := expected_host || normalized_path ||
      case when raw_query = '' then '' else '?' || raw_query end;
    canonical_pattern := canonical_url;
  end if;

  return pg_catalog.jsonb_build_object(
    'domain', expected_host,
    'url_pattern', canonical_pattern,
    'connection_key', normalized_scope || ':' || canonical_pattern,
    'match_scope', normalized_scope,
    'host', expected_host,
    'registrable_domain', registrable_domain,
    'normalized_path', normalized_path,
    'section_path', section_path,
    'canonical_url', canonical_url,
    'normalization_version', 1
  );
end;
$$;

revoke all on function private.normalize_task_website_host(text)
  from public, anon, authenticated;
revoke all on function private.task_website_registrable_domain(text)
  from public, anon, authenticated;
revoke all on function private.normalize_task_website_path(text)
  from public, anon, authenticated;
revoke all on function private.normalize_task_website_query(text)
  from public, anon, authenticated;
revoke all on function private.canonical_task_website_rule(text, text, text)
  from public, anon, authenticated;

-- Migrate valid legacy task rules to canonical keys first. Invalid legacy
-- rows remain visible for the user to review rather than being guessed into a
-- broader site relationship.
with normalized as (
  select
    rule.id,
    private.canonical_task_website_rule(
      rule.domain,
      rule.url_pattern,
      coalesce(rule.data ->> 'match_scope', 'host')
    ) as canonical
  from public.website_rules as rule
  where rule.scope_type = 'task'
    and rule.scope_id is not null
    and rule.deleted_at is null
)
update public.website_rules as rule
set domain = normalized.canonical ->> 'domain',
    url_pattern = normalized.canonical ->> 'url_pattern',
    data = coalesce(rule.data, '{}'::jsonb) ||
      (normalized.canonical - 'domain' - 'url_pattern')
from normalized
where rule.id = normalized.id
  and normalized.canonical is not null;

-- The same relationship may have been created offline on two old devices.
-- Keep the earliest row canonical and soft-delete only semantic duplicates.
with ranked as (
  select
    rule.id,
    first_value(rule.id) over (
      partition by rule.user_id, rule.scope_id, rule.data ->> 'connection_key'
      order by rule.created_at, rule.id
    ) as canonical_id,
    row_number() over (
      partition by rule.user_id, rule.scope_id, rule.data ->> 'connection_key'
      order by rule.created_at, rule.id
    ) as duplicate_rank
  from public.website_rules as rule
  where rule.scope_type = 'task'
    and rule.scope_id is not null
    and rule.deleted_at is null
    and rule.data ? 'connection_key'
)
update public.website_rules as rule
set deleted_at = pg_catalog.statement_timestamp(),
    data = coalesce(rule.data, '{}'::jsonb) ||
      pg_catalog.jsonb_build_object(
        'superseded_by_rule_id', ranked.canonical_id,
        'superseded_reason', 'duplicate_canonical_task_website_rule'
      )
from ranked
where rule.id = ranked.id
  and ranked.duplicate_rank > 1;

create unique index if not exists website_rules_active_task_connection_key_unique
  on public.website_rules (
    user_id,
    scope_id,
    (data ->> 'connection_key')
  )
  where scope_type = 'task'
    and scope_id is not null
    and deleted_at is null
    and data ? 'connection_key';

-- Generic/legacy writes are normalized too, so an old client cannot create a
-- second live semantic rule simply by omitting its local connection key.
create or replace function private.enforce_task_website_rule_v0028()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  canonical jsonb;
begin
  if new.scope_type is distinct from 'task' or new.deleted_at is not null then
    return new;
  end if;
  if new.scope_id is null then
    raise exception 'task_website_scope_required' using errcode = '23502';
  end if;
  if not exists (
    select 1
    from public.task_occurrences as task
    where task.user_id = new.user_id
      and task.id = new.scope_id
      and task.deleted_at is null
  ) then
    raise exception 'task_website_scope_not_available' using errcode = '23503';
  end if;

  canonical := private.canonical_task_website_rule(
    new.domain,
    new.url_pattern,
    coalesce(new.data ->> 'match_scope', 'host')
  );
  if canonical is null then
    raise exception 'invalid_task_website_rule' using errcode = '23514';
  end if;

  new.domain := canonical ->> 'domain';
  new.url_pattern := canonical ->> 'url_pattern';
  new.classification := 'direct_task_work';
  new.target_type := 'task_occurrence';
  new.target_id := new.scope_id;
  new.contribution_type := 'active_work_seconds';
  new.automatic_credit := true;
  new.priority := greatest(coalesce(new.priority, 0), 200);
  new.data := coalesce(new.data, '{}'::jsonb) ||
    (canonical - 'domain' - 'url_pattern');
  return new;
end;
$$;

drop trigger if exists aaa_enforce_task_website_rule_v0028
  on public.website_rules;
create trigger aaa_enforce_task_website_rule_v0028
before insert or update on public.website_rules
for each row execute function private.enforce_task_website_rule_v0028();

revoke all on function private.enforce_task_website_rule_v0028()
  from public, anon, authenticated;

create or replace function public.connect_website_to_task(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_rule_id uuid,
  p_task_occurrence_id uuid,
  p_base_revision bigint,
  p_domain text,
  p_url_pattern text,
  p_match_scope text,
  p_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
-- The endpoint needs a privileged lock/read to atomically converge two
-- devices. It remains narrowly owner-scoped and every caller-controlled
-- identity is validated before that privilege is used.
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_result jsonb;
  canonical_input jsonb;
  connection_key text;
  canonical_rule public.website_rules%rowtype;
  supplied_rule public.website_rules%rowtype;
  supplied_rule_found boolean := false;
  supplied_canonical jsonb;
  result_payload jsonb;
  stale_restore boolean := false;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;

  -- A command ID is immutable evidence of an already-accepted operation.
  -- Consult it before mutable device/task checks, otherwise a lost-response
  -- retry can look like a new failure after another device changes the task.
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

  if p_device_id is null
     or p_rule_id is null
     or p_task_occurrence_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_base_revision is null or p_base_revision < 0 or
      coalesce(p_device_sequence, 0) < 1 then
    raise exception 'invalid_command_payload' using errcode = '23514';
  end if;
  if not exists (
    select 1
    from public.account_devices as device
    where device.user_id = owner_id
      and device.id = p_device_id
      and device.revoked_at is null
      and device.deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
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

  -- p_data is deliberately not used for canonical identity. It is retained
  -- in the signature only for older clients and the generic command adapter.
  canonical_input := private.canonical_task_website_rule(
    p_domain,
    p_url_pattern,
    p_match_scope
  );
  if canonical_input is null then
    raise exception 'invalid_task_website_rule' using errcode = '23514';
  end if;
  connection_key := canonical_input ->> 'connection_key';

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':task-website:' || p_task_occurrence_id::text || ':' ||
      connection_key,
      0
    )
  );

  -- Validate an already allocated client rule ID before accepting a semantic
  -- duplicate.  Otherwise a stale device could accidentally alias a rule that
  -- belongs to a different task/site merely because this task already has the
  -- requested semantic relationship.
  select rule.*
  into supplied_rule
  from public.website_rules as rule
  where rule.user_id = owner_id
    and rule.id = p_rule_id
  for update;
  supplied_rule_found := found;

  if supplied_rule_found then
    supplied_canonical := case
      when supplied_rule.scope_type = 'task' then
        private.canonical_task_website_rule(
          supplied_rule.domain,
          supplied_rule.url_pattern,
          coalesce(
            supplied_rule.data ->> 'match_scope',
            'host'
          )
        )
      else null
    end;
    if supplied_rule.scope_id is distinct from p_task_occurrence_id or
        supplied_canonical is null or
        supplied_canonical ->> 'connection_key' <> connection_key then
      raise exception 'rule_id_bound_to_other_relationship'
        using errcode = '23505';
    end if;
  end if;

  select rule.*
  into canonical_rule
  from public.website_rules as rule
  where rule.user_id = owner_id
    and rule.scope_type = 'task'
    and rule.scope_id = p_task_occurrence_id
    and rule.deleted_at is null
    and rule.data ->> 'connection_key' = connection_key
  order by rule.created_at, rule.id
  limit 1
  for update;

  if not found then
    if supplied_rule_found then
      if supplied_rule.deleted_at is null then
        canonical_rule := supplied_rule;
      elsif p_base_revision <> supplied_rule.revision then
        canonical_rule := supplied_rule;
        stale_restore := true;
      else
        -- The generic tombstone guard only permits an explicit, server-side
        -- restore.  Keep this transaction-local so no unrelated command can
        -- inherit the restore capability.
        perform pg_catalog.set_config(
          'taskmaster.allow_tombstone_restore',
          'on',
          true
        );
        update public.website_rules as rule
        set domain = canonical_input ->> 'domain',
            url_pattern = canonical_input ->> 'url_pattern',
            scope_type = 'task',
            scope_id = p_task_occurrence_id,
            classification = 'direct_task_work',
            target_type = 'task_occurrence',
            target_id = p_task_occurrence_id,
            contribution_type = 'active_work_seconds',
            automatic_credit = true,
            priority = greatest(rule.priority, 200),
            deleted_at = null,
            data = coalesce(rule.data, '{}'::jsonb) ||
              (canonical_input - 'domain' - 'url_pattern'),
            updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where rule.user_id = owner_id
          and rule.id = p_rule_id
        returning * into canonical_rule;
      end if;
    else
      if p_base_revision <> 0 then
        raise exception 'missing_website_rule_for_revision'
          using errcode = '23503';
      end if;
      insert into public.website_rules (
        id,
        user_id,
        domain,
        url_pattern,
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
        p_rule_id,
        owner_id,
        canonical_input ->> 'domain',
        canonical_input ->> 'url_pattern',
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
        canonical_input - 'domain' - 'url_pattern'
      )
      returning * into canonical_rule;
    end if;
  end if;

  result_payload := pg_catalog.jsonb_build_object(
    'status', 'accepted',
    'canonical_only', stale_restore or canonical_rule.id <> p_rule_id,
    'superseded', stale_restore,
    'reason', case when stale_restore then 'stale_rule_revision' else null end,
    'entity_type', 'website_rules',
    'entity_id', canonical_rule.id,
    'rule_id', canonical_rule.id,
    'user_id', owner_id,
    'domain', canonical_rule.domain,
    'url_pattern', canonical_rule.url_pattern,
    'scope_type', canonical_rule.scope_type,
    'scope_id', canonical_rule.scope_id,
    'classification', canonical_rule.classification,
    'target_type', canonical_rule.target_type,
    'target_id', canonical_rule.target_id,
    'contribution_type', canonical_rule.contribution_type,
    'automatic_credit', canonical_rule.automatic_credit,
    'priority', canonical_rule.priority,
    'revision', canonical_rule.revision,
    'created_at', canonical_rule.created_at,
    'updated_at', canonical_rule.updated_at,
    'deleted_at', canonical_rule.deleted_at,
    'data', canonical_rule.data
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
    'website_rules',
    canonical_rule.id,
    'connect',
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

revoke all on function public.connect_website_to_task(
  uuid, uuid, bigint, uuid, uuid, bigint, text, text, text, jsonb
) from public, anon;
grant execute on function public.connect_website_to_task(
  uuid, uuid, bigint, uuid, uuid, bigint, text, text, text, jsonb
) to authenticated;

comment on function public.connect_website_to_task(
  uuid, uuid, bigint, uuid, uuid, bigint, text, text, text, jsonb
) is
  'Atomic owner-scoped task website connection. Canonical key and scope are server-derived; stale restores return the current canonical row without mutation.';
