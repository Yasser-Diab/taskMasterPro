-- LEGACY LEARNING PROJECT ONLY: iejbogkqknldxoyepvun
-- Never apply this migration to the account-data project tmvarulrujkmibqpqoeo.
--
-- The service stores no account, email, task, title, URL, process path, device,
-- or activity/session data. Application identifiers and per-install vote tokens
-- are hashed on-device. A vote token is derived separately for every app, so it
-- cannot be used to link an installation's votes across applications.

create schema if not exists learning;

revoke all on schema learning from public, anon, authenticated;

create table if not exists learning.application_system_votes (
  platform text not null
    check (platform in ('android', 'windows')),
  app_key_hash text not null
    check (app_key_hash ~ '^[0-9a-f]{64}$'),
  voter_token_hash text not null
    check (voter_token_hash ~ '^[0-9a-f]{64}$'),
  is_system_activity boolean not null,
  primary key (platform, app_key_hash, voter_token_hash)
);

create table if not exists learning.application_system_aggregates (
  platform text not null
    check (platform in ('android', 'windows')),
  app_key_hash text not null
    check (app_key_hash ~ '^[0-9a-f]{64}$'),
  system_votes integer not null check (system_votes >= 0),
  not_system_votes integer not null check (not_system_votes >= 0),
  sample_size integer not null check (
    sample_size = system_votes + not_system_votes
  ),
  updated_at timestamptz not null default now(),
  primary key (platform, app_key_hash)
);

revoke all on all tables in schema learning from public, anon, authenticated;

create or replace function learning.wilson_lower_bound(
  positive_votes integer,
  total_votes integer
) returns double precision
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select case
    when total_votes <= 0 then 0::double precision
    else (
      (positive_votes::double precision / total_votes) +
      (3.8416 / (2 * total_votes)) -
      (1.96 * sqrt(
        (
          (positive_votes::double precision / total_votes) *
          (1 - (positive_votes::double precision / total_votes)) +
          (3.8416 / (4 * total_votes))
        ) / total_votes
      ))
    ) / (1 + (3.8416 / total_votes))
  end
$$;

revoke all on function learning.wilson_lower_bound(integer, integer)
  from public, anon, authenticated;

create or replace function public.submit_application_system_vote(
  p_platform text,
  p_app_key_hash text,
  p_voter_token_hash text,
  p_is_system_activity boolean
) returns void
language plpgsql
security definer
set search_path = pg_catalog, learning
as $$
declare
  normalized_platform text := lower(trim(p_platform));
  normalized_app_hash text := lower(trim(p_app_key_hash));
  normalized_vote_hash text := lower(trim(p_voter_token_hash));
  system_count integer;
  not_system_count integer;
begin
  if normalized_platform not in ('android', 'windows') then
    raise exception using errcode = '22023', message = 'Unsupported platform';
  end if;
  if normalized_app_hash !~ '^[0-9a-f]{64}$' or
      normalized_vote_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid anonymous vote';
  end if;

  -- Serialize only this anonymous application bucket. This prevents concurrent
  -- submissions from publishing stale counters without creating a user key.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      normalized_platform || ':' || normalized_app_hash,
      0
    )
  );

  insert into learning.application_system_votes (
    platform,
    app_key_hash,
    voter_token_hash,
    is_system_activity
  ) values (
    normalized_platform,
    normalized_app_hash,
    normalized_vote_hash,
    p_is_system_activity
  )
  on conflict (platform, app_key_hash, voter_token_hash)
  do update set is_system_activity = excluded.is_system_activity;

  select
    count(*) filter (where is_system_activity),
    count(*) filter (where not is_system_activity)
  into system_count, not_system_count
  from learning.application_system_votes
  where platform = normalized_platform
    and app_key_hash = normalized_app_hash;

  insert into learning.application_system_aggregates (
    platform,
    app_key_hash,
    system_votes,
    not_system_votes,
    sample_size,
    updated_at
  ) values (
    normalized_platform,
    normalized_app_hash,
    system_count,
    not_system_count,
    system_count + not_system_count,
    now()
  )
  on conflict (platform, app_key_hash)
  do update set
    system_votes = excluded.system_votes,
    not_system_votes = excluded.not_system_votes,
    sample_size = excluded.sample_size,
    updated_at = excluded.updated_at;
end
$$;

revoke all on function public.submit_application_system_vote(
  text, text, text, boolean
) from public;
grant execute on function public.submit_application_system_vote(
  text, text, text, boolean
) to anon, authenticated;

create or replace function public.get_application_system_consensus(
  p_platform text,
  p_app_key_hash text
) returns table (
  sample_size integer,
  system_share double precision,
  confidence_lower_bound double precision,
  suggests_system_activity boolean
)
language sql
stable
security definer
set search_path = pg_catalog, learning
as $$
  select
    aggregate.sample_size,
    aggregate.system_votes::double precision / aggregate.sample_size,
    learning.wilson_lower_bound(
      aggregate.system_votes,
      aggregate.sample_size
    ),
    (
      aggregate.sample_size >= 20 and
      aggregate.system_votes::double precision / aggregate.sample_size >= 0.80 and
      learning.wilson_lower_bound(
        aggregate.system_votes,
        aggregate.sample_size
      ) >= 0.65
    )
  from learning.application_system_aggregates as aggregate
  where aggregate.platform = lower(trim(p_platform))
    and aggregate.app_key_hash = lower(trim(p_app_key_hash))
    and aggregate.sample_size >= 20
    and lower(trim(p_platform)) in ('android', 'windows')
    and lower(trim(p_app_key_hash)) ~ '^[0-9a-f]{64}$'
$$;

revoke all on function public.get_application_system_consensus(text, text)
  from public;
grant execute on function public.get_application_system_consensus(text, text)
  to anon, authenticated;

comment on function public.get_application_system_consensus(text, text) is
  'Returns anonymous aggregate evidence only after a 20-install threshold. Clients must never override a local user choice.';
