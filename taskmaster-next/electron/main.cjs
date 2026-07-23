const { app, BrowserWindow, ipcMain, Menu, nativeImage, shell, Tray } = require('electron');
const { execFile } = require('node:child_process');
const path = require('node:path');

const isDev = !app.isPackaged;
let mainWindow;
let tray;

function resourcePath(...segments) {
  return path.join(app.getAppPath(), 'resources', ...segments);
}

function createTray() {
  if (tray) return;
  const icon = nativeImage.createFromPath(resourcePath('icons', 'app-icon.ico'));
  tray = new Tray(icon);
  tray.setToolTip('TaskMaster Pro');
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Open TaskMaster Pro', click: () => showMainWindow() },
      { type: 'separator' },
      { label: 'Quit', click: () => app.quit() },
    ]),
  );
  tray.on('click', () => showMainWindow());
}

function showMainWindow() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    createWindow();
    return;
  }
  mainWindow.show();
  mainWindow.focus();
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    title: 'TaskMaster Pro',
    icon: resourcePath('icons', 'app-icon.ico'),
    backgroundColor: '#07111f',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  mainWindow = win;

  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  if (isDev) {
    win.loadURL('http://127.0.0.1:5173');
  } else {
    win.loadFile(path.join(__dirname, '../dist/index.html'));
  }
}

function readWindowsForegroundActivity() {
  return new Promise((resolve) => {
    if (process.platform !== 'win32') {
      resolve({
        sourceType: 'taskmaster',
        applicationName: 'TaskMaster Pro',
        processName: 'taskmaster',
        windowTitle: 'TaskMaster Pro',
      });
      return;
    }

    const script = `
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Win32Activity {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@
$handle = [Win32Activity]::GetForegroundWindow()
$builder = New-Object System.Text.StringBuilder 512
[void][Win32Activity]::GetWindowText($handle, $builder, $builder.Capacity)
$pidValue = 0
[void][Win32Activity]::GetWindowThreadProcessId($handle, [ref]$pidValue)
$process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
[pscustomobject]@{
  sourceType = "external_application"
  applicationName = if ($process) { $process.ProcessName } else { "Unknown application" }
  processName = if ($process) { $process.ProcessName } else { "" }
  windowTitle = $builder.ToString()
  capturedAt = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Compress
`;

    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      { timeout: 3000, windowsHide: true },
      (error, stdout) => {
        if (error || !stdout.trim()) {
          resolve({
            sourceType: 'external_application',
            applicationName: 'Unknown application',
            processName: '',
            windowTitle: '',
            capturedAt: new Date().toISOString(),
          });
          return;
        }
        try {
          resolve(JSON.parse(stdout));
        } catch {
          resolve({
            sourceType: 'external_application',
            applicationName: 'Unknown application',
            processName: '',
            windowTitle: '',
            capturedAt: new Date().toISOString(),
          });
        }
      },
    );
  });
}

ipcMain.handle('taskmaster:get-active-window', () => readWindowsForegroundActivity());

app.whenReady().then(() => {
  app.setAppUserModelId('com.yasserdiab.taskmasterpro');
  createWindow();
  createTray();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
