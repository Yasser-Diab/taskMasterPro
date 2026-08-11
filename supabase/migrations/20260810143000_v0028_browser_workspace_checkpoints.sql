-- Browser resume state is a small, durable checkpoint rather than a stream of
-- scroll events.  Keeping it on the tab row makes it available to the normal
-- revisioned command path and to another signed-in device after a bounded
-- checkpoint is committed.
alter table public.browser_tabs
  add column if not exists checkpoint jsonb not null default '{}'::jsonb;

comment on column public.browser_tabs.checkpoint is
  'Bounded resume metadata: URL/title, scroll position, optional media time, and zoom scale. Never DOM, form, cookie, or credential content.';
