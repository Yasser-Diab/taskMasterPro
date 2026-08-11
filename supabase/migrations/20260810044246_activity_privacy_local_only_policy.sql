-- TaskMaster Pro v0.0.28: Activity observations are local by default.
--
-- `privacy_settings` is the canonical authority for whether raw device
-- Activity may leave a device. Old user_settings flags were able to override
-- it, producing both a privacy contradiction and a high-egress raw Activity
-- stream. Approved, privacy-safe task contributions remain synchronizable.
--
-- Do not erase another account's explicit detailed-history consent here.
-- Instead, repair only the derived legacy flag so it agrees with the already
-- canonical privacy row. Missing or malformed privacy rows fail closed.
update public.user_settings as preferences
set data = coalesce(preferences.data, '{}'::jsonb) ||
      pg_catalog.jsonb_build_object(
        'detailed_activity_sync_enabled',
        coalesce(
          privacy.activity_storage = 'synchronized'
          and privacy.data @> '{"detailed_activity_sync_opt_in": true}'::jsonb,
          false
        ),
        'activity_upload_policy',
        case
          when coalesce(
            privacy.activity_storage = 'synchronized'
            and privacy.data @> '{"detailed_activity_sync_opt_in": true}'::jsonb,
            false
          ) then 'explicit_detailed_history'
          else 'approved_contributions_only'
        end
      ),
    updated_by_device_id = null,
    last_command_id = null
from public.privacy_settings as privacy
where preferences.user_id = privacy.user_id
  and preferences.deleted_at is null
  and privacy.deleted_at is null
  and (
    coalesce(preferences.data ->> 'detailed_activity_sync_enabled', 'false')
      is distinct from case
        when coalesce(
          privacy.activity_storage = 'synchronized'
          and privacy.data @> '{"detailed_activity_sync_opt_in": true}'::jsonb,
          false
        ) then 'true'
        else 'false'
      end
    or coalesce(preferences.data ->> 'activity_upload_policy', '') is distinct from
      case
        when coalesce(
          privacy.activity_storage = 'synchronized'
          and privacy.data @> '{"detailed_activity_sync_opt_in": true}'::jsonb,
          false
        ) then 'explicit_detailed_history'
        else 'approved_contributions_only'
      end
  );

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
begin
  -- A client may still need to retire an old raw record that was accepted by
  -- a pre-policy build.  Let that one-way cleanup converge instead of turning
  -- a privacy migration into a permanent sync failure. Preserve every
  -- content-bearing column from OLD so a deletion cannot simultaneously be
  -- used to smuggle a new raw value into the canonical record.
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
      and new.page_title is null;

    -- A contribution is not privacy-safe merely because its visible columns
    -- are empty: legacy raw samples lived in raw_metadata.  The only metadata
    -- allowed across devices is the small, documented provenance envelope.
    approved_safe_contribution := approved_safe_contribution
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

    if approved_safe_contribution
       or (storage_mode = 'synchronized' and detailed_opt_in) then
      return new;
    end if;

    raise exception 'activity_privacy_local_only' using errcode = '42501';
  end if;

  if tg_table_name = 'activity_review_queue' then
    if storage_mode = 'synchronized' and detailed_opt_in then
      return new;
    end if;

    if exists (
      select 1
      from public.activity_segments as segment
      where segment.user_id = new.user_id
        and segment.id = new.activity_segment_id
        and segment.deleted_at is null
        and coalesce(segment.data, '{}'::jsonb)
          @> '{"approved_contribution": true}'::jsonb
    )
       and coalesce(new.suggested_targets, '[]'::jsonb) = '[]'::jsonb
       and coalesce(new.data, '{}'::jsonb)
         <@ '{"capture_state": "finalized"}'::jsonb then
      return new;
    end if;

    raise exception 'activity_privacy_local_only' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_activity_privacy_v0028 on public.activity_segments;
create trigger enforce_activity_privacy_v0028
before insert or update on public.activity_segments
for each row execute function public.enforce_activity_privacy_v0028();

drop trigger if exists enforce_activity_review_privacy_v0028
  on public.activity_review_queue;
create trigger enforce_activity_review_privacy_v0028
before insert or update on public.activity_review_queue
for each row execute function public.enforce_activity_privacy_v0028();

revoke all on function public.enforce_activity_privacy_v0028() from public;

comment on function public.enforce_activity_privacy_v0028() is
  'Blocks raw Activity transport unless privacy_settings has an explicit detailed-history opt-in; permits privacy-safe approved contributions.';
