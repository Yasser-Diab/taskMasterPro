-- TaskMaster Pro v0.0.30: allow an explicitly entered, privacy-safe break
-- check-in to synchronize even when detailed device Activity remains local.
-- Manual entries contain no process, window, domain, URL or page-title data.

create or replace function public.enforce_activity_privacy_v0028()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  storage_mode text;
  detailed_opt_in boolean;
  approved_safe_contribution boolean;
  manual_safe_break boolean;
  safe_review_metadata boolean;
begin
  if tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null then
    if tg_table_name = 'activity_segments' then
      new.id := old.id;
      new.user_id := old.user_id;
      new.device_id := old.device_id;
      new.device_event_id := old.device_event_id;
      new.started_at := old.started_at;
      new.ended_at := old.ended_at;
      new.source_type := old.source_type;
      new.application_id := old.application_id;
      new.website_rule_id := old.website_rule_id;
      new.resource_id := old.resource_id;
      new.process_name := old.process_name;
      new.window_title := old.window_title;
      new.domain := old.domain;
      new.url := old.url;
      new.page_title := old.page_title;
      new.input_state := old.input_state;
      new.idle_state := old.idle_state;
      new.screen_state := old.screen_state;
      new.capture_confidence := old.capture_confidence;
      new.raw_metadata := old.raw_metadata;
      new.data := old.data;
    elsif tg_table_name = 'activity_review_queue' then
      new.id := old.id;
      new.user_id := old.user_id;
      new.activity_segment_id := old.activity_segment_id;
      new.review_reason := old.review_reason;
      new.priority := old.priority;
      new.suggested_targets := old.suggested_targets;
      new.suggested_classification := old.suggested_classification;
      new.confidence := old.confidence;
      new.status := old.status;
      new.reviewed_at := old.reviewed_at;
      new.data := old.data;
    end if;
    return new;
  end if;

  select
    settings.activity_storage,
    coalesce(
      settings.data @> '{"detailed_activity_sync_opt_in": true}'::jsonb,
      false
    )
  into storage_mode, detailed_opt_in
  from public.privacy_settings as settings
  where settings.user_id = new.user_id
    and settings.deleted_at is null;

  storage_mode := coalesce(storage_mode, 'local_only');
  detailed_opt_in := coalesce(detailed_opt_in, false);

  if tg_table_name = 'activity_segments' then
    approved_safe_contribution :=
      coalesce(new.data, '{}'::jsonb)
        @> '{"approved_contribution": true}'::jsonb
      and new.process_name is null
      and new.window_title is null
      and new.domain is null
      and new.url is null
      and new.page_title is null
      and coalesce(new.raw_metadata, '{}'::jsonb)
        @> '{"normalized": true, "raw_samples_included": false}'::jsonb
      and not exists (
        select 1
        from pg_catalog.jsonb_object_keys(
          coalesce(new.raw_metadata, '{}'::jsonb)
        ) as metadata_key
        where metadata_key not in (
          'normalized',
          'raw_samples_included',
          'source_task_id',
          'source_session_id',
          'source_runtime_state'
        )
      );

    manual_safe_break :=
      new.source_type = 'manual_break'
      and new.process_name is null
      and new.window_title is null
      and new.domain is null
      and new.url is null
      and new.page_title is null
      and coalesce(new.raw_metadata, '{}'::jsonb)
        @> '{"normalized": true, "raw_samples_included": false, "manual_break_check_in": true}'::jsonb
      and new.raw_metadata ->> 'manual_break_category' in (
        'break_activity_reading',
        'break_activity_sport',
        'break_activity_relaxing',
        'break_activity_drink',
        'break_activity_other'
      )
      and pg_catalog.length(
        coalesce(new.raw_metadata ->> 'manual_break_label', '')
      ) <= 120
      and not exists (
        select 1
        from pg_catalog.jsonb_object_keys(
          coalesce(new.raw_metadata, '{}'::jsonb)
        ) as metadata_key
        where metadata_key not in (
          'normalized',
          'raw_samples_included',
          'source_task_id',
          'source_session_id',
          'source_runtime_state',
          'manual_break_check_in',
          'manual_break_category',
          'manual_break_label'
        )
      )
      and not exists (
        select 1
        from pg_catalog.jsonb_object_keys(coalesce(new.data, '{}'::jsonb))
          as data_key
        where data_key not in (
          'normalization_version',
          'capture_state',
          'approved_contribution',
          'detail_level'
        )
      );

    if approved_safe_contribution
       or manual_safe_break
       or (storage_mode = 'synchronized' and detailed_opt_in) then
      return new;
    end if;

    raise exception 'activity_privacy_local_only' using errcode = '42501';
  end if;

  if tg_table_name = 'activity_review_queue' then
    if storage_mode = 'synchronized' and detailed_opt_in then
      return new;
    end if;

    safe_review_metadata := not exists (
      select 1
      from pg_catalog.jsonb_object_keys(coalesce(new.data, '{}'::jsonb))
        as review_key
      where review_key not in (
        'capture_state',
        'classification',
        'target_task_id',
        'contribution_type',
        'attribution_id',
        'contribution_id',
        'application_rule_id',
        'classification_command_id',
        'merged_from_revision',
        'reclassified_from_revision',
        'resolved_with_review_item_id'
      )
    )
      and (
        not coalesce(new.data, '{}'::jsonb) ? 'capture_state'
        or new.data ->> 'capture_state' = 'finalized'
      );

    if exists (
      select 1
      from public.activity_segments as segment
      where segment.user_id = new.user_id
        and segment.id = new.activity_segment_id
        and segment.deleted_at is null
        and segment.process_name is null
        and segment.window_title is null
        and segment.domain is null
        and segment.url is null
        and segment.page_title is null
        and coalesce(segment.raw_metadata, '{}'::jsonb)
          @> '{"normalized": true, "raw_samples_included": false}'::jsonb
        and (
          (
            coalesce(segment.data, '{}'::jsonb)
              @> '{"approved_contribution": true}'::jsonb
            and not exists (
              select 1
              from pg_catalog.jsonb_object_keys(
                coalesce(segment.raw_metadata, '{}'::jsonb)
              ) as metadata_key
              where metadata_key not in (
                'normalized',
                'raw_samples_included',
                'source_task_id',
                'source_session_id',
                'source_runtime_state'
              )
            )
          )
          or (
            segment.source_type = 'manual_break'
            and coalesce(segment.raw_metadata, '{}'::jsonb)
              @> '{"manual_break_check_in": true}'::jsonb
            and segment.raw_metadata ->> 'manual_break_category' in (
              'break_activity_reading',
              'break_activity_sport',
              'break_activity_relaxing',
              'break_activity_drink',
              'break_activity_other'
            )
            and pg_catalog.length(
              coalesce(segment.raw_metadata ->> 'manual_break_label', '')
            ) <= 120
            and not exists (
              select 1
              from pg_catalog.jsonb_object_keys(
                coalesce(segment.raw_metadata, '{}'::jsonb)
              ) as metadata_key
              where metadata_key not in (
                'normalized',
                'raw_samples_included',
                'source_task_id',
                'source_session_id',
                'source_runtime_state',
                'manual_break_check_in',
                'manual_break_category',
                'manual_break_label'
              )
            )
          )
        )
    )
       and coalesce(new.suggested_targets, '[]'::jsonb) = '[]'::jsonb
       and safe_review_metadata then
      return new;
    end if;

    raise exception 'activity_privacy_local_only' using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_activity_privacy_v0028() from public;

comment on function public.enforce_activity_privacy_v0028() is
  'Blocks raw Activity transport without consent; permits normalized approved contributions and explicitly entered privacy-safe manual break check-ins.';
