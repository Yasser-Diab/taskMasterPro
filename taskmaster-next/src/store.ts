import type {
  ActivityInterval,
  BrowserTabState,
  PomodoroState,
  QuickNote,
  RoadmapPhase,
  RoadmapPlan,
  RuntimeState,
  SessionSegment,
  TaskItem,
  TaskMasterSnapshot,
  UserSettings,
} from './domain';
import { blankRuntime, defaultDomains, defaultSettings } from './domain';
import { supabase } from './supabaseClient';

const storageKey = 'taskmaster-pro-next.snapshot.v2';

export function nowIso() {
  return new Date().toISOString();
}

export function createId(prefix: string) {
  const random =
    typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID()
      : Math.random().toString(36).slice(2);
  return `${prefix}_${random}`;
}

export function initialSnapshot(): TaskMasterSnapshot {
  const createdAt = nowIso();
  return {
    domains: defaultDomains,
    tasks: [],
    roadmaps: [],
    quickNotes: [],
    sessions: [],
    activityIntervals: [],
    browserTabs: [
      {
        id: createId('tab'),
        url: 'https://www.google.com',
        title: 'Google',
        pinned: true,
        lastOpenedAt: createdAt,
      },
    ],
    settings: defaultSettings,
    runtime: blankRuntime,
  };
}

export function loadLocalSnapshot(): TaskMasterSnapshot {
  const raw = localStorage.getItem(storageKey);
  if (!raw) return initialSnapshot();
  try {
    const parsed = JSON.parse(raw) as Partial<TaskMasterSnapshot>;
    return normalizeSnapshot(parsed);
  } catch {
    return initialSnapshot();
  }
}

export function saveLocalSnapshot(snapshot: TaskMasterSnapshot) {
  localStorage.setItem(storageKey, JSON.stringify(snapshot));
}

export function normalizeSnapshot(snapshot: Partial<TaskMasterSnapshot>): TaskMasterSnapshot {
  return {
    domains: snapshot.domains?.length ? snapshot.domains : defaultDomains,
    tasks: (snapshot.tasks ?? []).map(normalizeTask),
    roadmaps: snapshot.roadmaps ?? [],
    quickNotes: snapshot.quickNotes ?? [],
    sessions: snapshot.sessions ?? [],
    activityIntervals: snapshot.activityIntervals ?? [],
    browserTabs: snapshot.browserTabs?.length
      ? snapshot.browserTabs
      : [
          {
            id: createId('tab'),
            url: 'https://www.google.com',
            title: 'Google',
            pinned: true,
            lastOpenedAt: nowIso(),
          },
        ],
    settings: { ...defaultSettings, ...(snapshot.settings ?? {}) },
    runtime: { ...blankRuntime, ...(snapshot.runtime ?? {}) },
    lastSyncAt: snapshot.lastSyncAt,
    syncError: snapshot.syncError,
  };
}

export function defaultFocusProfile(title = '') {
  return {
    expectedActivity: title ? `Work related to "${title}"` : 'Focused work for this task',
    allowedDomains: [],
    distractionDomains: [],
    relatedApplications: [],
  };
}

export function normalizeTask(task: TaskItem): TaskItem {
  return {
    ...task,
    tags: task.tags ?? [],
    resources: task.resources ?? [],
    focusProfile: {
      ...defaultFocusProfile(task.title),
      ...(task.focusProfile ?? {}),
      allowedDomains: task.focusProfile?.allowedDomains ?? [],
      distractionDomains: task.focusProfile?.distractionDomains ?? [],
      relatedApplications: task.focusProfile?.relatedApplications ?? [],
    },
  };
}

export async function pullRemoteSnapshot(current: TaskMasterSnapshot): Promise<TaskMasterSnapshot> {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) return current;

  const [profile, settings, tasks, roadmaps, phases, quickNotes] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', user.id).maybeSingle(),
    supabase.from('user_settings').select('*').eq('user_id', user.id).maybeSingle(),
    supabase.from('tasks').select('*').eq('user_id', user.id).is('deleted_at', null),
    supabase.from('roadmaps').select('*').eq('user_id', user.id).is('deleted_at', null),
    supabase.from('roadmap_phases').select('*').eq('user_id', user.id).is('deleted_at', null),
    supabase.from('quick_notes').select('*').eq('user_id', user.id),
  ]);

  const errors = [profile.error, settings.error, tasks.error, roadmaps.error, phases.error, quickNotes.error].filter(Boolean);
  if (errors.length) {
    throw new Error(errors.map((error) => error?.message).join('; '));
  }

  const phaseRows = phases.data ?? [];
  const nextRoadmaps = (roadmaps.data ?? []).map((row) => fromRoadmapRow(row, phaseRows));
  const next: TaskMasterSnapshot = {
    ...current,
    settings: {
      ...(settings.data ? fromSettingsRow(settings.data, current.settings) : current.settings),
      displayName: profile.data?.display_name ?? current.settings.displayName,
      username: profile.data?.username ?? current.settings.username,
      language: profile.data?.preferred_language ?? current.settings.language,
    },
    tasks: (tasks.data ?? []).map(fromTaskRow).map(normalizeTask),
    roadmaps: nextRoadmaps,
    quickNotes: (quickNotes.data ?? []).map(fromQuickNoteRow),
    lastSyncAt: nowIso(),
    syncError: undefined,
  };
  saveLocalSnapshot(next);
  return next;
}

export async function syncTask(task: TaskItem) {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) return;
  await supabase.from('tasks').upsert(toTaskRow(task, user.id), { onConflict: 'id' });
}

export async function syncQuickNote(note: QuickNote) {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) return;
  await supabase.from('quick_notes').upsert(toQuickNoteRow(note, user.id), { onConflict: 'id' });
}

export async function syncSettings(settings: UserSettings) {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) return;
  await supabase.from('profiles').upsert(
    {
      id: user.id,
      display_name: settings.displayName || null,
      username: settings.username || null,
      preferred_language: settings.language,
      time_zone_mode: 'fixed',
      fixed_time_zone_id: settings.homeTimeZoneId,
      clock_format: 'system',
      updated_at: nowIso(),
    },
    { onConflict: 'id' },
  );
  await supabase.from('user_settings').upsert(toSettingsRow(settings, user.id), {
    onConflict: 'user_id',
  });
}

export async function syncRoadmap(roadmap: RoadmapPlan) {
  const user = (await supabase.auth.getUser()).data.user;
  if (!user) return;
  await supabase.from('roadmaps').upsert(toRoadmapRow(roadmap, user.id), { onConflict: 'id' });
  for (const phase of roadmap.phases) {
    await supabase.from('roadmap_phases').upsert(toPhaseRow(phase, user.id), { onConflict: 'id' });
  }
}

export function runtimeElapsed(runtime: RuntimeState, at = new Date()) {
  if (!runtime.lastResumedAtUtc || !runtime.state.endsWith('_running')) {
    return runtime.accumulatedActiveSeconds;
  }
  const resumed = new Date(runtime.lastResumedAtUtc).getTime();
  return runtime.accumulatedActiveSeconds + Math.max(0, Math.floor((at.getTime() - resumed) / 1000));
}

export function runtimeRemaining(runtime: RuntimeState, at = new Date()) {
  return Math.max(0, runtime.plannedDurationSeconds - runtimeElapsed(runtime, at));
}

export function transitionRuntime(runtime: RuntimeState, nextState: PomodoroState): RuntimeState {
  const active = runtimeElapsed(runtime);
  const timestamp = nowIso();
  const running = nextState.endsWith('_running');
  return {
    ...runtime,
    state: nextState,
    accumulatedActiveSeconds: active,
    lastResumedAtUtc: running ? timestamp : undefined,
    segmentStartedAtUtc: runtime.segmentStartedAtUtc ?? timestamp,
  };
}

export function completeCurrentSegment(snapshot: TaskMasterSnapshot): TaskMasterSnapshot {
  const runtime = snapshot.runtime;
  const task = snapshot.tasks.find((item) => item.id === runtime.activeTaskId);
  if (!task || !runtime.segmentStartedAtUtc) return snapshot;
  const activeSeconds = runtimeElapsed(runtime);
  const segment: SessionSegment = {
    id: createId('segment'),
    taskId: task.id,
    taskTitle: task.title,
    segmentType: runtime.state.startsWith('break') ? 'short_break' : 'focus',
    startedAtUtc: runtime.segmentStartedAtUtc,
    endedAtUtc: nowIso(),
    activeSeconds,
  };
  return {
    ...snapshot,
    sessions: [segment, ...snapshot.sessions].slice(0, 100),
  };
}

export function appendActivityInterval(snapshot: TaskMasterSnapshot, interval: ActivityInterval): TaskMasterSnapshot {
  return {
    ...snapshot,
    activityIntervals: [interval, ...snapshot.activityIntervals].slice(0, 500),
  };
}

function fromTaskRow(row: Record<string, any>): TaskItem {
  return {
    id: row.id,
    userId: row.user_id,
    domainId: row.domain_id ?? undefined,
    roadmapId: row.roadmap_id ?? undefined,
    phaseId: row.phase_id ?? undefined,
    title: row.title ?? '',
    description: row.description ?? '',
    executionMode: row.execution_mode ?? 'manual_completion',
    status: row.status ?? 'todo',
    priority: row.priority ?? 'normal',
    plannedLocalDate: row.planned_local_date ?? undefined,
    plannedStartMinutes: row.planned_start_minutes ?? undefined,
    plannedEndMinutes: row.planned_end_minutes ?? undefined,
    timeZoneId: row.time_zone_id ?? defaultSettings.homeTimeZoneId,
    remindersEnabled: row.reminders_enabled ?? false,
    recurrenceRule: row.recurrence_rule ?? undefined,
    progressMethod: row.progress_method ?? 'manual',
    manualProgress: Number(row.manual_progress ?? 0),
    tags: Array.isArray(row.tags) ? row.tags : [],
    resources: [],
    focusProfile: defaultFocusProfile(row.title ?? ''),
    createdAt: row.created_at ?? nowIso(),
    updatedAt: row.updated_at ?? nowIso(),
    deletedAt: row.deleted_at ?? undefined,
  };
}

function toTaskRow(task: TaskItem, userId: string) {
  return {
    id: task.id,
    user_id: userId,
    domain_id: task.domainId ?? null,
    roadmap_id: task.roadmapId ?? null,
    phase_id: task.phaseId ?? null,
    title: task.title,
    description: task.description,
    execution_mode: task.executionMode,
    status: task.status,
    priority: task.priority,
    planned_local_date: task.plannedLocalDate ?? null,
    planned_start_minutes: task.plannedStartMinutes ?? null,
    planned_end_minutes: task.plannedEndMinutes ?? null,
    time_zone_behavior: 'keep_local_clock',
    time_zone_id: task.timeZoneId,
    reminders_enabled: task.remindersEnabled,
    recurrence_rule: task.recurrenceRule ?? null,
    progress_method: task.progressMethod,
    manual_progress: task.manualProgress,
    updated_at: nowIso(),
  };
}

function fromRoadmapRow(row: Record<string, any>, phases: Record<string, any>[]): RoadmapPlan {
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title ?? '',
    description: row.description ?? '',
    goal: row.goal ?? '',
    status: row.status ?? 'not_started',
    progressMethod: row.progress_method ?? 'linked_tasks',
    manualProgress: Number(row.manual_progress ?? 0),
    phases: phases
      .filter((phase) => phase.roadmap_id === row.id)
      .map(fromPhaseRow)
      .sort((a, b) => a.phaseOrder - b.phaseOrder),
    createdAt: row.created_at ?? nowIso(),
    updatedAt: row.updated_at ?? nowIso(),
  };
}

function fromPhaseRow(row: Record<string, any>): RoadmapPhase {
  return {
    id: row.id,
    roadmapId: row.roadmap_id,
    title: row.title ?? '',
    description: row.description ?? '',
    phaseOrder: row.phase_order ?? 0,
    status: row.status ?? 'not_started',
  };
}

function toRoadmapRow(roadmap: RoadmapPlan, userId: string) {
  return {
    id: roadmap.id,
    user_id: userId,
    title: roadmap.title,
    description: roadmap.description,
    goal: roadmap.goal,
    status: roadmap.status,
    progress_method: roadmap.progressMethod,
    manual_progress: roadmap.manualProgress,
    updated_at: nowIso(),
  };
}

function toPhaseRow(phase: RoadmapPhase, userId: string) {
  return {
    id: phase.id,
    user_id: userId,
    roadmap_id: phase.roadmapId,
    phase_order: phase.phaseOrder,
    title: phase.title,
    description: phase.description,
    status: phase.status,
    progress_method: 'linked_tasks',
    updated_at: nowIso(),
  };
}

function fromQuickNoteRow(row: Record<string, any>): QuickNote {
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title ?? '',
    body: row.body ?? '',
    details: row.details ?? '',
    category: row.category ?? undefined,
    roadmapId: row.roadmap_id ?? undefined,
    convertedTaskId: row.converted_task_id ?? undefined,
    createdAt: row.created_at ?? nowIso(),
    updatedAt: row.updated_at ?? nowIso(),
  };
}

function toQuickNoteRow(note: QuickNote, userId: string) {
  return {
    id: note.id,
    user_id: userId,
    title: note.title,
    body: note.body,
    details: note.details,
    category: note.category ?? null,
    roadmap_id: note.roadmapId ?? null,
    converted_task_id: note.convertedTaskId ?? null,
    created_at: note.createdAt,
    updated_at: nowIso(),
  };
}

function fromSettingsRow(row: Record<string, any>, current: UserSettings): UserSettings {
  return {
    ...current,
    theme: row.theme ?? current.theme,
    language: row.language ?? current.language,
    focusDurationSeconds: row.focus_duration_seconds ?? current.focusDurationSeconds,
    shortBreakDurationSeconds: row.short_break_duration_seconds ?? current.shortBreakDurationSeconds,
    longBreakDurationSeconds: row.long_break_duration_seconds ?? current.longBreakDurationSeconds,
    autoStartBreak: row.auto_start_break ?? current.autoStartBreak,
    autoStartFocus: row.auto_start_focus ?? current.autoStartFocus,
    idleThresholdSeconds: row.idle_threshold_seconds ?? current.idleThresholdSeconds,
    homeTimeZoneId: row.fixed_time_zone_id ?? current.homeTimeZoneId,
    browserSyncEnabled: row.browser_sync_enabled ?? current.browserSyncEnabled,
    passwordSyncEnabled: row.browser_password_sync_enabled ?? current.passwordSyncEnabled,
    healthSyncEnabled: row.health_sync_enabled ?? current.healthSyncEnabled,
    cycleSyncEnabled: row.cycle_sync_enabled ?? current.cycleSyncEnabled,
  };
}

function toSettingsRow(settings: UserSettings, userId: string) {
  return {
    user_id: userId,
    theme: settings.theme,
    language: settings.language,
    coaching_intensity: 'balanced',
    focus_duration_seconds: settings.focusDurationSeconds,
    short_break_duration_seconds: settings.shortBreakDurationSeconds,
    long_break_duration_seconds: settings.longBreakDurationSeconds,
    long_break_after_focus_count: 4,
    auto_start_break: settings.autoStartBreak,
    auto_start_focus: settings.autoStartFocus,
    ask_break_activity: true,
    idle_threshold_seconds: settings.idleThresholdSeconds,
    default_search_engine: 'google',
    browser_sync_enabled: settings.browserSyncEnabled,
    browser_password_sync_enabled: settings.passwordSyncEnabled,
    bookmark_sync_enabled: true,
    health_sync_enabled: settings.healthSyncEnabled,
    cycle_sync_enabled: settings.cycleSyncEnabled,
    time_zone_mode: 'fixed',
    fixed_time_zone_id: settings.homeTimeZoneId,
    clock_format: 'system',
    quiet_hours_start_minutes: null,
    quiet_hours_end_minutes: null,
    updated_at: nowIso(),
  };
}
