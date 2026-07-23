# TaskMaster Pro Product Improvement Research

Research date: 2026-07-23

This note captures web-backed improvements to prioritize after the clean data/runtime refactor. Sources are official product/help pages where possible.

## Recommended Improvements

1. Natural-language quick capture
   - Todoist emphasizes fast capture with natural-language dates, recurring due dates, and reminders.
   - TaskMaster Pro should add one global command bar for text like `review roadmap Friday 5pm every week #Learning`.
   - Source: https://www.todoist.com/features

2. Time blocking and calendar-first planning
   - Akiflow centers task execution around calendar time blocks, smart slots, daily/weekly planning, and AI nudges.
   - TaskMaster Pro already has roadmap, tasks, and timers; the next leap is a planning surface that turns tasks into protected blocks automatically.
   - Source: https://akiflow.com/

3. Integrated Pomodoro, habits, calendar, and priority matrix
   - TickTick combines tasks, calendar, Eisenhower Matrix, Pomodoro, and habits in one product.
   - TaskMaster Pro should keep its richer task domains, but add a compact priority matrix and habit dashboard that reuse the same task/runtime schema.
   - Sources: https://help.ticktick.com/articles/7054286604315131904 and https://ticktick.com/features

4. Recurrence visibility and occurrence control
   - Google Tasks/Calendar supports repeating tasks, but only a limited number of upcoming recurring tasks appear.
   - TaskMaster Pro should avoid that limitation by showing a configurable upcoming occurrence horizon, conflict warnings, and per-occurrence skip/reschedule.
   - Source: https://support.google.com/tasks/answer/12132599

5. Cross-device reminders that match task time
   - Todoist supports automatic reminders when tasks have dates and times, across desktop/mobile/email notification channels.
   - TaskMaster Pro should map reminders to the authoritative occurrence/session state and suppress duplicates across devices.
   - Source: https://www.todoist.com/help/articles/introduction-to-reminders-9PezfU

6. Save web pages and resources into tasks
   - Todoist highlights saving websites as tasks and sharing web pages into tasks from mobile.
   - TaskMaster Pro already has a browser and resource schema; the next improvement is a frictionless "Save to current task/roadmap" flow from browser tabs and Android share intents.
   - Source: https://www.todoist.com/inspiration/hidden-features-todoist

7. Honest productivity analytics
   - Todoist uses productivity goals/streaks, while Akiflow focuses on planned work actually getting scheduled.
   - TaskMaster Pro should favor explainable analytics: planned vs focused time, start delay, overdue demand rollover, roadmap pace, and confidence instead of generic scores.
   - Sources: https://www.todoist.com/inspiration/hidden-features-todoist and https://akiflow.com/

## Product Direction

The strongest differentiator for TaskMaster Pro is not copying a simple to-do app. The product should become a local-first execution system: tasks, roadmaps, Pomodoro, browser resources, health signals, and multi-device runtime all explain one question clearly:

What should I do next, why now, and what changed after I worked?
