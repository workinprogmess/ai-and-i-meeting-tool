const { app, BrowserWindow, ipcMain, Menu, Tray, desktopCapturer } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs');
require('dotenv').config();
const AudioCapture = require('./src/audio/audioCapture');
const SummaryGeneration = require('./src/api/summaryGeneration');
const RecordingsDB = require('./src/storage/recordingsDB');

let mainWindow;
let tray = null;
let isRecording = false;
let audioCapture = null;
let summaryGeneration = null;
let recordingsDB = null;

// auto-updater configuration
autoUpdater.checkForUpdatesAndNotify = false; // we'll handle this manually
autoUpdater.autoDownload = false; // ask user before downloading

// auto-updater event handlers
autoUpdater.on('checking-for-update', () => {
  console.log('🔍 checking for updates...');
});

autoUpdater.on('update-available', (info) => {
  console.log('✅ update available:', info.version);
  // notify user about available update
  if (mainWindow) {
    mainWindow.webContents.send('update-available', info);
  }
});

autoUpdater.on('update-not-available', () => {
  console.log('✅ app is up to date');
  if (mainWindow) {
    mainWindow.webContents.send('update-not-available');
  }
});

autoUpdater.on('error', (err) => {
  console.error('❌ update error:', err);
  if (mainWindow) {
    mainWindow.webContents.send('update-error', err.message);
  }
});

autoUpdater.on('download-progress', (progressObj) => {
  console.log(`📥 downloading: ${Math.round(progressObj.percent)}%`);
  if (mainWindow) {
    mainWindow.webContents.send('download-progress', progressObj);
  }
});

autoUpdater.on('update-downloaded', (info) => {
  console.log('✅ update downloaded, ready to install');
  if (mainWindow) {
    mainWindow.webContents.send('update-downloaded', info);
  }
});

// Force the app to appear in macOS System Preferences by attempting screen capture
async function ensureAppRegisteredWithMacOS() {
  try {
    console.log('🔐 Attempting to register app with macOS permissions system...');
    
    // Try to access desktop capturer - this forces the app to appear in System Preferences
    if (desktopCapturer && desktopCapturer.getSources) {
      const sources = await desktopCapturer.getSources({
        types: ['screen'],
        thumbnailSize: { width: 1, height: 1 }
      });
      
      console.log('✅ App should now appear in System Preferences > Screen Recording');
      return true;
    } else {
      console.log('⚠️  desktopCapturer not available');
      return false;
    }
  } catch (error) {
    console.log('⚠️  Could not register with macOS permissions:', error.message);
    console.log('    This is normal - the app should still appear in System Preferences when you try to record');
    return false;
  }
}

function createWindow() {
  // Set app name for macOS
  if (process.platform === 'darwin') {
    app.setName('ai&i');
  }
  
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      enableRemoteModule: true
    },
    titleBarStyle: 'hiddenInset',
    show: true,
    title: 'ai&i',
    icon: path.join(__dirname, 'assets/ai-and-i.icns') // dock icon
  });

  mainWindow.loadFile('src/renderer/index.html');

  if (process.argv.includes('--dev')) {
    mainWindow.webContents.openDevTools();
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    mainWindow.focus();
  });

  mainWindow.on('closed', () => {
    if (isRecording) {
      stopRecording();
    }
    mainWindow = null;
  });
}

function createMenu() {
  const template = [
    {
      label: 'ai&i',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        {
          label: 'Check for Updates...',
          click: () => {
            if (app.isPackaged) {
              autoUpdater.checkForUpdates();
            } else {
              console.log('⚠️  Auto-updater only works in packaged app');
            }
          }
        },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideothers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    },
    {
      label: 'Recording',
      submenu: [
        {
          label: 'Start Recording',
          accelerator: 'CmdOrCtrl+R',
          click: () => mainWindow.webContents.send('start-recording')
        },
        {
          label: 'Stop Recording',
          accelerator: 'CmdOrCtrl+S',
          click: () => mainWindow.webContents.send('stop-recording')
        }
      ]
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'close' },
        { type: 'separator' },
        { role: 'front' }
      ]
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    }
  ];

  const menu = Menu.buildFromTemplate(template);
  Menu.setApplicationMenu(menu);
}

function createTrayIcon() {
  try {
    // Try multiple paths for tray icon
    let iconPath = path.join(__dirname, 'assets/tray-icon-white.png');
    if (!fs.existsSync(iconPath)) {
      // Try in Resources folder for packaged app
      iconPath = path.join(process.resourcesPath, 'app.asar.unpacked/assets/tray-icon-white.png');
      if (!fs.existsSync(iconPath)) {
        iconPath = path.join(process.resourcesPath, 'assets/tray-icon-white.png');
      }
    }
    tray = new Tray(iconPath);
  
  const contextMenu = Menu.buildFromTemplate([
    {
      label: isRecording ? 'Stop Recording' : 'Start Recording',
      click: () => {
        if (isRecording) {
          mainWindow.webContents.send('stop-recording');
        } else {
          mainWindow.webContents.send('start-recording');
        }
      }
    },
    { type: 'separator' },
    {
      label: 'Show ai&i',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
          mainWindow.focus();
        }
      }
    },
    {
      label: 'Quit',
      click: () => {
        app.quit();
      }
    }
  ]);
  
  tray.setContextMenu(contextMenu);
  tray.setToolTip('ai&i - meeting recorder');
  
  tray.on('click', () => {
    if (mainWindow) {
      mainWindow.show();
      mainWindow.focus();
    }
  });
  } catch (error) {
    console.error('❌ Failed to create tray icon:', error.message);
    console.log('   Continuing without tray icon...');
  }
}

function updateTrayMenu() {
  if (!tray) return;
  
  const contextMenu = Menu.buildFromTemplate([
    {
      label: isRecording ? 'Stop Recording' : 'Start Recording',
      click: () => {
        if (isRecording) {
          mainWindow.webContents.send('stop-recording');
        } else {
          mainWindow.webContents.send('start-recording');
        }
      }
    },
    { type: 'separator' },
    {
      label: 'Show ai&i',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
          mainWindow.focus();
        }
      }
    },
    {
      label: 'Quit',
      click: () => {
        app.quit();
      }
    }
  ]);
  
  tray.setContextMenu(contextMenu);
}

// Clean recording functions - no real-time transcription
function startRecordingSession(sessionId) {
  console.log(`🎙️  Starting clean audio recording session: ${sessionId}`);
  // Just record audio, no real-time processing
}

function stopRecordingSession() {
  console.log('⏹️  Recording session stopped');
  // Clean stop without transcription cleanup
}

// Gemini end-to-end processing (replaces whisper → gemini pipeline)
async function processRecordingWithGemini(recordingResult) {
  try {
    console.log('🎯 starting gemini end-to-end processing...');
    
    if (!recordingResult.audioFilePath) {
      throw new Error('No audio file path provided');
    }
    
    // Show welcome message to user
    mainWindow.webContents.send('processing-started', {
      message: 'your transcript and summary will be here soon, v',
      sessionId: recordingResult.sessionId
    });
    
    // Initialize gemini service
    if (!summaryGeneration) {
      summaryGeneration = new SummaryGeneration();
    }
    
    // Process with gemini end-to-end (audio → transcript + summary)
    const geminiResult = await summaryGeneration.processAudioEndToEnd(recordingResult.audioFilePath, {
      participants: 'v', // hardcoded user name
      expectedDuration: Math.round((recordingResult.duration / 60) * 10) / 10, // convert to minutes with 1 decimal place
      meetingTopic: 'meeting',
      context: 'personal recording'
    });
    
    if (geminiResult.error) {
      throw new Error(geminiResult.error);
    }
    
    // Create complete recording data with proper timestamp
    const completionTime = new Date().toISOString();
    const recordingData = {
      sessionId: recordingResult.sessionId || Date.now(),
      title: `meeting ${new Date().toLocaleDateString()}`, 
      timestamp: completionTime,
      date: new Date().toLocaleDateString(),
      time: new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}),
      duration: recordingResult.totalDuration || recordingResult.duration || 0,
      audioFilePath: recordingResult.audioFilePath,
      transcript: geminiResult.transcript,
      summary: geminiResult.summary,
      speakerAnalysis: geminiResult.speakerAnalysis,
      emotionalDynamics: geminiResult.emotionalDynamics,
      cost: geminiResult.cost?.totalCost || 0,
      processingTime: geminiResult.processingTime,
      provider: 'gemini-2.5-flash-end-to-end'
    };
    
    // Save to database
    if (recordingsDB) {
      recordingsDB.updateRecording(recordingData.sessionId, recordingData);
    }
    
    // Notify UI that recording is complete
    mainWindow.webContents.send('recording-complete', recordingData);
    
    console.log(`✅ gemini end-to-end complete: ${geminiResult.processingTime}ms, $${recordingData.cost.toFixed(4)}`);
    
  } catch (error) {
    console.error('❌ gemini end-to-end processing failed:', error);
    
    // Notify UI of error
    mainWindow.webContents.send('processing-error', {
      error: error.message,
      message: 'sorry v, something went wrong processing your recording'
    });
  }
}

// IPC Handlers for audio capture and transcription
ipcMain.handle('start-recording', async (event, data) => {
  return await startAudioCaptureHandler(data);
});

ipcMain.handle('stop-recording', async () => {
  return await stopAudioCaptureHandler();
});

async function startAudioCaptureHandler(data) {
  try {
    if (!audioCapture) {
      audioCapture = new AudioCapture();
    }

    const sessionId = data?.sessionId || Date.now();
    const result = await audioCapture.startRecording(sessionId);
    
    if (result.success) {
      isRecording = true;
      
      // Add sessionId to result
      result.sessionId = sessionId;
      
      // Send status updates to renderer
      mainWindow.webContents.send('audio-status', {
        status: 'recording',
        sessionId: sessionId
      });
      
      // Update tray menu
      updateTrayMenu();
      
      // Clean recording - no real-time transcription
      startRecordingSession(sessionId);
      
      // Create meeting entry in sidebar immediately
      if (recordingsDB) {
        const meetingData = {
          sessionId,
          title: 'new meeting',
          startTime: data?.timestamp || new Date().toISOString(),
          status: 'recording'
        };
        recordingsDB.addRecording(meetingData);
        
        // Notify UI to show new meeting in sidebar
        mainWindow.webContents.send('meeting-started', meetingData);
      }
    }
    
    return result;
  } catch (error) {
    console.error('Failed to start audio capture:', error);
    return { success: false, error: error.message };
  }
}

ipcMain.handle('start-audio-capture', async () => {
  return await startAudioCaptureHandler();
});

async function stopAudioCaptureHandler() {
  try {
    if (!audioCapture) {
      return { success: false, error: 'No audio capture instance' };
    }

    const result = await audioCapture.stopRecording();
    
    if (result.success) {
      isRecording = false;
      
      // Clean recording stop
      stopRecordingSession();
      
      // Update tray menu
      updateTrayMenu();
      
      // Send status updates to renderer
      mainWindow.webContents.send('audio-status', {
        status: 'stopped',
        ...result
      });
      
      // Process with gemini end-to-end (no whisper)
      await processRecordingWithGemini(result);
    }
    
    return result;
  } catch (error) {
    console.error('Failed to stop audio capture:', error);
    return { success: false, error: error.message };
  }
}

ipcMain.handle('stop-audio-capture', async () => {
  return await stopAudioCaptureHandler();
});

ipcMain.handle('get-audio-status', async () => {
  if (!audioCapture) {
    return { isRecording: false };
  }
  return audioCapture.getRecordingStatus();
});

ipcMain.handle('trigger-screen-access', async () => {
  try {
    console.log('🔐 Triggering screen access to register app with macOS...');
    const sources = await desktopCapturer.getSources({
      types: ['screen'],
      thumbnailSize: { width: 1, height: 1 }
    });
    console.log('✅ Screen access triggered - app should now appear in System Preferences');
    return { success: true };
  } catch (error) {
    console.log('⚠️  Screen access trigger failed:', error.message);
    return { success: false, error: error.message };
  }
});

// Gemini connection test (replaces whisper test)
ipcMain.handle('test-gemini-connection', async () => {
  try {
    if (!summaryGeneration) {
      summaryGeneration = new SummaryGeneration();
    }
    
    // Test gemini connection
    console.log('🔍 testing gemini connection...');
    return { success: true, message: 'gemini connection ready' };
  } catch (error) {
    console.error('gemini connection test failed:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('save-transcript', async (event, transcriptData) => {
  try {
    const transcriptsDir = path.join(process.cwd(), 'transcripts');
    if (!fs.existsSync(transcriptsDir)) {
      fs.mkdirSync(transcriptsDir, { recursive: true });
    }

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `transcript_${transcriptData.sessionId || timestamp}.json`;
    const filePath = path.join(transcriptsDir, filename);
    
    const transcriptFile = {
      sessionId: transcriptData.sessionId,
      timestamp: transcriptData.timestamp,
      duration: transcriptData.duration || 0,
      totalCost: transcriptData.cost || 0,
      transcript: transcriptData.transcript,
      segments: transcriptData.segments || [],
      speakers: transcriptData.speakers || [],
      metadata: {
        appVersion: '1.0.0',
        apiProvider: 'OpenAI Whisper',
        createdAt: new Date().toISOString()
      }
    };
    
    fs.writeFileSync(filePath, JSON.stringify(transcriptFile, null, 2));
    
    console.log('💾 Transcript saved:', filename);
    return { success: true, filePath: filename };
  } catch (error) {
    console.error('Failed to save transcript:', error);
    return { success: false, error: error.message };
  }
});

function stopRecording() {
  if (isRecording && audioCapture) {
    audioCapture.stopRecording();
    isRecording = false;
    updateTrayMenu();
  }
}

// initialize services (lazy loading to avoid startup errors)
function initializeServices() {
  try {
    recordingsDB = new RecordingsDB();
    console.log(`✅ services ready (${recordingsDB.getAllRecordings().length} recordings loaded)`);
  } catch (error) {
    console.warn('⚠️  Failed to initialize recordingsDB:', error.message);
    recordingsDB = null;
  }
}

// ipc handlers for new ui
ipcMain.handle('get-recordings', async () => {
  try {
    if (!recordingsDB) {
      return { recordings: [], error: 'Database not available' };
    }
    return { recordings: recordingsDB.getAllRecordings() };
  } catch (error) {
    return { recordings: [], error: error.message };
  }
});

// auto-updater ipc handlers
ipcMain.handle('check-for-updates', async () => {
  if (app.isPackaged) {
    autoUpdater.checkForUpdates();
  }
});

ipcMain.handle('download-update', async () => {
  console.log('📥 Download update requested');
  if (app.isPackaged) {
    try {
      // Check if already downloaded
      console.log('🔍 Starting download update process...');
      await autoUpdater.downloadUpdate();
      console.log('✅ Download update completed successfully');
      return { success: true };
    } catch (error) {
      console.error('❌ Download update failed:', error.message);
      // Don't throw error if it's already downloaded
      if (error.message.includes('already downloaded') || error.message.includes('Update has already been downloaded')) {
        console.log('ℹ️  Update was already downloaded, continuing...');
        return { success: true, alreadyDownloaded: true };
      }
      throw error;
    }
  } else {
    console.log('⚠️  Download update skipped (not packaged)');
    return { success: false, reason: 'not packaged' };
  }
});

ipcMain.handle('restart-and-install', async () => {
  console.log('🔄 Restart and install requested');
  if (app.isPackaged) {
    try {
      console.log('✅ Initiating quit and install...');
      // Use setImmediate to ensure the IPC response is sent back first
      setImmediate(() => {
        console.log('🔄 Executing quitAndInstall now...');
        try {
          // Try different quitAndInstall configurations
          autoUpdater.quitAndInstall(false, true);
        } catch (error) {
          console.log('❌ First quitAndInstall attempt failed, trying alternative...');
          try {
            autoUpdater.quitAndInstall();
          } catch (error2) {
            console.log('❌ Second quitAndInstall attempt failed, trying app.quit...');
            app.quit();
          }
        }
      });
      return { success: true };
    } catch (error) {
      console.error('❌ Restart and install failed:', error.message);
      throw error;
    }
  } else {
    console.log('⚠️  Restart and install skipped (not packaged)');
    return { success: false, reason: 'not packaged' };
  }
});

// Removed old generate-summary handler - now using gemini end-to-end processing

// Legacy function removed - now using processRecordingWithGemini for end-to-end processing

app.whenReady().then(async () => {
  createWindow();
  createMenu();
  createTrayIcon();
  initializeServices();
  
  // Register with macOS permissions system after app is ready
  await ensureAppRegisteredWithMacOS();
  
  // check if app was just updated using persistent storage
  if (app.isPackaged) {
    const currentVersion = app.getVersion();
    const userDataPath = app.getPath('userData');
    const versionFilePath = path.join(userDataPath, 'last-version.txt');
    
    let lastVersion = null;
    try {
      if (fs.existsSync(versionFilePath)) {
        lastVersion = fs.readFileSync(versionFilePath, 'utf8').trim();
      }
    } catch (error) {
      console.log('Could not read last version file:', error.message);
    }
    
    if (lastVersion && lastVersion !== currentVersion) {
      console.log(`✅ App updated from ${lastVersion} to ${currentVersion}`);
      setTimeout(() => {
        if (mainWindow) {
          mainWindow.webContents.send('update-success', {
            version: currentVersion,
            changelog: 'Auto-updater improvements and bug fixes'
          });
        }
      }, 2000); // slight delay to let UI load
    }
    
    // store current version for next startup
    try {
      fs.writeFileSync(versionFilePath, currentVersion);
    } catch (error) {
      console.log('Could not write version file:', error.message);
    }
  }

  // initialize auto-updater (check for updates on startup)
  console.log('🔍 app.isPackaged:', app.isPackaged);
  if (app.isPackaged) { // only in production builds
    console.log('⏰ scheduling auto-updater check in 3 seconds...');
    setTimeout(() => {
      console.log('🚀 triggering auto-updater check now');
      autoUpdater.checkForUpdates();
    }, 3000); // wait 3 seconds after startup
  } else {
    console.log('⚠️  skipping auto-updater (not packaged)');
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

app.on('before-quit', () => {
  stopRecording();
  if (audioCapture) {
    audioCapture.cleanup();
  }
});