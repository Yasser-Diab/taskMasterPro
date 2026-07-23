import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  AppWindow,
  Bell,
  BookOpen,
  BriefcaseBusiness,
  CalendarDays,
  Check,
  CheckCheck,
  ChevronRight,
  CirclePause,
  CirclePlay,
  Clock3,
  Database,
  Download,
  ExternalLink,
  FilePlus2,
  Gauge,
  Globe2,
  GraduationCap,
  History,
  Home,
  LayoutDashboard,
  LinkIcon,
  ListChecks,
  Loader2,
  LogIn,
  LogOut,
  Map,
  Monitor,
  MoreHorizontal,
  Pause,
  Paperclip,
  Play,
  Plus,
  RefreshCw,
  Repeat,
  Save,
  Search,
  Settings,
  Sparkles,
  Square,
  TimerReset,
  Trash2,
  User,
  Smartphone,
  Target,
} from 'lucide-react';
import type { Session } from '@supabase/supabase-js';
import {
  type ActivityInterval,
  BrowserTabState,
  type AppSection,
  type ExecutionMode,
  type Priority,
  type QuickNote,
  type RoadmapPlan,
  type RuntimeState,
  type TaskItem,
  type TaskMasterSnapshot,
} from './domain';
import { defaultDomains } from './domain';
import {
  appendActivityInterval,
  completeCurrentSegment,
  createId,
  defaultFocusProfile,
  loadLocalSnapshot,
  normalizeTask,
  nowIso,
  pullRemoteSnapshot,
  runtimeRemaining,
  saveLocalSnapshot,
  syncQuickNote,
  syncRoadmap,
  syncSettings,
  syncTask,
  transitionRuntime,
} from './store';
import type { CurrentActivity } from './platform/services';
import { platformServices } from './platform/services';
import { publicProjectLabel, supabase, supabaseUrl } from './supabaseClient';

const assetUrl = (path: string) => `${import.meta.env.BASE_URL}${path.replace(/^\/+/, '')}`;

const sections: Array<{ id: AppSection; label: string; icon: typeof LayoutDashboard }> = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'tasks', label: 'Tasks', icon: ListChecks },
  { id: 'pomodoro', label: 'Pomodoro', icon: Clock3 },
  { id: 'history', label: 'History', icon: CalendarDays },
  { id: 'roadmap', label: 'Roadmap', icon: Map },
  { id: 'browser', label: 'Browser', icon: Globe2 },
  { id: 'settings', label: 'Settings', icon: Settings },
];

const releaseDownloads = [
  {
    label: 'Windows installer',
    detail: 'TaskMasterPro-Next-Windows-Setup.exe',
    href: 'https://github.com/Yasser-Diab/taskMasterPro/releases/latest/download/TaskMasterPro-Next-Windows-Setup.exe',
    icon: Monitor,
  },
  {
    label: 'Android APK',
    detail: 'TaskMasterPro-Next-Android.apk',
    href: 'https://github.com/Yasser-Diab/taskMasterPro/releases/latest/download/TaskMasterPro-Next-Android.apk',
    icon: Smartphone,
  },
  {
    label: 'Supabase SQL',
    detail: 'TaskMasterPro-Next-Supabase-Clean-Rebuild.sql',
    href: 'https://github.com/Yasser-Diab/taskMasterPro/releases/latest/download/TaskMasterPro-Next-Supabase-Clean-Rebuild.sql',
    icon: Database,
  },
];

const executionModes: ExecutionMode[] = [
  'pomodoro',
  'continuous_timer',
  'checklist',
  'reading',
  'habit',
  'event',
  'manual_completion',
  'hybrid',
];

const priorities: Priority[] = ['low', 'normal', 'high', 'urgent'];

const commonZones = [
  'Africa/Cairo',
  'Europe/Athens',
  'Europe/Berlin',
  'Europe/London',
  'America/New_York',
  'America/Los_Angeles',
  'Asia/Dubai',
  'Asia/Riyadh',
  'Asia/Tokyo',
  'Australia/Sydney',
];

export function App() {
  const [snapshot, setSnapshot] = useState<TaskMasterSnapshot>(() => loadLocalSnapshot());
  const devPreviewAuth =
    import.meta.env.DEV && window.localStorage.getItem('taskmaster-pro-next.preview-auth') === '1';
  const [section, setSection] = useState<AppSection>('dashboard');
  const [quickNoteOpen, setQuickNoteOpen] = useState(false);
  const [taskEditorOpen, setTaskEditorOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<TaskItem | undefined>();
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [authMode, setAuthMode] = useState<'sign-in' | 'create-account'>('sign-in');
  const [authEmail, setAuthEmail] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [authDisplayName, setAuthDisplayName] = useState('');
  const [authUsername, setAuthUsername] = useState('');
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState<string>();
  const [clock, setClock] = useState(() => Date.now());

  const persist = useCallback((next: TaskMasterSnapshot) => {
    saveLocalSnapshot(next);
    setSnapshot(next);
  }, []);

  const patchSnapshot = useCallback(
    (mutator: (current: TaskMasterSnapshot) => TaskMasterSnapshot) => {
      setSnapshot((current) => {
        const next = mutator(current);
        saveLocalSnapshot(next);
        return next;
      });
    },
    [],
  );

  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setAuthReady(true);
      if (data.session) void refreshFromRemote();
    });
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (nextSession) void refreshFromRemote();
      setAuthReady(true);
    });
    return () => data.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!session?.user.id) return;
    const channel = supabase
      .channel(`taskmaster:user:${session.user.id}:runtime`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, () => void refreshFromRemote())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'quick_notes' }, () => void refreshFromRemote())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'roadmaps' }, () => void refreshFromRemote())
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.user.id]);

  useEffect(() => {
    const remaining = runtimeRemaining(snapshot.runtime, new Date(clock));
    if (remaining > 0 || !snapshot.runtime.state.endsWith('_running')) return;
    patchSnapshot((current) => {
      const completed = completeCurrentSegment(current);
      const wasBreak = current.runtime.state.startsWith('break');
      return {
        ...completed,
        runtime: {
          ...completed.runtime,
          state: wasBreak ? 'break_completed_waiting' : 'focus_completed_waiting',
          accumulatedActiveSeconds: completed.runtime.plannedDurationSeconds,
          lastResumedAtUtc: undefined,
        },
      };
    });
  }, [clock, patchSnapshot, snapshot.runtime]);

  useEffect(() => {
    if (!snapshot.runtime.activeTaskId || !snapshot.runtime.state.endsWith('_running')) return;
    let cancelled = false;
    const sample = async () => {
      const task = loadLocalSnapshot().tasks.find((item) => item.id === snapshot.runtime.activeTaskId);
      if (!task) return;
      const activity = await platformServices.activityTracking.currentActivity();
      if (cancelled) return;
      const timestamp = nowIso();
      const interval: ActivityInterval = {
        id: createId('activity'),
        taskId: task.id,
        sourceType: activity.sourceType,
        applicationName: activity.applicationName,
        processName: activity.processName,
        windowTitle: activity.windowTitle,
        domain: activity.domain,
        url: activity.url,
        classification: classifyActivity(task, activity),
        startedAtUtc: timestamp,
        endedAtUtc: timestamp,
        activeSeconds: 10,
        idleSeconds: 0,
      };
      patchSnapshot((current) => appendActivityInterval(current, interval));
    };
    void sample();
    const intervalId = window.setInterval(() => void sample(), 10_000);
    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
    };
  }, [patchSnapshot, snapshot.runtime.activeTaskId, snapshot.runtime.state]);

  async function refreshFromRemote() {
    try {
      const next = await pullRemoteSnapshot(loadLocalSnapshot());
      persist(next);
    } catch (error) {
      patchSnapshot((current) => ({
        ...current,
        syncError: error instanceof Error ? error.message : String(error),
      }));
    }
  }

  async function signInWithPassword() {
    setAuthBusy(true);
    setAuthError(undefined);
    const email = authEmail.trim();
    const displayName = authDisplayName.trim();
    const username = authUsername.trim();
    const { data, error } =
      authMode === 'create-account'
        ? await supabase.auth.signUp({
            email,
            password: authPassword,
            options: {
              data: {
                display_name: displayName,
                username,
              },
            },
          })
        : await supabase.auth.signInWithPassword({
            email,
            password: authPassword,
          });
    setAuthBusy(false);
    if (error) {
      setAuthError(error.message);
      return;
    }
    if (authMode === 'create-account') {
      const settings = {
        ...snapshot.settings,
        displayName: displayName || email.split('@')[0],
        username: username || email.split('@')[0].replace(/[^a-zA-Z0-9_]/g, ''),
      };
      patchSnapshot((current) => ({ ...current, settings }));
      if (data.session) void syncSettings(settings);
    }
  }

  async function signInWithGoogle() {
    setAuthBusy(true);
    setAuthError(undefined);
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: window.location.origin,
        scopes: 'email profile',
      },
    });
    setAuthBusy(false);
    if (error) setAuthError(error.message);
  }

  function upsertTask(task: TaskItem) {
    patchSnapshot((current) => ({
      ...current,
      tasks: [task, ...current.tasks.filter((item) => item.id !== task.id)],
    }));
    void syncTask(task);
  }

  function saveTask(input: Partial<TaskItem>) {
    const task: TaskItem = {
      id: input.id ?? createId('task'),
      title: input.title?.trim() || 'Untitled task',
      description: input.description ?? '',
      domainId: input.domainId || 'work',
      roadmapId: input.roadmapId,
      phaseId: input.phaseId,
      executionMode: input.executionMode ?? 'manual_completion',
      status: input.status ?? 'todo',
      priority: input.priority ?? 'normal',
      plannedLocalDate: input.plannedLocalDate,
      plannedStartMinutes: input.plannedStartMinutes,
      plannedEndMinutes: input.plannedEndMinutes,
      timeZoneId: input.timeZoneId || snapshot.settings.homeTimeZoneId,
      remindersEnabled: input.remindersEnabled ?? false,
      recurrenceRule: input.recurrenceRule,
      progressMethod: input.progressMethod ?? 'manual',
      manualProgress: input.manualProgress ?? 0,
      tags: input.tags ?? [],
      resources: input.resources ?? [],
      focusProfile: input.focusProfile ?? defaultFocusProfile(input.title),
      createdAt: input.createdAt ?? nowIso(),
      updatedAt: nowIso(),
    };
    upsertTask(normalizeTask(task));
    setTaskEditorOpen(false);
    setEditingTask(undefined);
  }

  function saveQuickNote(note: Omit<QuickNote, 'id' | 'createdAt' | 'updatedAt'>, convert: boolean) {
    const createdAt = nowIso();
    let nextNote: QuickNote = {
      ...note,
      id: createId('note'),
      createdAt,
      updatedAt: createdAt,
    };
    let createdTask: TaskItem | undefined;
    if (convert) {
      createdTask = {
        id: createId('task'),
        title: note.title || note.body.slice(0, 60) || 'Quick note task',
        description: [note.body, note.details].filter(Boolean).join('\n\n'),
        domainId: 'personal',
        roadmapId: note.roadmapId,
        executionMode: 'manual_completion',
        status: 'todo',
        priority: 'normal',
        timeZoneId: snapshot.settings.homeTimeZoneId,
        remindersEnabled: false,
        progressMethod: 'manual',
        manualProgress: 0,
        tags: [],
        resources: [],
        focusProfile: defaultFocusProfile(note.title),
        createdAt,
        updatedAt: createdAt,
      };
      nextNote = { ...nextNote, convertedTaskId: createdTask.id };
    }
    patchSnapshot((current) => ({
      ...current,
      quickNotes: [nextNote, ...current.quickNotes],
      tasks: createdTask ? [createdTask, ...current.tasks] : current.tasks,
    }));
    void syncQuickNote(nextNote);
    if (createdTask) void syncTask(createdTask);
    setQuickNoteOpen(false);
  }

  function setRuntime(runtime: RuntimeState) {
    patchSnapshot((current) => ({ ...current, runtime }));
  }

  function startFocus(taskId: string) {
    setRuntime({
      activeTaskId: taskId,
      state: 'focus_running',
      segmentStartedAtUtc: nowIso(),
      lastResumedAtUtc: nowIso(),
      accumulatedActiveSeconds: 0,
      plannedDurationSeconds: snapshot.settings.focusDurationSeconds,
      completedFocusCount: snapshot.runtime.completedFocusCount,
    });
    upsertTask({ ...snapshot.tasks.find((task) => task.id === taskId)!, status: 'in_progress', updatedAt: nowIso() });
  }

  function transition(nextState: RuntimeState['state']) {
    patchSnapshot((current) => ({ ...current, runtime: transitionRuntime(current.runtime, nextState) }));
  }

  function finishTask() {
    patchSnapshot((current) => {
      const completed = completeCurrentSegment(current);
      return {
        ...completed,
        runtime: {
          ...completed.runtime,
          state: 'task_completed',
          lastResumedAtUtc: undefined,
          activeTaskId: undefined,
        },
        tasks: completed.tasks.map((task) =>
          task.id === current.runtime.activeTaskId
            ? { ...task, status: 'completed', manualProgress: 100, updatedAt: nowIso() }
            : task,
        ),
      };
    });
  }

  const activeTask = snapshot.tasks.find((task) => task.id === snapshot.runtime.activeTaskId);
  if (!authReady) {
    return <SplashScreen theme={snapshot.settings.theme} />;
  }

  if (!session && !devPreviewAuth) {
    return (
      <AuthScreen
        theme={snapshot.settings.theme}
        mode={authMode}
        email={authEmail}
        password={authPassword}
        displayName={authDisplayName}
        username={authUsername}
        busy={authBusy}
        error={authError}
        onMode={setAuthMode}
        onEmail={setAuthEmail}
        onPassword={setAuthPassword}
        onDisplayName={setAuthDisplayName}
        onUsername={setAuthUsername}
        onSubmit={signInWithPassword}
        onGoogle={signInWithGoogle}
      />
    );
  }

  const content = (
    <main className="app-main" data-testid="app-main">
      <TopBar
        section={section}
        onQuickNote={() => setQuickNoteOpen(true)}
        onAddTask={() => {
          setEditingTask(undefined);
          setTaskEditorOpen(true);
        }}
        syncLabel={snapshot.syncError ? 'Sync issue' : snapshot.lastSyncAt ? 'Synced' : 'Offline ready'}
      />
      {section === 'dashboard' && (
        <Dashboard
          snapshot={snapshot}
          onOpenTasks={() => setSection('tasks')}
          onOpenRoadmap={() => setSection('roadmap')}
          onStartFocus={startFocus}
        />
      )}
      {section === 'tasks' && (
        <Tasks
          snapshot={snapshot}
          onAdd={() => {
            setEditingTask(undefined);
            setTaskEditorOpen(true);
          }}
          onEdit={(task) => {
            setEditingTask(task);
            setTaskEditorOpen(true);
          }}
          onStart={startFocus}
          onUpdate={upsertTask}
        />
      )}
      {section === 'pomodoro' && (
        <Pomodoro
          snapshot={snapshot}
          activeTask={activeTask}
          onStart={startFocus}
          onTransition={transition}
          onFinishTask={finishTask}
          onStartBreak={() =>
            setRuntime({
              ...snapshot.runtime,
              state: 'break_running',
              segmentStartedAtUtc: nowIso(),
              lastResumedAtUtc: nowIso(),
              accumulatedActiveSeconds: 0,
              plannedDurationSeconds: snapshot.settings.shortBreakDurationSeconds,
            })
          }
          onContinueWorking={() =>
            setRuntime({
              ...snapshot.runtime,
              state: 'focus_running',
              segmentStartedAtUtc: nowIso(),
              lastResumedAtUtc: nowIso(),
              accumulatedActiveSeconds: 0,
              plannedDurationSeconds: snapshot.settings.focusDurationSeconds,
            })
          }
          clock={clock}
        />
      )}
      {section === 'history' && <HistoryView snapshot={snapshot} />}
      {section === 'roadmap' && (
        <RoadmapView
          snapshot={snapshot}
          onSave={(roadmap) => {
            patchSnapshot((current) => ({
              ...current,
              roadmaps: [roadmap, ...current.roadmaps.filter((item) => item.id !== roadmap.id)],
            }));
            void syncRoadmap(roadmap);
          }}
        />
      )}
      {section === 'browser' && (
        <BrowserWorkspace
          tabs={snapshot.browserTabs}
          onTabsChange={(tabs) => patchSnapshot((current) => ({ ...current, browserTabs: tabs }))}
          onSaveAsTask={(tab) => {
            saveTask({
              title: tab.title,
              description: tab.url,
              domainId: 'reading',
              executionMode: 'reading',
              timeZoneId: snapshot.settings.homeTimeZoneId,
            });
            setSection('tasks');
          }}
        />
      )}
      {section === 'settings' && (
        <SettingsView
          snapshot={snapshot}
          session={session}
          authEmail={authEmail}
          authPassword={authPassword}
          authBusy={authBusy}
          authError={authError}
          onAuthEmail={setAuthEmail}
          onAuthPassword={setAuthPassword}
          onSignIn={signInWithPassword}
          onGoogle={signInWithGoogle}
          onSignOut={() => supabase.auth.signOut()}
          onRefresh={() => void refreshFromRemote()}
          onSettings={(settings) => {
            patchSnapshot((current) => ({ ...current, settings }));
            void syncSettings(settings);
          }}
        />
      )}
    </main>
  );

  return (
    <div className={`app theme-${snapshot.settings.theme}`}>
      <Sidebar section={section} onSection={setSection} snapshot={snapshot} />
      {content}
      {quickNoteOpen && (
        <QuickNoteDialog
          roadmaps={snapshot.roadmaps}
          onClose={() => setQuickNoteOpen(false)}
          onSave={saveQuickNote}
        />
      )}
      {taskEditorOpen && (
        <TaskEditor
          task={editingTask}
          snapshot={snapshot}
          onClose={() => {
            setTaskEditorOpen(false);
            setEditingTask(undefined);
          }}
          onSave={saveTask}
        />
      )}
    </div>
  );
}

function SplashScreen({ theme }: { theme: TaskMasterSnapshot['settings']['theme'] }) {
  return (
    <main className={`auth-shell theme-${theme}`}>
      <section className="auth-card compact">
        <img src={assetUrl('assets/branding/logo-dark.png')} alt="TaskMaster Pro" />
        <Loader2 className="spin" size={28} />
        <p>Opening your workspace...</p>
      </section>
    </main>
  );
}

function AuthScreen({
  theme,
  mode,
  email,
  password,
  displayName,
  username,
  busy,
  error,
  onMode,
  onEmail,
  onPassword,
  onDisplayName,
  onUsername,
  onSubmit,
  onGoogle,
}: {
  theme: TaskMasterSnapshot['settings']['theme'];
  mode: 'sign-in' | 'create-account';
  email: string;
  password: string;
  displayName: string;
  username: string;
  busy: boolean;
  error?: string;
  onMode: (mode: 'sign-in' | 'create-account') => void;
  onEmail: (value: string) => void;
  onPassword: (value: string) => void;
  onDisplayName: (value: string) => void;
  onUsername: (value: string) => void;
  onSubmit: () => void;
  onGoogle: () => void;
}) {
  const creating = mode === 'create-account';
  return (
    <main className={`auth-shell theme-${theme}`}>
      <section className="auth-card">
        <div>
          <img className="auth-logo" src={assetUrl('assets/branding/logo-dark.png')} alt="TaskMaster Pro" />
          <p className="eyebrow">Your planning workspace</p>
          <h1>{creating ? 'Create your TaskMaster Pro account' : 'Welcome back'}</h1>
          <p className="quiet">
            Plan your tasks, run focused work sessions, keep your data synced, and continue working offline after
            sign-in.
          </p>
        </div>
        <div className="segmented">
          <button className={mode === 'sign-in' ? 'active' : ''} onClick={() => onMode('sign-in')} type="button">
            Sign in
          </button>
          <button
            className={mode === 'create-account' ? 'active' : ''}
            onClick={() => onMode('create-account')}
            type="button"
          >
            Create account
          </button>
        </div>
        {creating && (
          <div className="form-grid">
            <label>
              Display name
              <input value={displayName} onChange={(event) => onDisplayName(event.target.value)} placeholder="Your name" />
            </label>
            <label>
              Username
              <input value={username} onChange={(event) => onUsername(event.target.value)} placeholder="username" />
            </label>
          </div>
        )}
        <label>
          Email
          <input value={email} onChange={(event) => onEmail(event.target.value)} placeholder="you@example.com" type="email" />
        </label>
        <label>
          Password
          <input value={password} onChange={(event) => onPassword(event.target.value)} placeholder="Your password" type="password" />
        </label>
        {error && <p className="error-text">{error}</p>}
        <button className="primary-btn full" disabled={busy || !email || !password} onClick={onSubmit} type="button">
          {busy ? <Loader2 className="spin" size={18} /> : <LogIn size={18} />}
          {creating ? 'Create account' : 'Sign in'}
        </button>
        <button className="ghost-btn full" disabled={busy} onClick={onGoogle} type="button">
          <Globe2 size={18} />
          Continue with Google
        </button>
      </section>
      <section className="auth-card install-auth-card">
        <h2>Install TaskMaster Pro</h2>
        <p className="quiet">Use the same account on Windows, Android, and the web app.</p>
        <div className="release-grid">
          {releaseDownloads.map((item) => {
            const Icon = item.icon;
            return (
              <a className="release-card" href={item.href} key={item.href} target="_blank" rel="noreferrer">
                <span className="release-icon">
                  <Icon size={20} />
                </span>
                <span>
                  <strong>{item.label}</strong>
                  <small>{item.detail}</small>
                </span>
                <Download size={18} />
              </a>
            );
          })}
        </div>
      </section>
    </main>
  );
}

function Sidebar({
  section,
  onSection,
  snapshot,
}: {
  section: AppSection;
  onSection: (section: AppSection) => void;
  snapshot: TaskMasterSnapshot;
}) {
  return (
    <aside className="sidebar">
      <img className="brand-logo" src={assetUrl('assets/branding/logo-dark.png')} alt="TaskMaster Pro" />
      <div className="profile-chip">
        <div className="avatar">{initials(snapshot.settings.displayName)}</div>
        <strong>{snapshot.settings.displayName || 'Your workspace'}</strong>
        <span>{snapshot.settings.username ? `@${snapshot.settings.username}` : 'Signed in'}</span>
      </div>
      <nav className="nav">
        {sections.map((item) => {
          const Icon = item.icon;
          return (
            <button
              key={item.id}
              aria-label={item.label}
              data-testid={`nav-${item.id}`}
              className={section === item.id ? 'active' : ''}
              onClick={() => onSection(item.id)}
              type="button"
            >
              <Icon size={20} />
              <span>{item.label}</span>
            </button>
          );
        })}
      </nav>
    </aside>
  );
}

function TopBar({
  section,
  onQuickNote,
  onAddTask,
  syncLabel,
}: {
  section: AppSection;
  onQuickNote: () => void;
  onAddTask: () => void;
  syncLabel: string;
}) {
  return (
    <header className="topbar">
      <div>
        <p className="eyebrow">TaskMaster Pro</p>
        <h1>{labelForSection(section)}</h1>
      </div>
      <div className="toolbar">
        <span className="sync-pill">
          <RefreshCw size={14} />
          {syncLabel}
        </span>
        <button
          className="ghost-btn quick-note-action"
          aria-label="Quick note"
          onClick={onQuickNote}
          type="button"
        >
          <FilePlus2 size={18} />
          <span>Quick note</span>
        </button>
        <button className="primary-btn" onClick={onAddTask} type="button">
          <Plus size={18} />
          Task
        </button>
      </div>
    </header>
  );
}

function Dashboard({
  snapshot,
  onOpenTasks,
  onOpenRoadmap,
  onStartFocus,
}: {
  snapshot: TaskMasterSnapshot;
  onOpenTasks: () => void;
  onOpenRoadmap: () => void;
  onStartFocus: (taskId: string) => void;
}) {
  const today = new Date().toISOString().slice(0, 10);
  const todayTasks = snapshot.tasks.filter((task) => task.plannedLocalDate === today || task.status === 'in_progress');
  const completed = snapshot.tasks.filter((task) => task.status === 'completed').length;
  const activeRoadmap = snapshot.roadmaps.find((roadmap) => roadmap.status === 'active') ?? snapshot.roadmaps[0];
  return (
    <section className="page" data-testid="dashboard-page">
      <div className="hero-panel">
        <div>
          <p className="eyebrow">Today</p>
          <h2>{todayTasks.length ? 'Your plan is ready.' : 'Start by adding what matters today.'}</h2>
          <p>
            {todayTasks.length
              ? `${todayTasks.length} planned item${todayTasks.length === 1 ? '' : 's'} for today.`
              : 'Create a task, capture a quick note, or open a roadmap when you are ready.'}
            {completed ? ` ${completed} task${completed === 1 ? '' : 's'} completed so far.` : ''}
          </p>
        </div>
        <button className="primary-btn" onClick={onOpenTasks} type="button">
          <ChevronRight size={18} />
          Open tasks
        </button>
      </div>
      <div className="metric-grid">
        <Metric title="Focus duration" value={formatDuration(snapshot.settings.focusDurationSeconds)} icon={Clock3} />
        <Metric title="Quick notes" value={String(snapshot.quickNotes.length)} icon={FilePlus2} />
        <Metric title="Active tasks" value={String(snapshot.tasks.filter((task) => task.status !== 'completed').length)} icon={ListChecks} />
        <Metric title="Roadmaps" value={String(snapshot.roadmaps.length)} icon={Map} />
      </div>
      <div className="split-grid">
        <section className="panel">
          <div className="panel-title">
            <h3>Next tasks</h3>
            <button className="text-btn" onClick={onOpenTasks} type="button">Manage</button>
          </div>
          <div className="list">
            {snapshot.tasks.length === 0 && <EmptyState text="No tasks yet. Add your first task when you are ready." />}
            {snapshot.tasks.slice(0, 5).map((task) => (
              <TaskRow key={task.id} task={task} onStart={() => onStartFocus(task.id)} />
            ))}
          </div>
        </section>
        <section className="panel">
          <div className="panel-title">
            <h3>Roadmap pulse</h3>
            <button className="text-btn" onClick={onOpenRoadmap} type="button">Open</button>
          </div>
          {activeRoadmap ? <RoadmapSummary roadmap={activeRoadmap} tasks={snapshot.tasks} /> : <EmptyState text="No roadmap yet." />}
        </section>
      </div>
    </section>
  );
}

function Tasks({
  snapshot,
  onAdd,
  onEdit,
  onStart,
  onUpdate,
}: {
  snapshot: TaskMasterSnapshot;
  onAdd: () => void;
  onEdit: (task: TaskItem) => void;
  onStart: (taskId: string) => void;
  onUpdate: (task: TaskItem) => void;
}) {
  const [query, setQuery] = useState('');
  const filtered = snapshot.tasks.filter((task) => task.title.toLowerCase().includes(query.toLowerCase()));
  const activeTask = snapshot.tasks.find((task) => task.id === snapshot.runtime.activeTaskId);
  return (
    <section className="page" data-testid="tasks-page">
      <div className="page-tools">
        <label className="search-field">
          <Search size={18} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search tasks" />
        </label>
        <button className="primary-btn" onClick={onAdd} type="button">
          <Plus size={18} />
          New task
        </button>
      </div>
      <ActiveTaskPanel snapshot={snapshot} task={activeTask} onStart={onStart} onEdit={onEdit} />
      <div className="task-board">
        {(['todo', 'in_progress', 'completed'] as const).map((status) => (
          <section className="panel board-column" key={status}>
            <h3>{statusLabel(status)}</h3>
            {filtered.filter((task) => task.status === status).length === 0 && (
              <EmptyState text={status === 'todo' ? 'No planned tasks here yet.' : 'Nothing in this column.'} />
            )}
            {filtered
              .filter((task) => task.status === status)
              .map((rawTask) => {
                const task = normalizeTask(rawTask);
                const stats = summarizeTaskActivity(snapshot, task);
                return (
                  <article className="task-card" key={task.id}>
                  <div className="task-card-head">
                    <span className={`priority priority-${task.priority}`}>{task.priority}</span>
                    <button className="icon-btn" onClick={() => onEdit(task)} type="button" aria-label="Edit task">
                      <MoreHorizontal size={18} />
                    </button>
                  </div>
                  <h4>{task.title}</h4>
                  <p>{task.description || 'No description'}</p>
                  <div className="task-meta-row">
                    <span>
                      <Paperclip size={14} />
                      {task.resources.length} resources
                    </span>
                    <span>
                      <AppWindow size={14} />
                      {task.focusProfile.relatedApplications.length} related apps
                    </span>
                    <span>
                      <Target size={14} />
                      {stats.focusScore}% focus
                    </span>
                  </div>
                  {task.focusProfile.expectedActivity && (
                    <p className="focus-intent">{task.focusProfile.expectedActivity}</p>
                  )}
                  <Progress value={task.manualProgress} />
                  <div className="card-actions">
                    <button className="ghost-btn" onClick={() => onStart(task.id)} type="button">
                      <Play size={16} />
                      Focus
                    </button>
                    <button
                      className="ghost-btn"
                      onClick={() =>
                        onUpdate({
                          ...task,
                          status: task.status === 'completed' ? 'todo' : 'completed',
                          manualProgress: task.status === 'completed' ? 0 : 100,
                          updatedAt: nowIso(),
                        })
                      }
                      type="button"
                    >
                      <Check size={16} />
                      {task.status === 'completed' ? 'Reopen' : 'Done'}
                    </button>
                  </div>
                </article>
                );
              })}
          </section>
        ))}
      </div>
    </section>
  );
}

function ActiveTaskPanel({
  snapshot,
  task,
  onStart,
  onEdit,
}: {
  snapshot: TaskMasterSnapshot;
  task?: TaskItem;
  onStart: (taskId: string) => void;
  onEdit: (task: TaskItem) => void;
}) {
  if (!task) {
    const nextTask = snapshot.tasks.find((item) => item.status !== 'completed');
    return (
      <section className="panel active-task-panel">
        <div>
          <p className="eyebrow">Active work</p>
          <h3>No task is running</h3>
          <p className="quiet">Start a task to track focused work, related apps, resources, and interruptions.</p>
        </div>
        {nextTask && (
          <button className="primary-btn" onClick={() => onStart(nextTask.id)} type="button">
            <Play size={18} />
            Start next task
          </button>
        )}
      </section>
    );
  }

  const normalized = normalizeTask(task);
  const stats = summarizeTaskActivity(snapshot, normalized);
  const latestActivity = snapshot.activityIntervals.find((interval) => interval.taskId === task.id);
  return (
    <section className="panel active-task-panel">
      <div>
        <p className="eyebrow">Active work</p>
        <h3>{task.title}</h3>
        <p className="quiet">{normalized.focusProfile.expectedActivity}</p>
        {latestActivity && (
          <p className="quiet">
            Current device context: {latestActivity.applicationName || 'TaskMaster Pro'}
            {latestActivity.windowTitle ? ` - ${latestActivity.windowTitle}` : ''}
          </p>
        )}
      </div>
      <div className="activity-summary">
        <Metric title="Active captured" value={formatDuration(stats.totalActiveSeconds)} icon={Activity} />
        <Metric title="Focused" value={formatDuration(stats.focusedSeconds)} icon={CheckCheck} />
        <Metric title="Other context" value={formatDuration(stats.neutralSeconds + stats.distractingSeconds)} icon={Gauge} />
        <Metric title="Focus score" value={`${stats.focusScore}%`} icon={Target} />
      </div>
      <div className="toolbar">
        <button className="ghost-btn" onClick={() => onEdit(normalized)} type="button">
          <Paperclip size={16} />
          Add resources/apps
        </button>
      </div>
    </section>
  );
}

function Pomodoro({
  snapshot,
  activeTask,
  onStart,
  onTransition,
  onFinishTask,
  onStartBreak,
  onContinueWorking,
  clock,
}: {
  snapshot: TaskMasterSnapshot;
  activeTask?: TaskItem;
  onStart: (taskId: string) => void;
  onTransition: (state: RuntimeState['state']) => void;
  onFinishTask: () => void;
  onStartBreak: () => void;
  onContinueWorking: () => void;
  clock: number;
}) {
  const runtime = snapshot.runtime;
  const remaining = runtimeRemaining(runtime, new Date(clock));
  const selectable = snapshot.tasks.filter((task) => task.status !== 'completed');
  const [selectedTaskId, setSelectedTaskId] = useState(activeTask?.id ?? selectable[0]?.id ?? '');
  const selectedTask = selectable.find((task) => task.id === selectedTaskId) ?? activeTask ?? selectable[0];
  return (
    <section className="page pomodoro-page" data-testid="pomodoro-page">
      <section className="timer-panel">
        <p className="eyebrow">Standalone Pomodoro</p>
        <h2>{activeTask?.title ?? 'Focus timer'}</h2>
        <div className="timer-readout">{formatClock(remaining)}</div>
        <p className="state-label">{runtime.state.replaceAll('_', ' ')}</p>
        {!runtime.state.endsWith('_running') && (
          <label className="timer-task-select">
            Link this focus to a task
            <select value={selectedTask?.id ?? ''} onChange={(event) => setSelectedTaskId(event.target.value)}>
              {selectable.length === 0 && <option value="">Create a task first</option>}
              {selectable.map((task) => (
                <option key={task.id} value={task.id}>
                  {task.title}
                </option>
              ))}
            </select>
          </label>
        )}
        <div className="timer-actions">
          {(runtime.state === 'idle' || runtime.state === 'focus_ready') && selectedTask && (
            <button className="primary-btn" onClick={() => onStart(selectedTask.id)} type="button">
              <CirclePlay size={18} />
              Start focus
            </button>
          )}
          {runtime.state === 'focus_running' && (
            <button className="ghost-btn" onClick={() => onTransition('focus_paused')} type="button">
              <Pause size={18} />
              Pause
            </button>
          )}
          {runtime.state === 'focus_paused' && (
            <button className="primary-btn" onClick={() => onTransition('focus_running')} type="button">
              <Play size={18} />
              Resume
            </button>
          )}
          {runtime.state === 'focus_completed_waiting' && (
            <>
              <button className="primary-btn" onClick={onStartBreak} type="button">Start break</button>
              <button className="ghost-btn" onClick={onContinueWorking} type="button">Continue working</button>
              <button className="ghost-btn" onClick={onFinishTask} type="button">Finish task</button>
            </>
          )}
          {runtime.state === 'break_running' && (
            <button className="ghost-btn" onClick={() => onTransition('break_paused')} type="button">
              <CirclePause size={18} />
              Pause break
            </button>
          )}
          {runtime.state === 'break_paused' && (
            <button className="primary-btn" onClick={() => onTransition('break_running')} type="button">
              Resume break
            </button>
          )}
          {runtime.state === 'break_completed_waiting' && (
            <>
              <button className="primary-btn" onClick={onContinueWorking} type="button">Start focus</button>
              <button className="ghost-btn" onClick={onFinishTask} type="button">Finish task</button>
            </>
          )}
          {runtime.state !== 'idle' && runtime.state !== 'focus_ready' && (
            <button className="danger-btn" onClick={onFinishTask} type="button">
              <Square size={16} />
              Stop
            </button>
          )}
        </div>
      </section>
      <section className="panel">
        <h3>How this timer works</h3>
        <p className="quiet">
          Pomodoro is only the timer. Start and manage task resources, related applications, checklists, and activity
          evidence from the Tasks page.
        </p>
        <div className="list compact-list">
          <span>Focus stops at zero and waits for your next action.</span>
          <span>Breaks do not start automatically unless you turn that on later.</span>
          <span>Actual duration and transition reasons are preserved in session history.</span>
        </div>
      </section>
    </section>
  );
}

function HistoryView({ snapshot }: { snapshot: TaskMasterSnapshot }) {
  return (
    <section className="page" data-testid="history-page">
      <div className="panel">
        <h3>Activity history</h3>
        {snapshot.sessions.length === 0 ? (
          <EmptyState text="No completed focus or break segments yet." />
        ) : (
          <div className="list">
            {snapshot.sessions.map((session) => (
              <div className="history-row" key={session.id}>
                <History size={18} />
                <div>
                  <strong>{session.taskTitle}</strong>
                  <span>
                    {session.segmentType.replaceAll('_', ' ')} · {formatDuration(session.activeSeconds)}
                  </span>
                </div>
                <time>{new Date(session.startedAtUtc).toLocaleString()}</time>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function RoadmapView({
  snapshot,
  onSave,
}: {
  snapshot: TaskMasterSnapshot;
  onSave: (roadmap: RoadmapPlan) => void;
}) {
  const [draft, setDraft] = useState('');
  function addRoadmap() {
    if (!draft.trim()) return;
    const createdAt = nowIso();
    onSave({
      id: createId('roadmap'),
      title: draft.trim(),
      description: '',
      goal: draft.trim(),
      status: 'active',
      progressMethod: 'linked_tasks',
      manualProgress: 0,
      phases: [],
      createdAt,
      updatedAt: createdAt,
    });
    setDraft('');
  }
  return (
    <section className="page" data-testid="roadmap-page">
      <div className="page-tools">
        <label className="search-field">
          <Map size={18} />
          <input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="New roadmap title" />
        </label>
        <button className="primary-btn" onClick={addRoadmap} type="button">
          <Plus size={18} />
          Roadmap
        </button>
      </div>
      <div className="roadmap-grid">
        {snapshot.roadmaps.map((roadmap) => (
          <section className="panel" key={roadmap.id}>
            <RoadmapSummary roadmap={roadmap} tasks={snapshot.tasks} />
            <div className="phase-list">
              {roadmap.phases.map((phase) => (
                <div className="phase-row" key={phase.id}>
                  <span>{phase.phaseOrder}</span>
                  <div>
                    <strong>{phase.title}</strong>
                    <p>{phase.description}</p>
                  </div>
                  <span className={`status status-${phase.status}`}>{phase.status.replaceAll('_', ' ')}</span>
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
    </section>
  );
}

function BrowserWorkspace({
  tabs,
  onTabsChange,
  onSaveAsTask,
}: {
  tabs: BrowserTabState[];
  onTabsChange: (tabs: BrowserTabState[]) => void;
  onSaveAsTask: (tab: BrowserTabState) => void;
}) {
  const [activeId, setActiveId] = useState(tabs[0]?.id);
  const [address, setAddress] = useState('');
  const active = tabs.find((tab) => tab.id === activeId) ?? tabs[0];
  useEffect(() => {
    setAddress(active?.url ?? '');
  }, [active?.url]);

  function addTab(raw: string) {
    const url = normalizeBrowserInput(raw);
    const tab: BrowserTabState = {
      id: createId('tab'),
      url,
      title: titleForUrl(url),
      pinned: false,
      lastOpenedAt: nowIso(),
    };
    onTabsChange([...tabs, tab]);
    setActiveId(tab.id);
  }

  function openExternal(tab: BrowserTabState) {
    window.open(tab.url, '_blank', 'noopener,noreferrer');
  }

  return (
    <section className="page browser-page" data-testid="browser-page">
      <div className="browser-shell" data-testid="browser-shell">
        <div className="browser-tabs">
          {tabs.map((tab) => (
            <button
              className={tab.id === active?.id ? 'active' : ''}
              key={tab.id}
              onClick={() => setActiveId(tab.id)}
              type="button"
            >
              <Globe2 size={14} />
              {tab.title}
            </button>
          ))}
          <button className="icon-btn" onClick={() => addTab('https://www.google.com')} type="button" aria-label="New tab">
            <Plus size={16} />
          </button>
        </div>
        <form
          className="address-bar"
          onSubmit={(event) => {
            event.preventDefault();
            if (active) {
              const url = normalizeBrowserInput(address);
              onTabsChange(tabs.map((tab) => (tab.id === active.id ? { ...tab, url, title: titleForUrl(url) } : tab)));
            } else {
              addTab(address);
            }
          }}
        >
          <Search size={18} />
          <input value={address} onChange={(event) => setAddress(event.target.value)} placeholder="Search Google or enter a URL" />
          <button className="primary-btn" type="submit">Go</button>
        </form>
        {active ? (
          <div className="browser-content">
            <div className="browser-placeholder">
              <Globe2 size={42} />
              <h2>{active.title}</h2>
              <p>{active.url}</p>
              <p className="quiet">
                This rebuild stores tabs, bookmarks, task links, and browsing metadata in app state. External pages open in the
                browser shell/system browser instead of a hidden native view, so other pages cannot be covered by an old surface.
              </p>
              <div className="toolbar center">
                <button className="primary-btn" onClick={() => openExternal(active)} type="button">
                  <ExternalLink size={18} />
                  Open page
                </button>
                <button className="ghost-btn" onClick={() => onSaveAsTask(active)} type="button">
                  <LinkIcon size={18} />
                  Save as task resource
                </button>
                <button
                  className="ghost-btn"
                  onClick={() => onTabsChange(tabs.map((tab) => (tab.id === active.id ? { ...tab, pinned: !tab.pinned } : tab)))}
                  type="button"
                >
                  <Bell size={18} />
                  {active.pinned ? 'Unpin' : 'Pin'}
                </button>
              </div>
            </div>
          </div>
        ) : (
          <EmptyState text="No browser tabs are open." />
        )}
      </div>
    </section>
  );
}

function SettingsView({
  snapshot,
  session,
  authEmail,
  authPassword,
  authBusy,
  authError,
  onAuthEmail,
  onAuthPassword,
  onSignIn,
  onGoogle,
  onSignOut,
  onRefresh,
  onSettings,
}: {
  snapshot: TaskMasterSnapshot;
  session: Session | null;
  authEmail: string;
  authPassword: string;
  authBusy: boolean;
  authError?: string;
  onAuthEmail: (value: string) => void;
  onAuthPassword: (value: string) => void;
  onSignIn: () => void;
  onGoogle: () => void;
  onSignOut: () => void;
  onRefresh: () => void;
  onSettings: (settings: TaskMasterSnapshot['settings']) => void;
}) {
  const settings = snapshot.settings;
  const update = (patch: Partial<typeof settings>) => onSettings({ ...settings, ...patch });
  return (
    <section className="page settings-page" data-testid="settings-page">
      <div className="settings-grid">
        <section className="panel">
          <h3>Account and sync</h3>
          {session ? (
            <div className="account-box">
              <User size={22} />
              <div>
                <strong>{session.user.email}</strong>
                <span>Your account is connected and ready to sync.</span>
                <span>{publicProjectLabel()}</span>
              </div>
              <button className="ghost-btn" onClick={onRefresh} type="button">
                <RefreshCw size={16} />
                Refresh
              </button>
              <button className="danger-btn" onClick={onSignOut} type="button">
                <LogOut size={16} />
                Log out
              </button>
            </div>
          ) : (
            <div className="auth-box">
              <label>
                Email
                <input value={authEmail} onChange={(event) => onAuthEmail(event.target.value)} type="email" />
              </label>
              <label>
                Password
                <input value={authPassword} onChange={(event) => onAuthPassword(event.target.value)} type="password" />
              </label>
              {authError && <p className="error-text">{authError}</p>}
              <div className="toolbar">
                <button className="primary-btn" disabled={authBusy} onClick={onSignIn} type="button">
                  {authBusy ? <Loader2 className="spin" size={16} /> : <LogIn size={16} />}
                  Sign in
                </button>
                <button className="ghost-btn" disabled={authBusy} onClick={onGoogle} type="button">
                  Google
                </button>
              </div>
            </div>
          )}
        </section>
        <section className="panel">
          <h3>Profile</h3>
          <div className="form-grid compact">
            <label>
              Display name
              <input value={settings.displayName} onChange={(event) => update({ displayName: event.target.value })} />
            </label>
            <label>
              Username
              <input value={settings.username} onChange={(event) => update({ username: event.target.value })} />
            </label>
            <label>
              Theme
              <select value={settings.theme} onChange={(event) => update({ theme: event.target.value as typeof settings.theme })}>
                <option value="dark_blue">Dark blue</option>
                <option value="black_gold">Black gold</option>
                <option value="light">Light</option>
              </select>
            </label>
            <label>
              Home time zone
              <select value={settings.homeTimeZoneId} onChange={(event) => update({ homeTimeZoneId: event.target.value })}>
                {commonZones.map((zone) => (
                  <option value={zone} key={zone}>
                    {zone}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </section>
        <section className="panel">
          <h3>Schedule and availability</h3>
          <div className="form-grid compact">
            <TimeInput label="Wake-up time" value={settings.wakeUpTime} onChange={(wakeUpTime) => update({ wakeUpTime })} />
            <TimeInput label="Bedtime" value={settings.bedtime} onChange={(bedtime) => update({ bedtime })} />
            <TimeInput label="Work start" value={settings.workStartTime} onChange={(workStartTime) => update({ workStartTime })} />
            <TimeInput label="Work end" value={settings.workEndTime} onChange={(workEndTime) => update({ workEndTime })} />
            <NumberInput
              label="Focus minutes"
              value={settings.focusDurationSeconds / 60}
              onChange={(minutes) => update({ focusDurationSeconds: minutes * 60 })}
            />
            <NumberInput
              label="Break minutes"
              value={settings.shortBreakDurationSeconds / 60}
              onChange={(minutes) => update({ shortBreakDurationSeconds: minutes * 60 })}
            />
            <NumberInput
              label="Idle threshold seconds"
              value={settings.idleThresholdSeconds}
              onChange={(idleThresholdSeconds) => update({ idleThresholdSeconds })}
            />
          </div>
        </section>
        <section className="panel">
          <h3>Browser and privacy</h3>
          <Toggle label="Sync browser tabs and URLs" value={settings.browserSyncEnabled} onChange={(browserSyncEnabled) => update({ browserSyncEnabled })} />
          <Toggle label="Sync encrypted password vault" value={settings.passwordSyncEnabled} onChange={(passwordSyncEnabled) => update({ passwordSyncEnabled })} />
          <Toggle label="Sync health data" value={settings.healthSyncEnabled} onChange={(healthSyncEnabled) => update({ healthSyncEnabled })} />
          <Toggle label="Sync cycle data" value={settings.cycleSyncEnabled} onChange={(cycleSyncEnabled) => update({ cycleSyncEnabled })} />
          <p className="quiet">Website sessions and cookies stay on this device. Passwords require a separate encrypted vault.</p>
          <details className="diagnostics-box">
            <summary>Diagnostics</summary>
            <p>Supabase URL: {supabaseUrl}</p>
            <p>Local rows: {snapshot.tasks.length} tasks, {snapshot.quickNotes.length} notes.</p>
            {snapshot.syncError && <p className="error-text">Last sync error: {snapshot.syncError}</p>}
          </details>
        </section>
        <section className="panel">
          <h3>Notification sounds</h3>
          <p className="quiet">Preview the TaskMaster sounds packaged from the media folder.</p>
          <div className="sound-grid">
            {[
              ['focusCompleted', 'Focus alarm'],
              ['breakCompleted', 'Break alarm'],
              ['taskReminder', 'Task reminder'],
              ['taskOverdue', 'Overdue warning'],
              ['dailyCoaching', 'Daily coaching'],
              ['criticalAlarm', 'Critical alarm'],
            ].map(([key, label]) => (
              <button
                className="ghost-btn"
                key={key}
                onClick={() => void platformServices.notifications.playPreview(key)}
                type="button"
              >
                <Bell size={16} />
                {label}
              </button>
            ))}
          </div>
        </section>
      </div>
    </section>
  );
}

function QuickNoteDialog({
  roadmaps,
  onClose,
  onSave,
}: {
  roadmaps: RoadmapPlan[];
  onClose: () => void;
  onSave: (note: Omit<QuickNote, 'id' | 'createdAt' | 'updatedAt'>, convert: boolean) => void;
}) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [details, setDetails] = useState('');
  const [roadmapId, setRoadmapId] = useState('');
  const [saving, setSaving] = useState(false);
  function submit(convert: boolean) {
    if (saving || (!title.trim() && !body.trim())) return;
    setSaving(true);
    onSave({ title: title.trim(), body: body.trim(), details: details.trim(), roadmapId: roadmapId || undefined }, convert);
  }
  return (
    <div className="modal-backdrop" role="presentation">
      <section className="modal-sheet" role="dialog" aria-modal="true" aria-label="Quick note">
        <div className="panel-title">
          <h3>Quick note</h3>
          <button className="icon-btn" onClick={onClose} type="button" aria-label="Close">×</button>
        </div>
        <label>
          Title or note
          <input autoFocus value={title} onChange={(event) => setTitle(event.target.value)} />
        </label>
        <label>
          Details
          <textarea value={body} onChange={(event) => setBody(event.target.value)} />
        </label>
        <label>
          Optional extra context
          <textarea value={details} onChange={(event) => setDetails(event.target.value)} />
        </label>
        <label>
          Roadmap
          <select value={roadmapId} onChange={(event) => setRoadmapId(event.target.value)}>
            <option value="">Inbox / Quick Notes</option>
            {roadmaps.map((roadmap) => (
              <option key={roadmap.id} value={roadmap.id}>{roadmap.title}</option>
            ))}
          </select>
        </label>
        <div className="modal-actions">
          <button className="ghost-btn" onClick={onClose} type="button">Cancel</button>
          <button className="ghost-btn" disabled={saving} onClick={() => submit(false)} type="button">
            <Save size={16} />
            Save note
          </button>
          <button className="primary-btn" disabled={saving} onClick={() => submit(true)} type="button">
            <CheckCheck size={16} />
            Save and convert to task
          </button>
        </div>
      </section>
    </div>
  );
}

function TaskEditor({
  task,
  snapshot,
  onClose,
  onSave,
}: {
  task?: TaskItem;
  snapshot: TaskMasterSnapshot;
  onClose: () => void;
  onSave: (task: Partial<TaskItem>) => void;
}) {
  const [draft, setDraft] = useState<Partial<TaskItem>>(
    task ?? {
      title: '',
      description: '',
      domainId: 'work',
      executionMode: 'manual_completion',
      priority: 'normal',
      status: 'todo',
      plannedLocalDate: new Date().toISOString().slice(0, 10),
      timeZoneId: snapshot.settings.homeTimeZoneId,
      manualProgress: 0,
      remindersEnabled: false,
      tags: [],
      resources: [],
      focusProfile: defaultFocusProfile(''),
    },
  );
  const [resourceName, setResourceName] = useState('');
  const [resourceUrl, setResourceUrl] = useState('');
  const [appName, setAppName] = useState('');
  const [processName, setProcessName] = useState('');
  const selectedRoadmap = snapshot.roadmaps.find((roadmap) => roadmap.id === draft.roadmapId);
  const resources = draft.resources ?? [];
  const focusProfile = {
    ...defaultFocusProfile(draft.title),
    ...(draft.focusProfile ?? {}),
    relatedApplications: draft.focusProfile?.relatedApplications ?? [],
    allowedDomains: draft.focusProfile?.allowedDomains ?? [],
    distractionDomains: draft.focusProfile?.distractionDomains ?? [],
  };
  function updateFocusProfile(patch: Partial<typeof focusProfile>) {
    setDraft({ ...draft, focusProfile: { ...focusProfile, ...patch } });
  }
  function addResource() {
    const name = resourceName.trim() || resourceUrl.trim();
    if (!name) return;
    setDraft({
      ...draft,
      resources: [
        ...resources,
        {
          id: createId('resource'),
          name,
          resourceType: resourceUrl.trim() ? 'web_page' : 'external_reference',
          url: resourceUrl.trim() || undefined,
          createdAt: nowIso(),
        },
      ],
    });
    setResourceName('');
    setResourceUrl('');
  }
  function addRelatedApp() {
    const name = appName.trim();
    if (!name) return;
    updateFocusProfile({
      relatedApplications: [
        ...focusProfile.relatedApplications,
        {
          id: createId('app'),
          applicationName: name,
          processName: processName.trim() || undefined,
          matchType: processName.trim() ? 'process' : 'application',
          expectedUse: 'primary_work',
        },
      ],
    });
    setAppName('');
    setProcessName('');
  }
  return (
    <div className="modal-backdrop" role="presentation">
      <section className="modal-sheet wide" role="dialog" aria-modal="true" aria-label="Task editor">
        <div className="panel-title">
          <h3>{task ? 'Edit task' : 'New task'}</h3>
          <button className="icon-btn" onClick={onClose} type="button" aria-label="Close">×</button>
        </div>
        <div className="form-grid">
          <label className="span-2">
            Title
            <input autoFocus value={draft.title ?? ''} onChange={(event) => setDraft({ ...draft, title: event.target.value })} />
          </label>
          <label className="span-2">
            Description
            <textarea value={draft.description ?? ''} onChange={(event) => setDraft({ ...draft, description: event.target.value })} />
          </label>
          <label>
            Domain
            <select value={draft.domainId} onChange={(event) => setDraft({ ...draft, domainId: event.target.value })}>
              {snapshot.domains.map((domain) => (
                <option value={domain.id} key={domain.id}>{domain.name}</option>
              ))}
            </select>
          </label>
          <label>
            Mode
            <select value={draft.executionMode} onChange={(event) => setDraft({ ...draft, executionMode: event.target.value as ExecutionMode })}>
              {executionModes.map((mode) => (
                <option key={mode} value={mode}>{mode.replaceAll('_', ' ')}</option>
              ))}
            </select>
          </label>
          <label>
            Priority
            <select value={draft.priority} onChange={(event) => setDraft({ ...draft, priority: event.target.value as Priority })}>
              {priorities.map((priority) => (
                <option key={priority} value={priority}>{priority}</option>
              ))}
            </select>
          </label>
          <label>
            Date
            <input type="date" value={draft.plannedLocalDate ?? ''} onChange={(event) => setDraft({ ...draft, plannedLocalDate: event.target.value })} />
          </label>
          <label>
            Time zone
            <select value={draft.timeZoneId} onChange={(event) => setDraft({ ...draft, timeZoneId: event.target.value })}>
              {commonZones.map((zone) => (
                <option value={zone} key={zone}>
                  {zoneOffsetLabel(zone)} {zone}
                </option>
              ))}
            </select>
          </label>
          <label>
            Roadmap
            <select
              value={draft.roadmapId ?? ''}
              onChange={(event) => setDraft({ ...draft, roadmapId: event.target.value || undefined, phaseId: undefined })}
            >
              <option value="">None</option>
              {snapshot.roadmaps.map((roadmap) => (
                <option key={roadmap.id} value={roadmap.id}>{roadmap.title}</option>
              ))}
            </select>
          </label>
          <label>
            Phase
            <select
              value={draft.phaseId ?? ''}
              onChange={(event) => setDraft({ ...draft, phaseId: event.target.value || undefined })}
              disabled={!selectedRoadmap}
            >
              <option value="">None</option>
              {selectedRoadmap?.phases.map((phase) => (
                <option key={phase.id} value={phase.id}>{phase.title}</option>
              ))}
            </select>
          </label>
          <label>
            Progress
            <input
              type="range"
              min="0"
              max="100"
              value={draft.manualProgress ?? 0}
              onChange={(event) => setDraft({ ...draft, manualProgress: Number(event.target.value) })}
            />
          </label>
          <Toggle label="Reminder enabled" value={draft.remindersEnabled ?? false} onChange={(remindersEnabled) => setDraft({ ...draft, remindersEnabled })} />
        </div>
        <section className="editor-section">
          <div className="panel-title">
            <h4>Focus expectations</h4>
          </div>
          <label>
            What should count as useful work for this task?
            <textarea
              value={focusProfile.expectedActivity}
              onChange={(event) => updateFocusProfile({ expectedActivity: event.target.value })}
              placeholder="Example: writing the proposal, reviewing the source PDF, or researching the selected topic"
            />
          </label>
        </section>
        <section className="editor-section">
          <div className="panel-title">
            <h4>Resources and attachments</h4>
            <span className="quiet">{resources.length} linked</span>
          </div>
          <div className="resource-add-row">
            <input value={resourceName} onChange={(event) => setResourceName(event.target.value)} placeholder="Resource name" />
            <input value={resourceUrl} onChange={(event) => setResourceUrl(event.target.value)} placeholder="URL or reference" />
            <button className="ghost-btn" onClick={addResource} type="button">
              <Paperclip size={16} />
              Add
            </button>
          </div>
          <label className="file-attach-row">
            Select local attachments
            <input
              multiple
              type="file"
              onChange={(event) => {
                const files = Array.from(event.target.files ?? []);
                if (!files.length) return;
                setDraft({
                  ...draft,
                  resources: [
                    ...resources,
                    ...files.map((file) => ({
                      id: createId('resource'),
                      name: file.name,
                      resourceType: 'local_file' as const,
                      notes: `${Math.round(file.size / 1024)} KB selected on this device`,
                      createdAt: nowIso(),
                    })),
                  ],
                });
                event.currentTarget.value = '';
              }}
            />
          </label>
          <div className="chip-list">
            {resources.map((resource) => (
              <span className="data-chip" key={resource.id}>
                <Paperclip size={13} />
                {resource.name}
                <button
                  aria-label={`Remove ${resource.name}`}
                  onClick={() => setDraft({ ...draft, resources: resources.filter((item) => item.id !== resource.id) })}
                  type="button"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        </section>
        <section className="editor-section">
          <div className="panel-title">
            <h4>Related applications</h4>
            <span className="quiet">{focusProfile.relatedApplications.length} linked</span>
          </div>
          <div className="resource-add-row">
            <input value={appName} onChange={(event) => setAppName(event.target.value)} placeholder="Application name" />
            <input value={processName} onChange={(event) => setProcessName(event.target.value)} placeholder="Process name, optional" />
            <button className="ghost-btn" onClick={addRelatedApp} type="button">
              <AppWindow size={16} />
              Add
            </button>
          </div>
          <div className="chip-list">
            {focusProfile.relatedApplications.map((app) => (
              <span className="data-chip" key={app.id}>
                <AppWindow size={13} />
                {app.applicationName}
                <button
                  aria-label={`Remove ${app.applicationName}`}
                  onClick={() =>
                    updateFocusProfile({
                      relatedApplications: focusProfile.relatedApplications.filter((item) => item.id !== app.id),
                    })
                  }
                  type="button"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        </section>
        <div className="modal-actions">
          <button className="ghost-btn" onClick={onClose} type="button">Cancel</button>
          <button className="primary-btn" onClick={() => onSave(draft)} type="button">
            <Save size={16} />
            Save task
          </button>
        </div>
      </section>
    </div>
  );
}

function TaskRow({ task, onStart }: { task: TaskItem; onStart: () => void }) {
  return (
    <div className="task-row">
      <div>
        <strong>{task.title}</strong>
        <span>{task.executionMode.replaceAll('_', ' ')} · {task.timeZoneId}</span>
      </div>
      <button className="icon-btn" onClick={onStart} type="button" aria-label={`Start ${task.title}`}>
        <Play size={17} />
      </button>
    </div>
  );
}

function RoadmapSummary({ roadmap, tasks }: { roadmap: RoadmapPlan; tasks: TaskItem[] }) {
  const linked = tasks.filter((task) => task.roadmapId === roadmap.id);
  const completed = linked.filter((task) => task.status === 'completed').length;
  const linkedProgress = linked.length ? Math.round((completed / linked.length) * 100) : roadmap.manualProgress;
  const phaseProgress = roadmap.phases.length
    ? Math.round((roadmap.phases.filter((phase) => phase.status === 'completed').length / roadmap.phases.length) * 100)
    : 0;
  const progress = Math.round(linked.length ? linkedProgress * 0.7 + phaseProgress * 0.3 : roadmap.manualProgress);
  return (
    <div className="roadmap-summary">
      <div className="panel-title">
        <div>
          <p className="eyebrow">{roadmap.status.replaceAll('_', ' ')}</p>
          <h3>{roadmap.title}</h3>
        </div>
        <strong>{progress}%</strong>
      </div>
      <Progress value={progress} />
      <dl className="explain-grid">
        <div><dt>Phases</dt><dd>{roadmap.phases.filter((phase) => phase.status === 'completed').length} / {roadmap.phases.length}</dd></div>
        <div><dt>Linked tasks</dt><dd>{completed} / {linked.length}</dd></div>
        <div><dt>Method</dt><dd>{roadmap.progressMethod.replaceAll('_', ' ')}</dd></div>
      </dl>
    </div>
  );
}

function Metric({ title, value, icon: Icon }: { title: string; value: string; icon: typeof Activity }) {
  return (
    <section className="metric">
      <Icon size={20} />
      <span>{title}</span>
      <strong>{value}</strong>
    </section>
  );
}

function Progress({ value }: { value: number }) {
  return (
    <div className="progress" aria-label={`Progress ${value}%`}>
      <span style={{ width: `${Math.min(100, Math.max(0, value))}%` }} />
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return <div className="empty-state">{text}</div>;
}

function Toggle({ label, value, onChange }: { label: string; value: boolean; onChange: (value: boolean) => void }) {
  return (
    <label className="toggle-row">
      <span>{label}</span>
      <input type="checkbox" checked={value} onChange={(event) => onChange(event.target.checked)} />
    </label>
  );
}

function TimeInput({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <label>
      {label}
      <input type="time" value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function NumberInput({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return (
    <label>
      {label}
      <input type="number" value={value} onChange={(event) => onChange(Number(event.target.value))} />
    </label>
  );
}

function normalizeBrowserInput(raw: string) {
  const value = raw.trim();
  if (!value) return 'https://www.google.com';
  if (value.includes(' ') || !value.includes('.')) {
    return `https://www.google.com/search?q=${encodeURIComponent(value)}`;
  }
  return value.includes('://') ? value : `https://${value}`;
}

function titleForUrl(url: string) {
  try {
    const parsed = new URL(url);
    if (parsed.hostname.includes('google') && parsed.pathname.includes('/search')) return 'Google search';
    return parsed.hostname.replace(/^www\./, '');
  } catch {
    return 'New tab';
  }
}

function zoneOffsetLabel(zone: string) {
  try {
    const parts = new Intl.DateTimeFormat('en', {
      timeZone: zone,
      timeZoneName: 'shortOffset',
    }).formatToParts(new Date());
    return parts.find((part) => part.type === 'timeZoneName')?.value.replace('GMT', 'UTC') ?? '(UTC)';
  } catch {
    return '(UTC)';
  }
}

function formatDuration(seconds: number) {
  const wholeSeconds = Math.max(0, Math.round(seconds));
  if (wholeSeconds < 60) return `${wholeSeconds}s`;
  const minutes = Math.floor(wholeSeconds / 60);
  const secondsRest = wholeSeconds % 60;
  if (minutes < 60) return secondsRest ? `${minutes}m ${secondsRest}s` : `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours}h ${rest}m` : `${hours}h`;
}

function formatClock(seconds: number) {
  const minutes = Math.floor(seconds / 60).toString().padStart(2, '0');
  const rest = Math.floor(seconds % 60).toString().padStart(2, '0');
  return `${minutes}:${rest}`;
}

function initials(name: string) {
  const value = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');
  return value || 'TM';
}

function summarizeTaskActivity(snapshot: TaskMasterSnapshot, task: TaskItem) {
  const intervals = snapshot.activityIntervals.filter((interval) => interval.taskId === task.id);
  const totalActiveSeconds = intervals.reduce((sum, interval) => sum + interval.activeSeconds, 0);
  const focusedSeconds = intervals
    .filter((interval) => interval.classification === 'focused' || interval.classification === 'research')
    .reduce((sum, interval) => sum + interval.activeSeconds, 0);
  const neutralSeconds = intervals
    .filter((interval) => interval.classification === 'neutral' || interval.classification === 'communication')
    .reduce((sum, interval) => sum + interval.activeSeconds, 0);
  const distractingSeconds = intervals
    .filter((interval) => interval.classification === 'distracting')
    .reduce((sum, interval) => sum + interval.activeSeconds, 0);
  return {
    totalActiveSeconds,
    focusedSeconds,
    neutralSeconds,
    distractingSeconds,
    focusScore: totalActiveSeconds ? Math.round((focusedSeconds / totalActiveSeconds) * 100) : 0,
  };
}

function classifyActivity(task: TaskItem, activity: CurrentActivity): ActivityInterval['classification'] {
  const normalized = normalizeTask(task);
  const appName = `${activity.applicationName ?? ''} ${activity.processName ?? ''}`.toLowerCase();
  const title = (activity.windowTitle ?? '').toLowerCase();
  if (activity.sourceType === 'taskmaster') return 'focused';
  const related = normalized.focusProfile.relatedApplications.some((app) => {
    const expectedApp = app.applicationName.toLowerCase();
    const expectedProcess = app.processName?.toLowerCase();
    return appName.includes(expectedApp) || Boolean(expectedProcess && appName.includes(expectedProcess));
  });
  if (related) return 'focused';
  const resourceHit = normalized.resources.some((resource) => {
    const name = resource.name.toLowerCase();
    const url = resource.url?.toLowerCase();
    return title.includes(name) || Boolean(url && title.includes(url));
  });
  if (resourceHit) return 'research';
  if (/(chat|mail|teams|slack|whatsapp|telegram|discord)/i.test(appName)) return 'communication';
  if (/(game|netflix|youtube|tiktok|instagram|facebook|xbox)/i.test(`${appName} ${title}`)) return 'distracting';
  return 'neutral';
}

function labelForSection(section: AppSection) {
  return sections.find((item) => item.id === section)?.label ?? 'Dashboard';
}

function statusLabel(status: TaskItem['status']) {
  return status.replaceAll('_', ' ');
}
