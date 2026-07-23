export type AppSection =
  | 'dashboard'
  | 'tasks'
  | 'pomodoro'
  | 'history'
  | 'roadmap'
  | 'browser'
  | 'settings';

export type ExecutionMode =
  | 'pomodoro'
  | 'continuous_timer'
  | 'checklist'
  | 'reading'
  | 'habit'
  | 'event'
  | 'manual_completion'
  | 'hybrid';

export type TaskStatus = 'todo' | 'in_progress' | 'completed' | 'skipped';

export type Priority = 'low' | 'normal' | 'high' | 'urgent';

export interface TaskDomain {
  id: string;
  name: string;
  icon: string;
  color: string;
  sortOrder: number;
}

export interface TaskItem {
  id: string;
  userId?: string;
  domainId?: string;
  roadmapId?: string;
  phaseId?: string;
  title: string;
  description: string;
  executionMode: ExecutionMode;
  status: TaskStatus;
  priority: Priority;
  plannedLocalDate?: string;
  plannedStartMinutes?: number;
  plannedEndMinutes?: number;
  timeZoneId: string;
  remindersEnabled: boolean;
  recurrenceRule?: string;
  progressMethod: 'manual' | 'checkpoints' | 'linked_sessions';
  manualProgress: number;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string;
}

export interface RoadmapPhase {
  id: string;
  roadmapId: string;
  title: string;
  description: string;
  phaseOrder: number;
  status: 'not_started' | 'active' | 'completed' | 'paused';
}

export interface RoadmapPlan {
  id: string;
  userId?: string;
  title: string;
  description: string;
  goal: string;
  status: 'not_started' | 'active' | 'completed' | 'paused';
  progressMethod: 'linked_tasks' | 'manual' | 'weighted';
  manualProgress: number;
  phases: RoadmapPhase[];
  createdAt: string;
  updatedAt: string;
}

export interface QuickNote {
  id: string;
  userId?: string;
  title: string;
  body: string;
  details: string;
  category?: string;
  roadmapId?: string;
  convertedTaskId?: string;
  createdAt: string;
  updatedAt: string;
}

export interface SessionSegment {
  id: string;
  taskId: string;
  taskTitle: string;
  segmentType: 'focus' | 'short_break' | 'long_break' | 'continuous_work' | 'manual';
  startedAtUtc: string;
  endedAtUtc?: string;
  activeSeconds: number;
}

export type PomodoroState =
  | 'focus_ready'
  | 'focus_running'
  | 'focus_paused'
  | 'focus_completed_waiting'
  | 'break_ready'
  | 'break_running'
  | 'break_paused'
  | 'break_completed_waiting'
  | 'task_completed'
  | 'cancelled';

export interface RuntimeState {
  activeTaskId?: string;
  state: PomodoroState;
  segmentStartedAtUtc?: string;
  lastResumedAtUtc?: string;
  accumulatedActiveSeconds: number;
  plannedDurationSeconds: number;
  completedFocusCount: number;
}

export interface BrowserTabState {
  id: string;
  url: string;
  title: string;
  pinned: boolean;
  taskId?: string;
  lastOpenedAt: string;
}

export interface UserSettings {
  displayName: string;
  username: string;
  language: 'en' | 'ar' | 'de';
  theme: 'dark_blue' | 'black_gold' | 'light';
  focusDurationSeconds: number;
  shortBreakDurationSeconds: number;
  longBreakDurationSeconds: number;
  autoStartBreak: boolean;
  autoStartFocus: boolean;
  idleThresholdSeconds: number;
  homeTimeZoneId: string;
  wakeUpTime: string;
  bedtime: string;
  workStartTime: string;
  workEndTime: string;
  browserSyncEnabled: boolean;
  passwordSyncEnabled: boolean;
  healthSyncEnabled: boolean;
  cycleSyncEnabled: boolean;
}

export interface TaskMasterSnapshot {
  domains: TaskDomain[];
  tasks: TaskItem[];
  roadmaps: RoadmapPlan[];
  quickNotes: QuickNote[];
  sessions: SessionSegment[];
  browserTabs: BrowserTabState[];
  settings: UserSettings;
  runtime: RuntimeState;
  lastSyncAt?: string;
  syncError?: string;
}

export const defaultDomains: TaskDomain[] = [
  { id: 'work', name: 'Work', icon: 'briefcase', color: '#3b82f6', sortOrder: 1 },
  { id: 'learning', name: 'Learning', icon: 'graduation-cap', color: '#22c55e', sortOrder: 2 },
  { id: 'reading', name: 'Reading', icon: 'book-open', color: '#f59e0b', sortOrder: 3 },
  { id: 'self-improvement', name: 'Self-improvement', icon: 'sparkles', color: '#a855f7', sortOrder: 4 },
  { id: 'householding', name: 'Householding', icon: 'home', color: '#14b8a6', sortOrder: 5 },
  { id: 'sport', name: 'Sport', icon: 'activity', color: '#ef4444', sortOrder: 6 },
  { id: 'event', name: 'Event', icon: 'calendar-days', color: '#06b6d4', sortOrder: 7 },
  { id: 'personal', name: 'Personal', icon: 'user', color: '#84cc16', sortOrder: 8 },
  { id: 'habit', name: 'Habit', icon: 'repeat', color: '#f97316', sortOrder: 9 },
];

export const defaultSettings: UserSettings = {
  displayName: 'Diab',
  username: 'YasserDiab',
  language: 'en',
  theme: 'dark_blue',
  focusDurationSeconds: 1500,
  shortBreakDurationSeconds: 300,
  longBreakDurationSeconds: 900,
  autoStartBreak: false,
  autoStartFocus: false,
  idleThresholdSeconds: 30,
  homeTimeZoneId: Intl.DateTimeFormat().resolvedOptions().timeZone || 'Africa/Cairo',
  wakeUpTime: '05:00',
  bedtime: '23:30',
  workStartTime: '09:00',
  workEndTime: '17:30',
  browserSyncEnabled: true,
  passwordSyncEnabled: false,
  healthSyncEnabled: false,
  cycleSyncEnabled: false,
};

export const blankRuntime: RuntimeState = {
  state: 'focus_ready',
  accumulatedActiveSeconds: 0,
  plannedDurationSeconds: defaultSettings.focusDurationSeconds,
  completedFocusCount: 0,
};
