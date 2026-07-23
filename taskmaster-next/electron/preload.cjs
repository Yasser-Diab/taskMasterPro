const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('taskmasterShell', {
  platform: process.platform,
});
