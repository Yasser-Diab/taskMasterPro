const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('taskmasterShell', {
  platform: process.platform,
});

contextBridge.exposeInMainWorld('taskmasterPlatform', {
  getActiveWindow: () => ipcRenderer.invoke('taskmaster:get-active-window'),
});
