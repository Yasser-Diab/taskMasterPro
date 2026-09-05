-- DayVector 0.0.30: opt-in, aggregate-only application categorization.
--
-- This belongs to the active DayVector project (tmvarulrujkmibqpqoeo), not
-- the retired learning project. The RPC boundary accepts only an on-device
-- SHA-256 application hash plus an app-scoped anonymous ballot hash. It never
-- receives auth IDs, emails, task data, titles, URLs, paths, or activity time.

create schema if not exists learning;

revoke all on schema learning from public, anon, authenticated;

create table if not exists learning.application_category_votes (
  platform text not null check (platform in ('android', 'windows')),
  app_key_hash text not null check (app_key_hash ~ '^[0-9a-f]{64}$'),
  voter_token_hash text not null check (voter_token_hash ~ '^[0-9a-f]{64}$'),
  category text not null check (category in (
    'productivity', 'development', 'research', 'communication', 'education',
    'design', 'finance', 'system', 'entertainment', 'social', 'other'
  )),
  is_useful boolean not null,
  primary key (platform, app_key_hash, voter_token_hash)
);

create table if not exists learning.application_category_aggregates (
  platform text not null check (platform in ('android', 'windows')),
  app_key_hash text not null check (app_key_hash ~ '^[0-9a-f]{64}$'),
  category_votes jsonb not null default '{}'::jsonb,
  useful_votes integer not null check (useful_votes >= 0),
  not_useful_votes integer not null check (not_useful_votes >= 0),
  sample_size integer not null check (sample_size = useful_votes + not_useful_votes),
  top_category text not null,
  top_category_is_useful boolean not null,
  top_pair_votes integer not null check (top_pair_votes >= 0),
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

create or replace function public.submit_application_category_vote(
  p_platform text,
  p_app_key_hash text,
  p_voter_token_hash text,
  p_category text,
  p_is_useful boolean
) returns void
language plpgsql
security definer
set search_path = pg_catalog, learning
as $$
declare
  normalized_platform text := lower(trim(p_platform));
  normalized_app_hash text := lower(trim(p_app_key_hash));
  normalized_vote_hash text := lower(trim(p_voter_token_hash));
  normalized_category text := lower(trim(p_category));
  useful_count integer;
  not_useful_count integer;
  total_count integer;
  pair_category text;
  pair_is_useful boolean;
  pair_count integer;
  category_counts jsonb;
begin
  if normalized_platform not in ('android', 'windows') or
      normalized_category not in (
        'productivity', 'development', 'research', 'communication', 'education',
        'design', 'finance', 'system', 'entertainment', 'social', 'other'
      ) then
    raise exception using errcode = '22023', message = 'Unsupported application category';
  end if;
  if normalized_app_hash !~ '^[0-9a-f]{64}$' or
      normalized_vote_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid anonymous vote';
  end if;

  -- Serialize only this anonymous bucket so concurrent correction votes never
  -- publish stale aggregate counts.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(normalized_platform || ':' || normalized_app_hash, 0)
  );

  insert into learning.application_category_votes (
    platform, app_key_hash, voter_token_hash, category, is_useful
  ) values (
    normalized_platform, normalized_app_hash, normalized_vote_hash,
    normalized_category, p_is_useful
  )
  on conflict (platform, app_key_hash, voter_token_hash)
  do update set category = excluded.category, is_useful = excluded.is_useful;

  select
    count(*) filter (where is_useful),
    count(*) filter (where not is_useful),
    count(*)
  into useful_count, not_useful_count, total_count
  from learning.application_category_votes
  where platform = normalized_platform and app_key_hash = normalized_app_hash;

  select pair.category, pair.is_useful, pair.vote_count
  into pair_category, pair_is_useful, pair_count
  from (
    select category, is_useful, count(*)::integer as vote_count
    from learning.application_category_votes
    where platform = normalized_platform and app_key_hash = normalized_app_hash
    group by category, is_useful
    order by vote_count desc, category asc, is_useful desc
    limit 1
  ) as pair;

  select coalesce(jsonb_object_agg(category, votes), '{}'::jsonb)
  into category_counts
  from (
    select category, count(*)::integer as votes
    from learning.application_category_votes
    where platform = normalized_platform and app_key_hash = normalized_app_hash
    group by category
  ) as grouped;

  insert into learning.application_category_aggregates (
    platform, app_key_hash, category_votes, useful_votes, not_useful_votes,
    sample_size, top_category, top_category_is_useful, top_pair_votes, updated_at
  ) values (
    normalized_platform, normalized_app_hash, category_counts, useful_count,
    not_useful_count, total_count, pair_category, pair_is_useful, pair_count, now()
  )
  on conflict (platform, app_key_hash)
  do update set
    category_votes = excluded.category_votes,
    useful_votes = excluded.useful_votes,
    not_useful_votes = excluded.not_useful_votes,
    sample_size = excluded.sample_size,
    top_category = excluded.top_category,
    top_category_is_useful = excluded.top_category_is_useful,
    top_pair_votes = excluded.top_pair_votes,
    updated_at = excluded.updated_at;
end
$$;

revoke all on function public.submit_application_category_vote(
  text, text, text, text, boolean
) from public;
grant execute on function public.submit_application_category_vote(
  text, text, text, text, boolean
) to anon, authenticated;

create or replace function public.get_application_category_consensus(
  p_platform text,
  p_app_key_hash text
) returns table (
  sample_size integer,
  category text,
  is_useful boolean,
  confidence_lower_bound double precision
)
language sql
stable
security definer
set search_path = pg_catalog, learning
as $$
  select
    aggregate.sample_size,
    aggregate.top_category,
    aggregate.top_category_is_useful,
    learning.wilson_lower_bound(aggregate.top_pair_votes, aggregate.sample_size)
  from learning.application_category_aggregates as aggregate
  where aggregate.platform = lower(trim(p_platform))
    and aggregate.app_key_hash = lower(trim(p_app_key_hash))
    and aggregate.sample_size >= 20
    and aggregate.top_pair_votes::double precision / aggregate.sample_size >= 0.80
    and learning.wilson_lower_bound(
      aggregate.top_pair_votes,
      aggregate.sample_size
    ) >= 0.65
    and lower(trim(p_platform)) in ('android', 'windows')
    and lower(trim(p_app_key_hash)) ~ '^[0-9a-f]{64}$'
$$;

revoke all on function public.get_application_category_consensus(text, text)
  from public;
grant execute on function public.get_application_category_consensus(text, text)
  to anon, authenticated;

comment on function public.get_application_category_consensus(text, text) is
  'Returns only conservative anonymous aggregate application category evidence. A client must never override a local user rule.';
