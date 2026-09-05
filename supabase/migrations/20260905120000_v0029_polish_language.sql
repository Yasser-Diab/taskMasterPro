-- DayVector 0.0.30: Polish is a first-class preferred-language value.
-- `user_settings.data` is already jsonb and accepts the new work-schedule
-- fields without a table migration; this constraint is the only relational
-- schema gate that would otherwise reject `pl` during an account sync.

alter table public.user_settings
  drop constraint if exists user_settings_preferred_language_check;

alter table public.user_settings
  add constraint user_settings_preferred_language_check
  check (preferred_language in ('en', 'ar', 'de', 'pl'));
