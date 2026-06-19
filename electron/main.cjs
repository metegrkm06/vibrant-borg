const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const isDev = process.env.NODE_ENV === 'development';

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 750,
    minWidth: 800,
    minHeight: 600,
    frame: true, // Standard titlebar and borders
    transparent: false, // Disabled transparency for WebGL 3D rendering
    alwaysOnTop: false, // Standard window layering
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.cjs')
    },
  });

  if (isDev) {
    // In dev, load the vite dev server URL
    mainWindow.loadURL('http://localhost:5173');
  } else {
    // In production, load the built index.html
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
  }

  // Handle IPC for pinning/unpinning
  ipcMain.on('toggle-pin', (event, isPinned) => {
    mainWindow.setAlwaysOnTop(isPinned);
  });

  // Media Control IPC Handlers
  ipcMain.handle('get-current-session', async () => {
    try {
      const wmc = await import('win-media-control-enhanced');
      const session = await wmc.getCurrentSession();
      if (!session) return null;
      
      return {
        title: session.media.title,
        artist: session.media.artist,
        status: session.playback.status, // Playing, Paused, Stopped
        positionMs: session.playback.timeline.positionMs,
        endTimeMs: session.playback.timeline.endTimeMs,
        thumbnailDataUrl: session.media.thumbnailDataUrl // base64 image
      };
    } catch (e) {
      console.error('Error fetching media session:', e);
      return null;
    }
  });

  ipcMain.on('media-action', async (event, action) => {
    try {
      const wmc = await import('win-media-control-enhanced');
      if (action === 'play') await wmc.play();
      if (action === 'pause') await wmc.pause();
      if (action === 'togglePlayPause') await wmc.togglePlayPause();
      if (action === 'next') await wmc.next();
      if (action === 'previous') await wmc.previous();
    } catch (e) {
      console.error('Error executing media action:', e);
    }
  });
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
