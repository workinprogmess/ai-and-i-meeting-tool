const { ipcRenderer } = require('electron');

class AITranscriptApp {
    constructor() {
        this.isRecording = false;
        this.currentCost = 0;
        this.currentSessionId = null;
        
        this.initializeElements();
        this.bindEvents();
        this.setupIPC();
        this.updateStatus('Ready');
    }
    
    initializeElements() {
        this.recordBtn = document.getElementById('recordBtn');
        this.stopBtn = document.getElementById('stopBtn');
        this.transcript = document.getElementById('transcript');
        this.status = document.getElementById('status');
        this.costCounter = document.getElementById('cost-counter');
    }
    
    bindEvents() {
        this.recordBtn.addEventListener('click', () => this.startRecording());
        this.stopBtn.addEventListener('click', () => this.stopRecording());
    }
    
    setupIPC() {
        // Listen for menu-triggered recording commands
        ipcRenderer.on('start-recording', () => {
            if (!this.isRecording) this.startRecording();
        });
        
        ipcRenderer.on('stop-recording', () => {
            if (this.isRecording) this.stopRecording();
        });
        
        // Listen for audio status updates from main process
        ipcRenderer.on('audio-status', (event, statusData) => {
            this.handleAudioStatus(statusData);
        });
        
        // Listen for real-time transcription updates
        ipcRenderer.on('transcription-update', (event, transcriptionData) => {
            this.handleTranscriptionUpdate(transcriptionData);
        });
    }
    
    async startRecording() {
        try {
            this.isRecording = true;
            this.recordBtn.disabled = true;
            this.stopBtn.disabled = false;
            
            this.updateStatus('Checking permissions...');
            this.clearTranscript();
            
            this.addTranscriptLine('System', 'Checking screen recording permissions...');
            
            // First, test OpenAI API connection
            this.addTranscriptLine('System', 'Testing OpenAI API connection...');
            const apiTest = await ipcRenderer.invoke('test-openai-connection');
            
            if (!apiTest.success) {
                throw new Error(`OpenAI API Error: ${apiTest.error}`);
            }
            
            this.addTranscriptLine('System', '✅ OpenAI API connection successful');
            
            // Trigger screen access to ensure app appears in System Preferences
            await ipcRenderer.invoke('trigger-screen-access');
            
            // Start audio capture via main process
            const result = await ipcRenderer.invoke('start-audio-capture');
            
            if (result.success) {
                this.currentSessionId = Date.now();
                this.updateStatus('Recording');
                this.addTranscriptLine('System', '✅ Permissions granted! Recording started.');
                this.addTranscriptLine('System', `📁 Session: ${result.sessionId || this.currentSessionId}`);
                this.addTranscriptLine('System', '🎙️ Real-time transcription enabled');
                
                // Remove mock transcription loop - we'll use real-time updates
            } else {
                throw new Error(result.error);
            }
            
        } catch (error) {
            console.error('Failed to start recording:', error);
            
            // Provide helpful error messages
            if (error.message.includes('permission')) {
                this.addTranscriptLine('System', '❌ Screen recording permission required');
                this.addTranscriptLine('System', '1. System Preferences should have opened automatically');
                this.addTranscriptLine('System', '2. Go to Security & Privacy > Screen Recording');
                this.addTranscriptLine('System', '3. Check the box next to "ai&i"');
                this.addTranscriptLine('System', '4. Restart the app and try again');
                this.updateStatus('Permission required - See instructions above');
            } else if (error.message.includes('OPENAI_API_KEY')) {
                this.addTranscriptLine('System', '❌ OpenAI API key not found');
                this.addTranscriptLine('System', '1. Create a .env file in the project root');
                this.addTranscriptLine('System', '2. Add: OPENAI_API_KEY=your_api_key_here');
                this.addTranscriptLine('System', '3. Restart the app');
                this.updateStatus('API key required - See instructions above');
            } else {
                this.updateStatus('Error: ' + error.message);
                this.addTranscriptLine('System', '❌ ' + error.message);
            }
            
            this.resetRecordingState();
        }
    }
    
    async stopRecording() {
        try {
            this.updateStatus('Stopping recording...');
            this.addTranscriptLine('System', '⏹️ Stopping recording...');
            
            // Stop audio capture
            const result = await ipcRenderer.invoke('stop-audio-capture');
            
            if (result.success) {
                this.updateStatus('Saving transcript...');
                this.addTranscriptLine('System', `✅ Recording stopped successfully`);
                
                if (result.totalDuration) {
                    this.addTranscriptLine('System', `📊 Duration: ${result.totalDuration.toFixed(1)} seconds`);
                }
                
                if (result.outputPath) {
                    this.addTranscriptLine('System', `💾 Audio saved to: ${result.outputPath}`);
                }
                
                // Save transcript
                await this.saveCurrentTranscript();
                
                this.updateStatus('Ready');
                this.addTranscriptLine('System', '💾 Transcript saved successfully');
                
            } else {
                throw new Error(result.error);
            }
            
        } catch (error) {
            console.error('Failed to stop recording:', error);
            this.updateStatus('Error: ' + error.message);
            this.addTranscriptLine('System', '❌ Failed to stop recording: ' + error.message);
        } finally {
            this.resetRecordingState();
        }
    }
    
    handleTranscriptionUpdate(transcriptionData) {
        try {
            console.log('📝 Received transcription update:', transcriptionData);
            
            // Add transcribed text with proper speaker identification
            if (transcriptionData.segments && transcriptionData.segments.length > 0) {
                // Process each segment with speaker info
                transcriptionData.segments.forEach((segment, index) => {
                    const speaker = segment.speaker || `Speaker ${index + 1}`;
                    this.addTranscriptLine(speaker, segment.text);
                });
            } else {
                // Fallback to basic text with generic speaker
                const speaker = transcriptionData.speakers?.[0] || 'Speaker 1';
                this.addTranscriptLine(speaker, transcriptionData.text);
            }
            
            // Update cost tracking
            if (transcriptionData.cost) {
                this.updateCost(this.currentCost + transcriptionData.cost);
            }
            
            // Show chunk processing indicator (reduced noise)
            if (transcriptionData.chunkIndex !== undefined && transcriptionData.text.trim()) {
                // Only show chunk info if there's actual transcribed text
                console.log(`📊 Processed chunk ${transcriptionData.chunkIndex + 1}`);
            }
            
        } catch (error) {
            console.error('Failed to handle transcription update:', error);
            this.addTranscriptLine('System', '⚠️ Transcription processing error: ' + error.message);
        }
    }
    
    async saveCurrentTranscript() {
        const transcriptData = {
            sessionId: this.currentSessionId,
            timestamp: new Date().toISOString(),
            transcript: this.transcript.innerText,
            cost: this.currentCost
        };
        
        const result = await ipcRenderer.invoke('save-transcript', transcriptData);
        return result;
    }
    
    resetRecordingState() {
        this.isRecording = false;
        this.recordBtn.disabled = false;
        this.stopBtn.disabled = true;
        this.currentSessionId = null;
    }
    
    updateStatus(message) {
        this.status.textContent = message;
        if (message === 'Recording') {
            this.status.classList.add('recording');
        } else {
            this.status.classList.remove('recording');
        }
    }
    
    clearTranscript() {
        this.transcript.innerHTML = '';
    }
    
    addTranscriptLine(speaker, text) {
        const line = document.createElement('div');
        
        // Style differently for actual transcription vs system messages
        if (speaker.startsWith('Speaker') && text.trim()) {
            line.className = 'transcript-line transcription';
            line.innerHTML = `
                <div class="speaker-label transcription-speaker">${speaker}:</div>
                <div class="transcription-text">${text}</div>
            `;
        } else {
            line.className = 'transcript-line system-message';
            line.innerHTML = `
                <div class="speaker-label system-speaker">${speaker}:</div>
                <div class="system-text">${text}</div>
            `;
        }
        
        this.transcript.appendChild(line);
        this.transcript.scrollTop = this.transcript.scrollHeight;
    }
    
    updateCost(newCost) {
        this.currentCost = newCost;
        this.costCounter.textContent = `API Cost: $${newCost.toFixed(4)}`;
    }
    
    handleAudioStatus(statusData) {
        switch (statusData.status) {
            case 'recording':
                this.addTranscriptLine('System', `Audio capture started (Session: ${statusData.sessionId})`);
                break;
            case 'stopped':
                this.addTranscriptLine('System', 
                    `Recording stopped. Duration: ${statusData.totalDuration?.toFixed(1)}s, Chunks: ${statusData.chunks}`);
                break;
            case 'error':
                this.addTranscriptLine('System', `Error: ${statusData.error}`);
                this.updateStatus('Error: ' + statusData.error);
                this.resetRecordingState();
                break;
        }
    }
}

// Initialize the app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new AITranscriptApp();
});