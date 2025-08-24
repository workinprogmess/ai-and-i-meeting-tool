const { app, BrowserWindow, ipcMain, Menu, desktopCapturer } = require('electron');
const path = require('path');
const fs = require('fs');
const AudioCapture = require('./src/audio/audioCapture');
const WhisperTranscription = require('./src/api/whisperTranscription');

let mainWindow;
let isRecording = false;
let audioCapture = null;
let whisperTranscription = null;
let chunkMonitorInterval = null;

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
    title: 'ai&i'
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

// Real-time PCM transcription with AudioTee
function setupRealTimeTranscription() {
  if (!audioCapture) return;
  
  // Listen for PCM chunks from AudioCapture
  audioCapture.on('chunk', async (chunkInfo) => {
    try {
      console.log(`🎯 Processing PCM chunk ${chunkInfo.index} for transcription`);
      
      if (!whisperTranscription) {
        whisperTranscription = new WhisperTranscription();
      }
      
      // Transcribe PCM chunk directly (no file conversion needed!)
      const result = await whisperTranscription.transcribePCMChunk(chunkInfo, {
        enableSpeakerDiarization: true
      });
      
      if (result.success && mainWindow) {
        console.log(`📝 Real-time transcription: "${result.text}"`);
        
        // Send live update to UI
        mainWindow.webContents.send('transcription-update', {
          text: result.text,
          segments: result.segments,
          speakers: result.speakers,
          cost: result.cost,
          chunkIndex: chunkInfo.index,
          sessionId: chunkInfo.sessionId
        });
      }
      
    } catch (error) {
      console.error(`❌ PCM transcription failed for chunk ${chunkInfo.index}:`, error.message);
    }
  });
  
  console.log('✅ Real-time PCM transcription system active');
}

function stopRealTimeTranscription() {
  if (audioCapture) {
    audioCapture.removeAllListeners('chunk');
    console.log('⏹️  Real-time transcription stopped');
  }
}

// IPC Handlers for audio capture and transcription
ipcMain.handle('start-audio-capture', async () => {
  try {
    if (!audioCapture) {
      audioCapture = new AudioCapture();
    }

    const sessionId = Date.now();
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
      
      // Start real-time PCM transcription
      setupRealTimeTranscription();
    }
    
    return result;
  } catch (error) {
    console.error('Failed to start audio capture:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('stop-audio-capture', async () => {
  try {
    if (!audioCapture) {
      return { success: false, error: 'No audio capture instance' };
    }

    const result = await audioCapture.stopRecording();
    
    if (result.success) {
      isRecording = false;
      
      // Stop real-time transcription
      stopRealTimeTranscription();
      
      // Send status updates to renderer
      mainWindow.webContents.send('audio-status', {
        status: 'stopped',
        ...result
      });
    }
    
    return result;
  } catch (error) {
    console.error('Failed to stop audio capture:', error);
    return { success: false, error: error.message };
  }
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

ipcMain.handle('test-openai-connection', async () => {
  try {
    if (!whisperTranscription) {
      whisperTranscription = new WhisperTranscription();
    }
    
    const result = await whisperTranscription.testApiConnection();
    return result;
  } catch (error) {
    console.error('OpenAI connection test failed:', error);
    return { success: false, error: error.message };
  }
});

ipcMain.handle('transcribe-audio', async (event, chunkInfo) => {
  try {
    if (!whisperTranscription) {
      whisperTranscription = new WhisperTranscription();
    }

    console.log('🎵 Starting transcription for chunk:', chunkInfo.chunkIndex || 'unknown');
    
    const result = await whisperTranscription.transcribeRealTimeChunk(chunkInfo);
    
    if (result.success) {
      // Send real-time update to renderer
      mainWindow.webContents.send('transcription-update', {
        text: result.text,
        segments: result.segments,
        speakers: result.speakers,
        cost: result.cost,
        chunkIndex: result.chunkInfo?.index
      });
    }
    
    return result;
  } catch (error) {
    console.error('Transcription failed:', error);
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
  }
}

app.whenReady().then(async () => {
  createWindow();
  createMenu();
  
  // Register with macOS permissions system after app is ready
  await ensureAppRegisteredWithMacOS();
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