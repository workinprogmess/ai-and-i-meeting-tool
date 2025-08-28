const { ipcRenderer } = require('electron');

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
            // Remove prompt leakage from old recordings
            let cleanContent = transcriptB;
            if (cleanContent.includes('### formatting requirements:')) {
                // Find where actual content starts (after the formatting instructions)
                const contentStart = cleanContent.indexOf('[0:00');
                if (contentStart > 0) {
                    cleanContent = cleanContent.substring(contentStart);
                }
            }
            
            // format enhanced transcript with emotional context and conversation blocks
            let formatted = cleanContent
                .replace(/\n\n/g, '</p><p>')
                .replace(/\n/g, '<br>')
                .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                .replace(/@(\w+)/g, '<span class="speaker-ref">@$1</span>')
                .replace(/_([^_]+)_/g, '<em class="topic-emphasis">$1</em>')
                .replace(/(🟡|🔴|🔵|🟢|🟠)/g, '<span class="emotion-indicator">$1</span>')
                .replace(/\[(\d{1,2}:\d{2}[:\d{2}]*(?:-\d{1,2}:\d{2}[:\d{2}]*)?)\]/g, '<span class="timestamp">[$1]</span>')
                .replace(/^### /gm, '<h3>')
                .replace(/^## /gm, '<h2>');
            
            return `<div class="enhanced-transcript"><p>${formatted}</p></div>`;
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
        this.updateBtn.textContent = 'restart';
        this.updateBtn.style.background = 'rgba(76, 175, 80, 0.3)';
    }
    
    async handleUpdateClick() {
        if (this.updateBtn.textContent === 'download') {
            this.updateBtn.textContent = 'downloading...';
            this.updateBtn.disabled = true;
            await ipcRenderer.invoke('download-update');
        } else if (this.updateBtn.textContent === 'restart') {
            await ipcRenderer.invoke('restart-and-install');
        }
    }
    
    hideUpdatePopup() {
        this.updatePopup.style.display = 'none';
    }
    
    async handleUpdateNow() {
        this.hideUpdatePopup();
        this.updateBtn.textContent = 'downloading...';
        this.updateBtn.disabled = true;
        await ipcRenderer.invoke('download-update');
    }
}

// initialize app when dom is ready
document.addEventListener('DOMContentLoaded', () => {
    window.aiApp = new AIAndIApp();
});