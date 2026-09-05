-- DayVector 0.0.30: a complete, privacy-safe application category taxonomy.
--
-- Category is intentionally distinct from task credit. Only a SHA-256 app
-- identifier, an app-scoped anonymous ballot, the chosen category, and the
-- user's general usefulness decision can reach this aggregate-only service.

alter table learning.application_category_votes
  drop constraint if exists application_category_votes_category_check;

alter table learning.application_category_votes
  add constraint application_category_votes_category_check check (category in (
    'business', 'productivity', 'development', 'research', 'communication',
    'education', 'writing', 'design', 'finance', 'health_fitness', 'medical',
    'utilities', 'travel_navigation', 'shopping', 'food_drink',
    'home_lifestyle', 'automotive', 'weather', 'music_audio', 'system',
    'entertainment', 'video_streaming', 'games', 'social', 'news_media',
    'sports', 'photography', 'books_reference', 'other'
  ));

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
        'business', 'productivity', 'development', 'research', 'communication',
        'education', 'writing', 'design', 'finance', 'health_fitness', 'medical',
        'utilities', 'travel_navigation', 'shopping', 'food_drink',
        'home_lifestyle', 'automotive', 'weather', 'music_audio', 'system',
        'entertainment', 'video_streaming', 'games', 'social', 'news_media',
        'sports', 'photography', 'books_reference', 'other'
      ) then
    raise exception using errcode = '22023', message = 'Unsupported application category';
  end if;
  if normalized_app_hash !~ '^[0-9a-f]{64}$' or
      normalized_vote_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid anonymous vote';
  end if;

  -- Serialize only this anonymous bucket so a revised personal category
  -- cannot leave an aggregate built from a stale concurrent vote.
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
