-- Every synchronized feature table must emit a durable change envelope so
-- offline devices can pull the row after reconnecting. The baseline covered
-- the initial core; this completes tracking for all current feature records.

do $$
declare
  table_name text;
  tracked_tables text[] := array[
    'profiles',
    'user_settings',
    'coaching_settings',
    'privacy_settings',
    'account_devices',
    'task_domains',
    'task_categories',
    'tags',
    'task_templates',
    'task_occurrences',
    'recurrence_rules',
    'recurrence_exceptions',
    'task_dependencies',
    'task_reminders',
    'execution_sessions',
    'session_events',
    'user_runtime_state',
    'pomodoro_cycles',
    'interruptions',
    'task_completion_evidence',
    'checklist_items',
    'work_demands',
    'learning_checkpoints',
    'reading_targets',
    'reading_positions',
    'habit_records',
    'event_attendance',
    'task_notes',
    'roadmaps',
    'roadmap_phases',
    'roadmap_milestones',
    'roadmap_checkpoints',
    'roadmap_progress_rules',
    'roadmap_evidence',
    'roadmap_forecasts',
    'application_catalog',
    'application_rules',
    'website_rules',
    'activity_segments',
    'activity_attributions',
    'activity_contributions',
    'contribution_roadmap_effects',
    'activity_review_queue',
    'classification_feedback',
    'task_resources',
    'resource_activity',
    'browser_workspaces',
    'browser_tabs',
    'browser_bookmarks',
    'browser_history_events',
    'browser_closed_tabs',
    'document_positions',
    'coaching_insights',
    'coaching_feedback',
    'daily_metrics',
    'weekly_metrics',
    'monthly_metrics',
    'task_performance_profiles',
    'notification_decisions',
    'health_permissions',
    'health_summaries',
    'cycle_records'
  ];
begin
  foreach table_name in array tracked_tables
  loop
    if to_regclass('public.' || quote_ident(table_name)) is not null
       and not exists (
         select 1
         from pg_catalog.pg_trigger trigger_row
         join pg_catalog.pg_class table_row
           on table_row.oid = trigger_row.tgrelid
         join pg_catalog.pg_namespace namespace_row
           on namespace_row.oid = table_row.relnamespace
         where namespace_row.nspname = 'public'
           and table_row.relname = table_name
           and trigger_row.tgname = 'log_' || table_name
           and not trigger_row.tgisinternal
       )
    then
      execute format(
        'create trigger %I after insert or update on public.%I
         for each row execute function private.log_synchronized_change()',
        'log_' || table_name,
        table_name
      );
    end if;
  end loop;
end;
$$;
