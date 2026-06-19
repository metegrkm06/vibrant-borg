const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  togglePin: (isPinned) => ipcRenderer.send('toggle-pin', isPinned),
  getMediaSession: () => ipcRenderer.invoke('get-current-session'),
  mediaAction: (action) => ipcRenderer.send('media-action', action)
});
