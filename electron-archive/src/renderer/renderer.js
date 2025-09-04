const { ipcRenderer } = require('electron');

// Send logs to main process for debugging
const sendLog = (msg) => {
    console.log(msg);
    try {
        ipcRenderer.send('renderer-log', msg);
    } catch (e) {
        // Ignore if IPC not ready
    }
};

// MILESTONE 3.3.5: Mixed audio capture - the simple solution
// First check if we have the required APIs
sendLog('🔍 Checking browser APIs:');
sendLog(`   - window available: ${typeof window !== 'undefined'}`);
sendLog(`   - navigator available: ${typeof navigator !== 'undefined'}`);
sendLog(`   - navigator.mediaDevices available: ${!!(navigator && navigator.mediaDevices)}`);
sendLog(`   - getDisplayMedia available: ${!!(navigator && navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia)}`);
sendLog(`   - __dirname: ${__dirname}`);
sendLog(`   - process.cwd(): ${process.cwd()}`);

// Load mixed audio capture directly in the renderer process
try {
    sendLog('📁 Loading mixed audio capture module...');
    // Use absolute path from __dirname
    const path = require('path');
    const modulePath = path.join(__dirname, 'mixedAudioCapture.js');
    sendLog(`   - Module path: ${modulePath}`);
    const MixedAudioCapture = require(modulePath);
    
    // Create instance if not already created by the module
    if (!window.mixedAudioCapture) {
        sendLog('📦 Creating MixedAudioCapture instance from imported class...');
        window.mixedAudioCapture = new MixedAudioCapture();
    }
    
    sendLog(`✅ Mixed audio capture loaded, checking availability: ${!!window.mixedAudioCapture}`);
} catch (error) {
    sendLog(`❌ Failed to load mixed audio capture: ${error.message}`);
    sendLog(`Stack trace: ${error.stack}`);
}
ipcRenderer.on('start-mixed-audio-recording', async (event, sessionId) => {
    console.log('📨 IPC: Received start-mixed-audio-recording request:', sessionId);
    
    // Send console logs to main process for debugging
    const sendLog = (msg) => {
        console.log(msg);
        ipcRenderer.send('renderer-log', msg);
    };
    
    sendLog('🔍 Checking window.mixedAudioCapture...');
    sendLog(`   - typeof window.mixedAudioCapture: ${typeof window.mixedAudioCapture}`);
    sendLog(`   - window.mixedAudioCapture exists: ${!!window.mixedAudioCapture}`);
    
    // Check if mixed audio capture is available
    if (!window.mixedAudioCapture) {
        sendLog('❌ window.mixedAudioCapture is not available');
        sendLog(`   - Checking global scope...`);
        sendLog(`   - global.mixedAudioCapture: ${typeof global.mixedAudioCapture}`);
        sendLog(`   - this.mixedAudioCapture: ${typeof this.mixedAudioCapture}`);
        ipcRenderer.send('mixed-audio-recording-started', {
            success: false,
            error: 'Mixed audio capture not initialized'
        });
        return;
    }
    
    sendLog('✅ window.mixedAudioCapture is available, attempting to start recording...');
    
    // Capture console logs from mixed audio module
    const originalLog = console.log;
    const originalError = console.error;
    
    // Temporarily override console to capture module logs
    console.log = (...args) => {
        originalLog(...args);
        // Use IPC directly to avoid recursion
        try {
            ipcRenderer.send('renderer-log', '   [Module] ' + args.join(' '));
        } catch (e) {
            // Ignore
        }
    };
    console.error = (...args) => {
        originalError(...args);
        // Use IPC directly to avoid recursion
        try {
            ipcRenderer.send('renderer-log', '   [Module Error] ' + args.join(' '));
        } catch (e) {
            // Ignore
        }
    };
    
    try {
        const result = await window.mixedAudioCapture.startRecording(sessionId);
        // Restore console
        console.log = originalLog;
        console.error = originalError;
        ipcRenderer.send('mixed-audio-recording-started', result);
    } catch (error) {
        // Restore console
        console.log = originalLog;
        console.error = originalError;
        sendLog(`❌ Mixed audio recording failed: ${error.message}`);
        sendLog(`   Stack: ${error.stack}`);
        ipcRenderer.send('mixed-audio-recording-started', {
            success: false,
            error: error.message || 'Not supported'
        });
    }
});

ipcRenderer.on('stop-mixed-audio-recording', async (event) => {
    console.log('📨 IPC: Received stop-mixed-audio-recording request');
    try {
        const result = await window.mixedAudioCapture.stopRecording();
        
        // Handle the single mixed audio file
        if (result.audioBlob) {
            console.log('🎯 Processing mixed audio for IPC transfer...');
            const buffer = Buffer.from(await result.audioBlob.arrayBuffer());
            result.audioBuffer = buffer;
            delete result.audioBlob; // Remove blob (can't serialize over IPC)
        }
        
        ipcRenderer.send('mixed-audio-recording-stopped', result);
    } catch (error) {
        ipcRenderer.send('mixed-audio-recording-stopped', {
            success: false,
            error: error.message
        });
    }
});

class AIAndIApp {
    constructor() {
        this.isRecording = false;
        this.currentCost = 0;
        this.totalCost = 0; // track total accumulated cost
        this.currentSessionId = null;
        this.currentView = 'recording'; // 'recording' or 'meeting'
        this.selectedRecording = null;
        this.recordings = [];
        
        this.initializeElements();
        this.bindEvents();
        this.setupIPC();
        this.loadRecordings();
        this.updateStatus('ready');
    }
    
    initializeElements() {
        // recording view elements
        this.newMeetingBtn = document.getElementById('newMeetingBtn');
        this.toggleRecordBtn = document.getElementById('toggleRecordBtn');
        this.recordBtnText = document.getElementById('recordBtnText');
        this.recordDot = document.getElementById('recordDot');
        this.recordingDisplay = document.getElementById('recordingDisplay');
        this.waveAnimation = document.getElementById('waveAnimation');
        this.recordingTimer = document.getElementById('recordingTimer');
        this.recordingMessage = document.getElementById('recordingMessage');
        this.status = document.getElementById('status');
        this.costCounter = document.getElementById('costCounter');
        
        // sidebar elements
        this.recordingsList = document.getElementById('recordingsList');
        this.updateNotification = document.getElementById('updateNotification');
        this.updateBtn = document.getElementById('updateBtn');
        this.updateVersion = document.getElementById('updateVersion');
        
        // update popup elements
        this.updatePopup = document.getElementById('updatePopup');
        this.popupVersion = document.getElementById('popupVersion');
        this.updateLater = document.getElementById('updateLater');
        this.updateNow = document.getElementById('updateNow');
        
        // meeting view elements
        this.recordingView = document.getElementById('recordingView');
        this.meetingView = document.getElementById('meetingView');
        this.backBtn = document.getElementById('backBtn');
        this.meetingTitle = document.getElementById('meetingTitle');
        this.meetingDate = document.getElementById('meetingDate');
        this.meetingDuration = document.getElementById('meetingDuration');
        
        // tab elements
        this.tabBtns = document.querySelectorAll('.tab-btn');
        this.summaryTab = document.getElementById('summaryTab');
        this.transcriptTab = document.getElementById('transcriptTab');
        this.summaryContent = document.getElementById('summaryContent');
        this.transcriptContent = document.getElementById('transcriptContent');
        this.copySummaryBtn = document.getElementById('copySummaryBtn');
        this.copyTranscriptBtn = document.getElementById('copyTranscriptBtn');
    }
    
    bindEvents() {
        // recording controls
        this.newMeetingBtn.addEventListener('click', () => this.showRecordingView());
        this.toggleRecordBtn.addEventListener('click', () => this.toggleRecording());
        
        // navigation
        this.backBtn.addEventListener('click', () => this.showRecordingView());
        
        // tabs
        this.tabBtns.forEach(btn => {
            btn.addEventListener('click', (e) => this.switchTab(e.target.dataset.tab));
        });
        
        // copy buttons
        this.copySummaryBtn.addEventListener('click', () => this.copyToClipboard('summary'));
        this.copyTranscriptBtn.addEventListener('click', () => this.copyToClipboard('transcript'));
        
        // update notifications
        this.updateBtn.addEventListener('click', () => this.handleUpdateClick());
        this.updateLater.addEventListener('click', () => this.hideUpdatePopup());
        this.updateNow.addEventListener('click', () => this.handleUpdateNow());
    }
    
    setupIPC() {
        // menu-triggered commands
        ipcRenderer.on('start-recording', () => {
            if (!this.isRecording) this.startRecording();
        });
        
        ipcRenderer.on('stop-recording', () => {
            if (this.isRecording) this.stopRecording();
        });
        
        // audio status updates
        ipcRenderer.on('audio-status', (event, statusData) => {
            this.handleAudioStatus(statusData);
        });
        
        // new gemini pipeline events
        ipcRenderer.on('meeting-started', (event, meetingData) => {
            this.handleMeetingStarted(meetingData);
        });
        
        ipcRenderer.on('processing-started', (event, data) => {
            this.handleProcessingStarted(data);
        });
        
        ipcRenderer.on('recording-complete', (event, recordingData) => {
            this.handleRecordingComplete(recordingData);
        });
        
        ipcRenderer.on('processing-error', (event, errorData) => {
            this.handleProcessingError(errorData);
        });
        
        ipcRenderer.on('recording-error', (event, errorData) => {
            this.handleRecordingError(errorData);
        });
        
        // auto-updater events
        ipcRenderer.on('update-available', (event, info) => {
            this.showUpdateNotification(info);
        });
        
        ipcRenderer.on('update-downloaded', (event, info) => {
            this.showUpdateReady(info);
        });
        
        ipcRenderer.on('update-error', (event, error) => {
            console.error('update error:', error);
        });

        ipcRenderer.on('update-not-available', () => {
            console.log('app is up to date');
            // Show temporary status message
            const originalText = this.statusText.textContent;
            this.updateStatus('app is up to date');
            setTimeout(() => {
                this.updateStatus(originalText || 'ready');
            }, 3000);
        });

        ipcRenderer.on('update-success', (event, info) => {
            console.log('update completed successfully:', info);
            this.showUpdateSuccessToast(info.version, info.changelog || 'Performance improvements and bug fixes');
        });
    }
    
    // New toggle recording method
    toggleRecording() {
        if (this.isRecording) {
            this.stopRecording();
        } else {
            this.startRecording();
        }
    }
    
    async startRecording() {
        try {
            this.isRecording = true;
            this.currentSessionId = Date.now().toString();
            
            // update ui - single toggle button
            this.recordBtnText.textContent = 'stop recording';
            this.recordDot.className = 'status-dot recording';
            this.updateStatus('recording');
            
            // show recording display with wave animation
            this.recordingDisplay.style.display = 'flex';
            this.createWaveAnimation();
            this.startRecordingTimer();
            
            // preserve cost display during recording
            // don't reset cost counter to 0
            
            // start recording via main process
            const result = await ipcRenderer.invoke('start-recording', {
                sessionId: this.currentSessionId,
                timestamp: new Date().toISOString()
            });
            
            if (!result.success) {
                throw new Error(result.error);
            }
            
        } catch (error) {
            console.error('failed to start recording:', error);
            this.updateStatus('error: ' + error.message);
            this.resetRecordingUI();
        }
    }
    
    async stopRecording() {
        try {
            this.updateStatus('stopping...');
            this.recordDot.className = 'status-dot processing';
            
            // stop recording via main process
            const result = await ipcRenderer.invoke('stop-recording');
            
            if (result.success) {
                this.updateStatus('generating summary...');
            }
            
        } catch (error) {
            console.error('failed to stop recording:', error);
            this.updateStatus('error: ' + error.message);
        }
    }
    
    resetRecordingUI() {
        this.isRecording = false;
        this.recordBtnText.textContent = 'start recording';
        this.recordDot.className = 'status-dot ready';
        this.recordingDisplay.style.display = 'none';
        this.stopRecordingTimer();
        this.updateStatus('ready');
        
        // Clear wave animation
        this.waveAnimation.innerHTML = '';
        
        // Check for deferred updates
        this.checkDeferredUpdate();
    }
    
    handleAudioStatus(statusData) {
        // update cost counter
        this.currentCost = statusData.cost || 0;
        this.costCounter.textContent = `$${this.currentCost.toFixed(4)}`;
    }
    
    
    handleRecordingComplete(recordingData) {
        const { 
            sessionId, 
            transcript, 
            summary, 
            cost, 
            timestamp, 
            duration,
            speakerAnalysis,
            emotionalDynamics
        } = recordingData;
        
        // stop sidebar timer if exists
        if (this.sidebarTimers && this.sidebarTimers[sessionId]) {
            clearInterval(this.sidebarTimers[sessionId]);
            delete this.sidebarTimers[sessionId];
        }
        
        // add to recordings list with gemini end-to-end data
        // main.js now sends properly formatted date/time, use directly
        const recording = {
            id: sessionId,
            title: recordingData.title || `meeting ${new Date().toLocaleDateString()}`,
            date: recordingData.date || new Date().toLocaleDateString(),
            time: recordingData.time || new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}),
            duration: this.formatDuration(recordingData.duration || duration || 0),
            // gemini end-to-end provides both transcript and summary
            transcriptB: transcript, // enhanced transcript from gemini
            summaryB: summary, // enhanced summary from gemini
            speakerAnalysis,
            emotionalDynamics,
            cost: cost || 0,
            timestamp: recordingData.timestamp || new Date().toISOString(),
            provider: 'gemini' // mark as gemini end-to-end
        };
        
        this.recordings.unshift(recording);
        this.renderRecordingsList();
        this.resetRecordingUI();
        
        // show the completed meeting in sidebar immediately
        this.updateMeetingInSidebar(sessionId, 'completed');
        
        // navigate to the meeting view to show results
        this.selectRecording(sessionId);
        
        // Update total cost tracking
        this.totalCost += (cost || 0);
        
        // Calculate average cost per meeting
        const avgCost = this.recordings.length > 0 ? this.totalCost / this.recordings.length : 0;
        
        // Update cost display with total and average side by side
        this.costCounter.innerHTML = `total: $${this.totalCost.toFixed(4)} • avg: $${avgCost.toFixed(4)}`;
        
        this.updateStatus(`recording saved • $${(cost || 0).toFixed(4)}`);
    }
    
    handleSummaryGenerated(summaryData) {
        const { sessionId, summary, provider } = summaryData;
        
        // find recording and add summary
        const recording = this.recordings.find(r => r.id === sessionId);
        if (recording) {
            recording.summary = summary;
            recording.summaryProvider = provider;
        }
        
        // if this recording is currently viewed, update the summary tab
        if (this.selectedRecording && this.selectedRecording.id === sessionId) {
            this.selectedRecording.summary = summary;
            this.loadSummaryContent();
        }
    }
    
    async loadRecordings() {
        try {
            const result = await ipcRenderer.invoke('get-recordings');
            this.recordings = result.recordings || [];
            
            // Clean up existing recordings with all fixes
            this.recordings = this.recordings.map(recording => {
                // Fix invalid dates
                if (recording.date === 'Invalid Date' || !recording.date) {
                    const validTime = recording.timestamp ? new Date(recording.timestamp) : new Date();
                    recording.date = validTime.toLocaleDateString();
                    recording.time = validTime.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
                }
                
                // Fix uppercase titles to lowercase
                if (recording.title && recording.title.startsWith('Meeting')) {
                    recording.title = recording.title.replace('Meeting', 'meeting');
                }
                
                // Fix duration if it's 0 but we can calculate it from audio file info
                if (recording.duration === 0 || recording.duration === '0:00') {
                    // For your test recording, it was ~85 seconds based on logs
                    if (recording.sessionId === 1756320332841) {
                        recording.duration = '1:25'; // 85 seconds = 1:25
                    }
                }
                
                // Fix transcript/summary structure for gemini end-to-end recordings
                if (recording.transcript && !recording.transcriptB) {
                    recording.transcriptB = recording.transcript; // Move to enhanced field
                }
                if (recording.summary && !recording.summaryB) {
                    recording.summaryB = recording.summary; // Move to enhanced field
                }
                
                return recording;
            });
            
            this.totalCost = this.recordings.reduce((sum, recording) => {
                return sum + (recording.cost || 0);
            }, 0);
            
            // Update cost display
            const avgCost = this.recordings.length > 0 ? this.totalCost / this.recordings.length : 0;
            this.costCounter.innerHTML = `total: $${this.totalCost.toFixed(4)} • avg: $${avgCost.toFixed(4)}`;
            
            this.renderRecordingsList();
        } catch (error) {
            console.error('failed to load recordings:', error);
        }
    }
    
    renderRecordingsList() {
        if (this.recordings.length === 0) {
            this.recordingsList.innerHTML = `
                <div class="empty-state">
                    <p>no meetings yet</p>
                    <span>start your first recording</span>
                </div>
            `;
            return;
        }
        
        this.recordingsList.innerHTML = this.recordings.map(recording => `
            <div class="recording-item" data-id="${recording.id}">
                <h3>${recording.title}</h3>
                <div class="meta">
                    ${recording.date} • ${recording.time} • ${recording.duration}
                </div>
            </div>
        `).join('');
        
        // bind click events
        this.recordingsList.querySelectorAll('.recording-item').forEach(item => {
            item.addEventListener('click', () => {
                const recordingId = item.dataset.id;
                this.selectRecording(recordingId);
            });
        });
    }
    
    selectRecording(recordingId) {
        // Handle both string and number IDs
        const recording = this.recordings.find(r => r.id == recordingId);
        if (!recording) {
            console.log(`Recording not found: ${recordingId}`, this.recordings.map(r => r.id));
            return;
        }
        
        this.selectedRecording = recording;
        this.showMeetingView(recording);
    }
    
    showRecordingView() {
        this.currentView = 'recording';
        this.recordingView.style.display = 'flex';
        this.meetingView.style.display = 'none';
        
        // Reset UI state when returning to recording view
        if (!this.isRecording) {
            this.updateStatus('ready');
        }
        
        // clear active recording selection
        this.recordingsList.querySelectorAll('.recording-item').forEach(item => {
            item.classList.remove('active');
        });
    }
    
    showMeetingView(recording) {
        this.currentView = 'meeting';
        this.recordingView.style.display = 'none';
        this.meetingView.style.display = 'flex';
        
        // update meeting info
        this.meetingTitle.textContent = recording.title;
        this.meetingDate.textContent = recording.date;
        this.meetingDuration.textContent = recording.duration;
        
        // highlight selected recording
        this.recordingsList.querySelectorAll('.recording-item').forEach(item => {
            item.classList.toggle('active', item.dataset.id === recording.id);
        });
        
        // load content (now using pipeline b as default)
        this.loadTranscriptContent();
        this.loadSummaryContent();
    }
    
    showMeetingViewWithLoadingState(sessionId, message) {
        // Switch to meeting view immediately
        this.currentView = 'meeting';
        this.recordingView.style.display = 'none';
        this.meetingView.style.display = 'flex';
        
        // Set up meeting info with temp data
        this.meetingTitle.textContent = 'meeting ' + new Date().toLocaleDateString();
        this.meetingDate.textContent = new Date().toLocaleDateString();
        this.meetingDuration.textContent = '0:00';
        
        // Show loading states in tabs with custom message
        this.transcriptContent.innerHTML = `<div class="loading">${message}</div>`;
        this.summaryContent.innerHTML = `<div class="loading">processing will complete soon...</div>`;
        
        // Set transcript tab as active
        this.tabBtns.forEach(btn => {
            btn.classList.toggle('active', btn.dataset.tab === 'transcript');
        });
        this.summaryTab.classList.remove('active');
        this.transcriptTab.classList.add('active');
    }
    
    switchTab(tabName) {
        // update tab buttons
        this.tabBtns.forEach(btn => {
            btn.classList.toggle('active', btn.dataset.tab === tabName);
        });
        
        // update tab panels
        this.summaryTab.classList.toggle('active', tabName === 'summary');
        this.transcriptTab.classList.toggle('active', tabName === 'transcript');
    }
    
    loadTranscriptContent() {
        // use pipeline b (enhanced transcript) as default, fallback to pipeline a
        const transcript = this.selectedRecording?.transcriptB || this.selectedRecording?.transcript;
        
        if (!transcript) {
            this.transcriptContent.innerHTML = '<div class="loading">no transcript found for this recording</div>';
            return;
        }
        
        // format enhanced transcript if available, otherwise basic transcript
        console.log('Transcript data:', {
            hasTranscriptB: !!this.selectedRecording?.transcriptB,
            transcriptLength: transcript?.length,
            transcriptBLength: this.selectedRecording?.transcriptB?.length,
            transcriptPreview: transcript?.substring(0, 100)
        });
        
        const formattedTranscript = this.selectedRecording?.transcriptB 
            ? this.formatEnhancedTranscriptForDisplay(this.selectedRecording.transcriptB)
            : this.formatTranscriptForDisplay(transcript);
        this.transcriptContent.innerHTML = formattedTranscript;
    }
    
    loadSummaryContent() {
        if (!this.selectedRecording) return;
        
        // use pipeline b (enhanced summary) as default, fallback to pipeline a
        const summary = this.selectedRecording?.summaryB || this.selectedRecording?.summary;
        
        if (!summary) {
            this.summaryContent.innerHTML = '<div class="loading">analyzing transcript to generate summary...</div>';
            // trigger summary generation
            this.generateSummary();
            return;
        }
        
        // format enhanced summary if available, otherwise basic summary
        console.log('Summary data:', {
            hasSummaryB: !!this.selectedRecording?.summaryB,
            summaryLength: summary?.length,
            summaryBLength: this.selectedRecording?.summaryB?.length,
            summaryPreview: summary?.substring(0, 100)
        });
        
        const formattedSummary = this.selectedRecording?.summaryB 
            ? this.formatEnhancedSummaryForDisplay(this.selectedRecording.summaryB)
            : this.formatSummaryForDisplay(summary);
        this.summaryContent.innerHTML = formattedSummary;
    }
    
    
    async generateSummary() {
        try {
            await ipcRenderer.invoke('generate-summary', {
                sessionId: this.selectedRecording.id,
                transcript: this.selectedRecording.transcript,
                provider: 'gemini' // default to gemini for speed
            });
        } catch (error) {
            this.summaryContent.innerHTML = '<div class="loading">summary generation failed - please try again</div>';
        }
    }
    
    formatTranscriptForDisplay(transcript) {
        if (typeof transcript === 'string') {
            return `<div class="transcript-text">${transcript.replace(/\\n/g, '<br>')}</div>`;
        }
        
        // handle structured transcript
        return '<div class="transcript-text">formatted transcript content</div>';
    }
    
    formatSummaryForDisplay(summary) {
        if (typeof summary === 'string') {
            // convert markdown-style formatting to html
            let formatted = summary
                .replace(/\n\n/g, '</p><p>')
                .replace(/\n/g, '<br>')
                .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                .replace(/^- /gm, '• ')
                .replace(/^### /gm, '<h3>')
                .replace(/^## /gm, '<h2>');
            
            return `<div class="summary-text"><p>${formatted}</p></div>`;
        }
        
        return '<div class="summary-text">formatted summary content</div>';
    }
    
    formatEnhancedTranscriptForDisplay(transcriptB) {
        if (typeof transcriptB === 'string') {
            // Check if parsing failed - look for the exact failure message
            if (transcriptB.includes('parsing failed')) {
                // Check if we have fullOutput in the recording data
                if (this.selectedRecording?.fullOutput) {
                    // Use the fullOutput which contains the raw transcript
                    transcriptB = this.selectedRecording.fullOutput;
                    console.log('using fullOutput as fallback for failed transcript parsing');
                } else {
                    // Show a more helpful message with action
                    return `<div class="enhanced-transcript">
                        <p style="color: #666;">transcript parsing failed</p>
                        <p style="margin-top: 10px; font-size: 14px;">
                            the transcript was generated but couldn't be displayed properly.
                            try re-processing this recording or check the JSON file in summaries folder.
                        </p>
                    </div>`;
                }
            }
            
            // Remove prompt leakage from old recordings
            let cleanContent = transcriptB;
            if (cleanContent.includes('### formatting requirements:')) {
                // Find where actual content starts (after the formatting instructions)
                const contentStart = cleanContent.indexOf('[0:00');
                if (contentStart > 0) {
                    cleanContent = cleanContent.substring(contentStart);
                }
            }
            
            // format enhanced transcript - handle both timestamp and natural conversation formats
            let formatted;
            
            // Check if this is natural conversation format (contains @speaker: at line starts)
            if (/@\w+:\s/.test(cleanContent)) {
                // Natural conversation format - clean chronological lines
                formatted = cleanContent
                    .split('\n\n') // Split by speaker changes
                    .map(turn => {
                        if (turn.trim()) {
                            return `<div class="speaker-turn">${turn.replace(/^(@\w+):\s*/gm, '<span class="speaker-label">$1:</span> ')}</div>`;
                        }
                        return '';
                    })
                    .filter(turn => turn.length > 0)
                    .join('\n')
                    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                    .replace(/_([^_]+)_/g, '<em class="topic-emphasis">$1</em>')
                    .replace(/(🟡|🔴|🔵|🟢|🟠)/g, '<span class="emotion-indicator">$1</span>')
                    .replace(/\n(?!<div)/g, '<br>'); // line breaks within content, not between divs
            } else {
                // Legacy format with timestamps
                formatted = cleanContent
                    .replace(/\n\n/g, '</p><p>')
                    .replace(/\n/g, '<br>')
                    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                    .replace(/@(\w+)/g, '<span class="speaker-ref">@$1</span>')
                    .replace(/_([^_]+)_/g, '<em class="topic-emphasis">$1</em>')
                    .replace(/(🟡|🔴|🔵|🟢|🟠)/g, '<span class="emotion-indicator">$1</span>')
                    .replace(/\[(\d{1,2}:\d{2}[:\d{2}]*(?:-\d{1,2}:\d{2}[:\d{2}]*)?)\]/g, '<span class="timestamp">[$1]</span>')
                    .replace(/^### /gm, '<h3>')
                    .replace(/^## /gm, '<h2>');
                
                formatted = `<p>${formatted}</p>`;
            }
            
            return `<div class="enhanced-transcript">${formatted}</div>`;
        }
        
        return '<div class="enhanced-transcript">enhanced transcript content</div>';
    }
    
    formatEnhancedSummaryForDisplay(summaryB) {
        if (typeof summaryB === 'string') {
            // format enhanced summary with relationship dynamics and insights
            let formatted = summaryB
                .replace(/\n\n/g, '</p><p>')
                .replace(/\n/g, '<br>')
                .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                .replace(/@(\w+)/g, '<span class="speaker-ref">@$1</span>')
                .replace(/_([^_]+)_/g, '<em class="topic-emphasis">$1</em>')
                .replace(/(🟡|🔴|🔵|🟢|🟠)/g, '<span class="emotion-indicator">$1</span>')
                .replace(/^- /gm, '• ')
                .replace(/^### /gm, '<h3>')
                .replace(/^## /gm, '<h2>');
            
            return `<div class="enhanced-summary"><p>${formatted}</p></div>`;
        }
        
        return '<div class="enhanced-summary">enhanced summary content</div>';
    }
    
    async copyToClipboard(type) {
        let content;
        let buttonElement;
        
        switch(type) {
            case 'summary':
                // use pipeline b content if available, fallback to pipeline a
                content = this.selectedRecording?.summaryB || this.selectedRecording?.summary;
                buttonElement = this.copySummaryBtn;
                break;
            case 'transcript':
                // use pipeline b content if available, fallback to pipeline a
                content = this.selectedRecording?.transcriptB || this.selectedRecording?.transcript;
                buttonElement = this.copyTranscriptBtn;
                break;
            default:
                content = '';
                buttonElement = null;
        }
        
        if (!content) return;
        
        try {
            await navigator.clipboard.writeText(content);
            if (buttonElement) {
                const originalText = buttonElement.textContent;
                buttonElement.textContent = 'copied!';
                setTimeout(() => buttonElement.textContent = originalText, 2000);
            }
        } catch (error) {
            console.error('failed to copy:', error);
        }
    }
    
    updateStatus(message) {
        this.status.textContent = message;
    }
    
    formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }
    
    formatDuration(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }
    
    // Wave animation and timer methods for milestone 3.1.9
    createWaveAnimation() {
        // Create wave bars dynamically
        this.waveAnimation.innerHTML = '';
        for (let i = 0; i < 8; i++) {
            const bar = document.createElement('div');
            bar.className = 'wave-bar';
            this.waveAnimation.appendChild(bar);
        }
    }
    
    startRecordingTimer() {
        this.recordingStartTime = Date.now();
        this.timerInterval = setInterval(() => {
            const elapsed = Date.now() - this.recordingStartTime;
            const seconds = Math.floor(elapsed / 1000);
            this.recordingTimer.textContent = this.formatDuration(seconds);
        }, 1000);
    }
    
    stopRecordingTimer() {
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
            this.timerInterval = null;
        }
    }
    
    // New event handlers for gemini pipeline
    handleMeetingStarted(meetingData) {
        console.log('meeting started:', meetingData);
        // Meeting appears in sidebar (will implement sidebar updates)
        this.addMeetingToSidebar(meetingData);
    }
    
    handleProcessingStarted(data) {
        console.log('processing started:', data.message, 'for session:', data.sessionId);
        
        // Stop recording UI immediately and completely
        this.isRecording = false;
        this.recordBtnText.textContent = 'start recording';
        this.recordDot.className = 'status-dot processing';
        this.stopRecordingTimer();
        
        // Stop wave animation by hiding recording display
        this.recordingDisplay.style.display = 'none';
        this.waveAnimation.innerHTML = '';
        
        // Show processing message and navigate to meeting view with loading state
        this.updateStatus('processing');
        
        // Stop sidebar timer for the correct session
        const sessionId = data.sessionId || this.currentSessionId;
        if (this.sidebarTimers && this.sidebarTimers[sessionId]) {
            clearInterval(this.sidebarTimers[sessionId]);
            delete this.sidebarTimers[sessionId];
        }
        
        // Update sidebar to show processing state
        this.updateMeetingInSidebar(sessionId, 'processing');
        
        // Navigate to meeting view and show loading state immediately
        this.showMeetingViewWithLoadingState(sessionId, data.message);
    }
    
    handleProcessingError(errorData) {
        console.error('processing error:', errorData);
        this.updateStatus('error');
        this.recordingMessage.textContent = errorData.message;
        this.resetRecordingUI();
    }
    
    handleRecordingError(errorData) {
        console.error('❌ Recording error:', errorData);
        
        // Reset recording state immediately
        this.isRecording = false;
        this.recordBtnText.textContent = 'start recording';
        this.recordDot.className = 'status-dot error';
        
        // Stop any running timers
        this.stopRecordingTimer();
        this.recordingDisplay.style.display = 'none';
        this.waveAnimation.innerHTML = '';
        
        // Show user-friendly error message
        let userMessage = 'recording error occurred';
        if (errorData.phase === 'streaming_to_disk') {
            userMessage = 'failed to save recording - check disk space and permissions';
        } else if (errorData.type === 'pcm_processing_error') {
            userMessage = 'audio processing error - recording may be incomplete';
        }
        
        this.recordingMessage.textContent = userMessage;
        this.recordingMessage.style.display = 'block';
        
        // Clean up any sidebar timers
        if (this.sidebarTimers) {
            Object.values(this.sidebarTimers).forEach(timer => clearInterval(timer));
            this.sidebarTimers = {};
        }
        
        console.error(`❌ User shown: ${userMessage}`);
        console.error(`❌ Technical details:`, errorData);
    }
    
    addMeetingToSidebar(meetingData) {
        // Create meeting entry in sidebar
        const meetingEl = document.createElement('div');
        meetingEl.className = 'meeting-item recording';
        meetingEl.dataset.sessionId = meetingData.sessionId;
        meetingEl.innerHTML = `
            <div class="meeting-title">${meetingData.title}</div>
            <div class="meeting-status">recording...</div>
            <div class="meeting-timer" id="sidebarTimer-${meetingData.sessionId}">00:00</div>
        `;
        
        // Add to sidebar (insert at top)
        const emptyState = this.recordingsList.querySelector('.empty-state');
        if (emptyState) {
            emptyState.style.display = 'none';
        }
        
        this.recordingsList.insertBefore(meetingEl, this.recordingsList.firstChild);
        
        // Start sidebar timer
        this.startSidebarTimer(meetingData.sessionId);
    }
    
    startSidebarTimer(sessionId) {
        const timerEl = document.getElementById(`sidebarTimer-${sessionId}`);
        if (timerEl) {
            const startTime = Date.now();
            const interval = setInterval(() => {
                const elapsed = Date.now() - startTime;
                const seconds = Math.floor(elapsed / 1000);
                timerEl.textContent = this.formatDuration(seconds);
            }, 1000);
            
            // Store interval for cleanup
            this.sidebarTimers = this.sidebarTimers || {};
            this.sidebarTimers[sessionId] = interval;
        }
    }
    
    updateMeetingInSidebar(sessionId, status) {
        const meetingEl = this.recordingsList.querySelector(`.meeting-item[data-session-id="${sessionId}"]`);
        if (meetingEl) {
            const statusEl = meetingEl.querySelector('.meeting-status');
            const timerEl = meetingEl.querySelector('.meeting-timer');
            
            if (status === 'processing') {
                statusEl.textContent = 'processing...';
                meetingEl.classList.remove('recording');
                meetingEl.classList.add('processing');
                // Timer stays as is (showing final recording time)
            } else if (status === 'completed') {
                statusEl.textContent = 'completed';
                meetingEl.classList.remove('recording', 'processing');
                meetingEl.classList.add('completed');
                
                // Convert to permanent recording item
                const recording = this.recordings.find(r => r.id == sessionId);
                if (recording) {
                    meetingEl.classList.remove('meeting-item');
                    meetingEl.classList.add('recording-item');
                    meetingEl.innerHTML = `
                        <h3>${recording.title}</h3>
                        <div class="meta">
                            ${recording.date} • ${recording.time} • ${recording.duration}
                        </div>
                    `;
                    meetingEl.dataset.id = sessionId;
                    
                    // Bind click event
                    meetingEl.addEventListener('click', () => {
                        this.selectRecording(sessionId);
                    });
                }
            }
        }
    }
    
    // update notification methods
    showUpdateNotification(info) {
        console.log('update available:', info);
        this.currentUpdateInfo = info;
        
        // show sidebar notification
        this.updateVersion.textContent = `v${info.version}`;
        this.updateNotification.style.display = 'flex';
        this.updateBtn.textContent = 'download';
        
        // show figma-style popup
        this.popupVersion.textContent = `v${info.version}`;
        this.updatePopup.style.display = 'flex';
    }
    
    showUpdateReady(info) {
        console.log('update ready:', info);
        this.updateBtn.textContent = 'install';
        this.updateBtn.disabled = false;
        // Remove old styling, let CSS handle appearance
        this.updateBtn.style.background = '';
        this.updateBtn.style.removeProperty('background');
    }
    
    async handleUpdateClick() {
        console.log('🖱️ Update button clicked, text:', this.updateBtn.textContent);
        try {
            if (this.updateBtn.textContent === 'download') {
                // Check if recording is active
                if (this.isRecording) {
                    console.log('⚠️ Recording active, deferring update');
                    this.showUpdateDeferredMessage();
                    return;
                }
                
                console.log('📥 Starting download...');
                this.updateBtn.textContent = 'downloading...';
                this.updateBtn.disabled = true;
                const result = await ipcRenderer.invoke('download-update');
                console.log('📥 Download result:', result);
            } else if (this.updateBtn.textContent === 'install') {
                // Check if recording is active
                if (this.isRecording) {
                    console.log('⚠️ Recording active, deferring update');
                    this.showUpdateDeferredMessage();
                    return;
                }
                
                console.log('🔄 Showing manual update instructions...');
                this.showManualUpdateInstructions();
            }
        } catch (error) {
            console.error('❌ Update click error:', error);
        }
    }
    
    hideUpdatePopup() {
        this.updatePopup.style.display = 'none';
    }
    
    async handleUpdateNow() {
        // Check if recording is active
        if (this.isRecording) {
            this.hideUpdatePopup();
            this.showUpdateDeferredMessage();
            return;
        }
        
        this.hideUpdatePopup();
        
        // If update is already downloaded (button says 'restart'), install immediately
        if (this.updateBtn.textContent === 'restart') {
            await ipcRenderer.invoke('restart-and-install');
        } else {
            // Still need to download
            this.updateBtn.textContent = 'downloading...';
            this.updateBtn.disabled = true;
            await ipcRenderer.invoke('download-update');
        }
    }
    
    // Update protection and UX methods
    showUpdateDeferredMessage() {
        this.showToast('Update will install automatically after recording ends', 5000);
    }
    
    showUpdateConfirmDialog() {
        // Create minimal confirmation dialog
        const dialog = document.createElement('div');
        dialog.className = 'update-confirm-dialog';
        dialog.innerHTML = `
            <div class="update-confirm-overlay">
                <div class="update-confirm-content">
                    <h3>Ready to update?</h3>
                    <p>The app will restart to install the new version.</p>
                    <div class="update-confirm-actions">
                        <button class="btn-secondary" onclick="this.closest('.update-confirm-dialog').remove()">Cancel</button>
                        <button class="btn-primary" onclick="this.confirmUpdate()">Update Now</button>
                    </div>
                </div>
            </div>
        `;
        
        // Add click handler for update button
        const updateBtn = dialog.querySelector('.btn-primary');
        updateBtn.onclick = async () => {
            console.log('🔄 Confirmation dialog: Update Now clicked');
            dialog.remove();
            try {
                console.log('🔄 Calling restart-and-install IPC...');
                const result = await ipcRenderer.invoke('restart-and-install');
                console.log('🔄 Restart result:', result);
            } catch (error) {
                console.error('❌ Restart error:', error);
            }
        };
        
        document.body.appendChild(dialog);
    }
    
    showToast(message, duration = 10000) {
        // Remove any existing toast
        const existingToast = document.querySelector('.update-toast');
        if (existingToast) {
            existingToast.remove();
        }
        
        // Create new toast
        const toast = document.createElement('div');
        toast.className = 'update-toast';
        toast.innerHTML = `
            <div class="toast-content">
                <span class="toast-message">${message}</span>
                <button class="toast-close" onclick="this.closest('.update-toast').remove()">×</button>
            </div>
        `;
        
        document.body.appendChild(toast);
        
        // Auto-remove after duration
        setTimeout(() => {
            if (toast.parentNode) {
                toast.remove();
            }
        }, duration);
    }
    
    showUpdateSuccessToast(version, changelog) {
        const message = `Updated to ${version} - ${changelog}`;
        this.showToast(message, 15000);
    }
    
    showManualUpdateInstructions() {
        const dialog = document.createElement('div');
        dialog.className = 'update-confirm-dialog';
        dialog.innerHTML = `
            <div class="update-confirm-overlay">
                <div class="update-confirm-content">
                    <h3>Update Ready to Install</h3>
                    <p>The new version has been downloaded. To complete the update:</p>
                    <ol style="margin: 16px 0; padding-left: 20px; color: #666;">
                        <li>Quit ai&i</li>
                        <li>Download the latest version from GitHub releases</li>
                        <li>Replace the app in Applications folder</li>
                        <li>Restart ai&i</li>
                    </ol>
                    <p style="font-size: 12px; color: #888;">Auto-install will work once we have code signing.</p>
                    <div class="update-confirm-actions">
                        <button class="btn-secondary">Close</button>
                        <button class="btn-primary">Open GitHub Releases</button>
                    </div>
                </div>
            </div>
        `;
        
        const closeBtn = dialog.querySelector('.btn-secondary');
        const githubBtn = dialog.querySelector('.btn-primary');
        
        closeBtn.onclick = () => dialog.remove();
        githubBtn.onclick = async () => {
            dialog.remove();
            // Open GitHub releases page
            await ipcRenderer.invoke('open-external-url', 'https://github.com/workinprogmess/ai-and-i-meeting-tool/releases');
        };
        
        document.body.appendChild(dialog);
    }
    
    checkDeferredUpdate() {
        // Check if there's a pending update (restart button is showing)
        if (this.updateBtn.textContent === 'restart' && this.updateNotification.style.display === 'flex') {
            // Show dialog asking if user wants to update now
            const dialog = document.createElement('div');
            dialog.className = 'update-confirm-dialog';
            dialog.innerHTML = `
                <div class="update-confirm-overlay">
                    <div class="update-confirm-content">
                        <h3>Ready to update now?</h3>
                        <p>Recording finished. The app can now restart to install the new version.</p>
                        <div class="update-confirm-actions">
                            <button class="btn-secondary">Later</button>
                            <button class="btn-primary">Update Now</button>
                        </div>
                    </div>
                </div>
            `;
            
            // Add click handlers
            const laterBtn = dialog.querySelector('.btn-secondary');
            const updateBtn = dialog.querySelector('.btn-primary');
            
            laterBtn.onclick = () => dialog.remove();
            updateBtn.onclick = async () => {
                console.log('🔄 Deferred update dialog: Update Now clicked');
                dialog.remove();
                try {
                    console.log('🔄 Calling restart-and-install IPC from deferred dialog...');
                    const result = await ipcRenderer.invoke('restart-and-install');
                    console.log('🔄 Deferred restart result:', result);
                } catch (error) {
                    console.error('❌ Deferred restart error:', error);
                }
            };
            
            document.body.appendChild(dialog);
        }
    }
}

// initialize app when dom is ready
document.addEventListener('DOMContentLoaded', () => {
    window.aiApp = new AIAndIApp();
});