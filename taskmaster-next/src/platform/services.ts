export interface CurrentActivity {
  sourceType: 'taskmaster' | 'internal_browser' | 'external_application' | 'external_website' | 'document' | 'manual';
  applicationName?: string;
  processName?: string;
  windowTitle?: string;
  domain?: string;
  url?: string;
  capturedAt?: string;
}

export interface ActivityTrackingAdapter {
  currentActivity(): Promise<CurrentActivity>;
}

export interface NotificationAdapter {
  playPreview(soundKey: string): Promise<void>;
}

export interface PlatformServices {
  activityTracking: ActivityTrackingAdapter;
  notifications: NotificationAdapter;
}

declare global {
  interface Window {
    taskmasterPlatform?: {
      getActiveWindow?: () => Promise<CurrentActivity>;
    };
  }
}

const webActivityTracking: ActivityTrackingAdapter = {
  async currentActivity() {
    return {
      sourceType: 'taskmaster',
      applicationName: 'TaskMaster Pro',
      processName: 'taskmaster-web',
      windowTitle: document.title,
      capturedAt: new Date().toISOString(),
    };
  },
};

const electronActivityTracking: ActivityTrackingAdapter = {
  async currentActivity() {
    if (!window.taskmasterPlatform?.getActiveWindow) return webActivityTracking.currentActivity();
    const activity = await window.taskmasterPlatform.getActiveWindow();
    return {
      sourceType: activity.sourceType ?? 'external_application',
      applicationName: activity.applicationName,
      processName: activity.processName,
      windowTitle: activity.windowTitle,
      capturedAt: activity.capturedAt ?? new Date().toISOString(),
    };
  },
};

const webNotifications: NotificationAdapter = {
  async playPreview(soundKey) {
    const manifestResponse = await fetch(`${import.meta.env.BASE_URL}assets/media-manifest.json`);
    const manifest = await manifestResponse.json();
    const soundPath = manifest.sounds?.[soundKey] as string | undefined;
    if (!soundPath) return;
    const audio = new Audio(`${import.meta.env.BASE_URL}${soundPath}`);
    await audio.play();
  },
};

function detectPlatformServices(): PlatformServices {
  const isElectron = Boolean(window.taskmasterPlatform?.getActiveWindow);
  return {
    activityTracking: isElectron ? electronActivityTracking : webActivityTracking,
    notifications: webNotifications,
  };
}

export const platformServices = detectPlatformServices();
