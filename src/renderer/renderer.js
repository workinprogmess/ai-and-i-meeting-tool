const { ipcRenderer } = require('electron');

class AIAndIApp {
    constructor() {
        this.isRecording = false;
        this.currentCost = 0;
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
        this.recordBtn = document.getElementById('recordBtn');
        this.stopBtn = document.getElementById('stopBtn');
        this.transcript = document.getElementById('transcript');
        this.status = document.getElementById('status');
        this.costCounter = document.getElementById('costCounter');
        this.recordDot = document.getElementById('recordDot');
        this.liveTranscript = document.getElementById('liveTranscript');
        
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
        this.recordBtn.addEventListener('click', () => this.startRecording());
        this.stopBtn.addEventListener('click', () => this.stopRecording());
        
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
        
        // audio and transcription updates
        ipcRenderer.on('audio-status', (event, statusData) => {
            this.handleAudioStatus(statusData);
        });
        
        ipcRenderer.on('transcription-update', (event, transcriptionData) => {
            this.handleTranscriptionUpdate(transcriptionData);
        });
        
        ipcRenderer.on('recording-complete', (event, recordingData) => {
            this.handleRecordingComplete(recordingData);
        });
        
        ipcRenderer.on('summary-generated', (event, summaryData) => {
            this.handleSummaryGenerated(summaryData);
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
    }
    
    async startRecording() {
        try {
            this.isRecording = true;
            this.currentSessionId = Date.now().toString();
            
            // update ui
            this.recordBtn.disabled = true;
            this.stopBtn.disabled = false;
            this.recordDot.className = 'status-dot recording';
            this.liveTranscript.classList.add('show');
            this.transcript.innerHTML = '<p class="placeholder">listening...</p>';
            this.updateStatus('recording');
            
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
        this.recordBtn.disabled = false;
        this.stopBtn.disabled = true;
        this.recordDot.className = 'status-dot ready';
        this.liveTranscript.classList.remove('show');
        this.updateStatus('ready');
    }
    
    handleAudioStatus(statusData) {
        // update cost counter
        this.currentCost = statusData.cost || 0;
        this.costCounter.textContent = `$${this.currentCost.toFixed(4)}`;
    }
    
    handleTranscriptionUpdate(transcriptionData) {
        if (!this.isRecording) return;
        
        const { text, timestamp, chunkIndex } = transcriptionData;
        
        if (text && text.trim()) {
            // format timestamp for display
            const time = this.formatTime(chunkIndex * 5); // 5-second chunks
            
            // add new transcript line
            const transcriptLine = document.createElement('p');
            transcriptLine.innerHTML = `<span class="timestamp">[${time}]</span> ${text}`;
            
            // replace placeholder or append
            if (this.transcript.querySelector('.placeholder')) {
                this.transcript.innerHTML = '';
            }
            
            this.transcript.appendChild(transcriptLine);
            this.transcript.scrollTop = this.transcript.scrollHeight;
        }
    }
    
    handleRecordingComplete(recordingData) {
        const { sessionId, transcript, duration, cost, timestamp } = recordingData;
        
        // add to recordings list
        const recording = {
            id: sessionId,
            title: `meeting ${new Date().toLocaleDateString()}`,
            date: new Date(timestamp).toLocaleDateString(),
            time: new Date(timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}),
            duration: this.formatDuration(duration),
            transcript,
            cost,
            timestamp
        };
        
        this.recordings.unshift(recording);
        this.renderRecordingsList();
        this.resetRecordingUI();
        this.updateStatus(`recording saved • $${cost.toFixed(4)}`);
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
        const recording = this.recordings.find(r => r.id === recordingId);
        if (!recording) return;
        
        this.selectedRecording = recording;
        this.showMeetingView(recording);
    }
    
    showRecordingView() {
        this.currentView = 'recording';
        this.recordingView.style.display = 'flex';
        this.meetingView.style.display = 'none';
        
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
            this.transcriptContent.innerHTML = '<div class="loading">no transcript available</div>';
            return;
        }
        
        // format enhanced transcript if available, otherwise basic transcript
        const formattedTranscript = this.selectedRecording?.transcriptB 
            ? this.formatEnhancedTranscriptForDisplay(transcript)
            : this.formatTranscriptForDisplay(transcript);
        this.transcriptContent.innerHTML = formattedTranscript;
    }
    
    loadSummaryContent() {
        if (!this.selectedRecording) return;
        
        // use pipeline b (enhanced summary) as default, fallback to pipeline a
        const summary = this.selectedRecording?.summaryB || this.selectedRecording?.summary;
        
        if (!summary) {
            this.summaryContent.innerHTML = '<div class="loading">generating summary...</div>';
            // trigger summary generation
            this.generateSummary();
            return;
        }
        
        // format enhanced summary if available, otherwise basic summary
        const formattedSummary = this.selectedRecording?.summaryB 
            ? this.formatEnhancedSummaryForDisplay(summary)
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
            this.summaryContent.innerHTML = '<div class="loading">failed to generate summary</div>';
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
                .replace(/\\n\\n/g, '</p><p>')
                .replace(/\\n/g, '<br>')
                .replace(/\\*\\*(.*?)\\*\\*/g, '<strong>$1</strong>')
                .replace(/^- /gm, '• ');
            
            return `<div class="summary-text"><p>${formatted}</p></div>`;
        }
        
        return '<div class="summary-text">formatted summary content</div>';
    }
    
    formatEnhancedTranscriptForDisplay(transcriptB) {
        if (typeof transcriptB === 'string') {
            // format enhanced transcript with emotional context and conversation blocks
            let formatted = transcriptB
                .replace(/\n/g, '<br>')
                .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
                .replace(/@(\w+)/g, '<span class="speaker-ref">@$1</span>')
                .replace(/_([^_]+)_/g, '<em class="topic-emphasis">$1</em>')
                .replace(/(🟡|🔴|🔵|🟢|🟠)/g, '<span class="emotion-indicator">$1</span>')
                .replace(/\[(\d{1,2}:\d{2}[:\d{2}]*(?:-\d{1,2}:\d{2}[:\d{2}]*)?)\]/g, '<span class="timestamp">[$1]</span>');
            
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
                .replace(/^- /gm, '• ');
            
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