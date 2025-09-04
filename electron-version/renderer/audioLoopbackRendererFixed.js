/**
 * COMPREHENSIVE FIX for audioLoopbackRenderer
 * Addresses:
 * 1. Device switching reliability
 * 2. Recording start delay
 * 3. Post-AirPods audio capture
 * 4. Memory management
 * 5. Edge cases
 */

class AudioLoopbackRendererFixed {
    constructor() {
        this.isRecording = false;
        this.sessionId = null;
        
        // Dual-stream architecture
        this.micRecorder = null;
        this.systemRecorder = null;
        this.micStream = null;
        this.systemStream = null;
        
        // Audio segments
        this.micSegments = [];
        this.systemSegments = [];
        
        // Recording timing
        this.recordingStartTime = null;
        this.actualRecordingStart = null; // Track when audio actually starts
        
        // Audio configuration
        this.audioBitsPerSecond = 256000;
        this.segmentDuration = 5000; // 5-second segments
        
        // Device monitoring
        this.deviceCheckInterval = null; // Poll-based instead of event-based
        this.lastMicLabel = null;
        this.deviceSwitchCount = 0;
        
        console.log('✅ AudioLoopbackRendererFixed initialized');
    }

    async startRecording(sessionId) {
        try {
            if (this.isRecording) {
                throw new Error('Recording already in progress');
            }

            console.log('🎙️ Starting dual-stream recording...');
            
            this.sessionId = sessionId;
            this.recordingStartTime = Date.now();
            this.micSegments = [];
            this.systemSegments = [];
            this.deviceSwitchCount = 0;
            
            const { getLoopbackAudioMediaStream } = require('electron-audio-loopback');
            
            // START IMMEDIATELY - no delays
            console.log('⚡ Fast-starting audio capture...');
            
            // Get microphone stream
            try {
                this.micStream = await navigator.mediaDevices.getUserMedia({
                    audio: {
                        echoCancellation: false,
                        noiseSuppression: false,
                        autoGainControl: false,
                        sampleRate: 48000
                    }
                });
                
                const micTrack = this.micStream.getAudioTracks()[0];
                this.lastMicLabel = micTrack?.label;
                console.log(`✅ Microphone started: ${this.lastMicLabel}`);
            } catch (micError) {
                console.error('❌ Microphone failed:', micError);
                this.micStream = null;
            }
            
            // Get system audio stream
            this.systemStream = await getLoopbackAudioMediaStream();
            console.log('✅ System audio started');
            
            // Create recorders IMMEDIATELY
            if (this.micStream) {
                this.micRecorder = new MediaRecorder(this.micStream, {
                    mimeType: 'audio/webm;codecs=opus',
                    audioBitsPerSecond: this.audioBitsPerSecond
                });
                this.setupMicRecorderHandlers();
                
                // START RECORDING IMMEDIATELY - no delay
                this.micRecorder.start(this.segmentDuration);
                this.actualRecordingStart = Date.now(); // Track actual start
            }
            
            this.systemRecorder = new MediaRecorder(this.systemStream, {
                mimeType: 'audio/webm;codecs=opus',
                audioBitsPerSecond: this.audioBitsPerSecond
            });
            this.setupSystemRecorderHandlers();
            this.systemRecorder.start(this.segmentDuration);
            
            // POLL-BASED device monitoring (more reliable than events)
            this.startDevicePolling();
            
            this.isRecording = true;
            
            const startupTime = Date.now() - this.recordingStartTime;
            console.log(`✅ Recording started in ${startupTime}ms`);
            
            return {
                success: true,
                message: 'Recording started',
                sessionId: sessionId,
                startupTime: startupTime
            };

        } catch (error) {
            console.error('❌ Failed to start recording:', error);
            await this.cleanup();
            return {
                success: false,
                error: error.message
            };
        }
    }

    setupMicRecorderHandlers() {
        this.micRecorder.ondataavailable = (event) => {
            if (event.data.size > 0) {
                this.micSegments.push(event.data);
                const segmentTime = (Date.now() - this.actualRecordingStart) / 1000;
                console.log(`🎤 Mic segment ${this.micSegments.length}: ${event.data.size} bytes at ${segmentTime.toFixed(1)}s`);
            }
        };
        
        this.micRecorder.onerror = (event) => {
            console.error('❌ Mic recorder error:', event.error);
            // Try to recover
            this.attemptMicRecovery();
        };
        
        // Monitor for unexpected stops
        this.micRecorder.onstop = () => {
            console.log('⚠️ Mic recorder stopped');
            if (this.isRecording) {
                console.log('🔄 Attempting to restart mic recorder...');
                this.attemptMicRecovery();
            }
        };
    }

    setupSystemRecorderHandlers() {
        this.systemRecorder.ondataavailable = (event) => {
            if (event.data.size > 0) {
                this.systemSegments.push(event.data);
                console.log(`🔊 System segment ${this.systemSegments.length}: ${event.data.size} bytes`);
            }
        };
        
        this.systemRecorder.onerror = (event) => {
            console.error('❌ System recorder error:', event.error);
        };
    }

    startDevicePolling() {
        // Check every 2 seconds for device changes (more reliable than events)
        this.deviceCheckInterval = setInterval(async () => {
            if (!this.isRecording) return;
            
            try {
                // Check if mic is still working
                if (this.micStream) {
                    const tracks = this.micStream.getAudioTracks();
                    const activeTrack = tracks[0];
                    
                    if (!activeTrack || activeTrack.readyState !== 'live') {
                        console.log('🚨 Microphone disconnected - attempting recovery...');
                        await this.handleMicDisconnect();
                    } else {
                        // Check if device changed (AirPods removed)
                        const currentLabel = activeTrack.label;
                        if (this.lastMicLabel && currentLabel !== this.lastMicLabel) {
                            console.log(`🔄 Device changed: ${this.lastMicLabel} → ${currentLabel}`);
                            this.lastMicLabel = currentLabel;
                        }
                    }
                }
                
                // Also check recorder state
                if (this.micRecorder && this.micRecorder.state === 'inactive') {
                    console.log('🚨 Mic recorder inactive - restarting...');
                    await this.handleMicDisconnect();
                }
                
            } catch (error) {
                console.error('Device poll error:', error);
            }
        }, 2000); // Every 2 seconds
        
        console.log('👂 Device polling started (2s intervals)');
    }

    async handleMicDisconnect() {
        this.deviceSwitchCount++;
        console.log(`🔄 Handling device disconnect (attempt ${this.deviceSwitchCount})...`);
        
        try {
            // Stop old recorder if exists
            if (this.micRecorder && this.micRecorder.state === 'recording') {
                this.micRecorder.stop();
            }
            
            // Stop old stream
            if (this.micStream) {
                this.micStream.getTracks().forEach(track => track.stop());
            }
            
            // Get new microphone (will default to built-in if AirPods gone)
            console.log('🎯 Getting new microphone...');
            this.micStream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    echoCancellation: false,
                    noiseSuppression: false,
                    autoGainControl: false,
                    sampleRate: 48000
                }
            });
            
            const newDevice = this.micStream.getAudioTracks()[0];
            this.lastMicLabel = newDevice?.label;
            console.log(`✅ New microphone connected: ${this.lastMicLabel}`);
            
            // Create new recorder
            this.micRecorder = new MediaRecorder(this.micStream, {
                mimeType: 'audio/webm;codecs=opus',
                audioBitsPerSecond: this.audioBitsPerSecond
            });
            
            // Setup handlers
            this.setupMicRecorderHandlers();
            
            // Start recording again
            this.micRecorder.start(this.segmentDuration);
            console.log('✅ Microphone recording resumed');
            
        } catch (error) {
            console.error('❌ Failed to recover microphone:', error);
            // Continue with system audio only
            this.micRecorder = null;
            this.micStream = null;
        }
    }

    async attemptMicRecovery() {
        // Called when recorder stops unexpectedly
        if (!this.isRecording) return;
        
        console.log('🔧 Attempting mic recovery...');
        await this.handleMicDisconnect();
    }

    async stopRecording() {
        try {
            if (!this.isRecording) {
                throw new Error('No recording in progress');
            }

            console.log('⏹️ Stopping recording...');
            const recordingEndTime = Date.now();
            
            // Stop recorders
            if (this.micRecorder && this.micRecorder.state === 'recording') {
                this.micRecorder.stop();
            }
            if (this.systemRecorder && this.systemRecorder.state === 'recording') {
                this.systemRecorder.stop();
            }
            
            // Wait for final segments
            await new Promise(resolve => setTimeout(resolve, 100));
            
            // Calculate actual duration
            const actualDuration = Math.round((recordingEndTime - this.recordingStartTime) / 1000);
            
            console.log(`✅ Recording stopped`);
            console.log(`📊 Duration: ${actualDuration}s`);
            console.log(`📊 Mic segments: ${this.micSegments.length}`);
            console.log(`📊 System segments: ${this.systemSegments.length}`);
            console.log(`📊 Device switches: ${this.deviceSwitchCount}`);
            
            // Create blobs
            let microphoneBlob = null;
            let systemAudioBlob = null;
            
            if (this.micSegments.length > 0) {
                microphoneBlob = new Blob(this.micSegments, { type: 'audio/webm;codecs=opus' });
                console.log(`📦 Mic audio: ${(microphoneBlob.size / 1024 / 1024).toFixed(2)} MB`);
            }
            
            if (this.systemSegments.length > 0) {
                systemAudioBlob = new Blob(this.systemSegments, { type: 'audio/webm;codecs=opus' });
                console.log(`📦 System audio: ${(systemAudioBlob.size / 1024 / 1024).toFixed(2)} MB`);
            }
            
            const result = {
                success: true,
                message: 'Recording completed',
                sessionId: this.sessionId,
                microphoneBlob: microphoneBlob,
                systemAudioBlob: systemAudioBlob,
                totalDuration: actualDuration,
                micSegments: this.micSegments.length,
                systemSegments: this.systemSegments.length,
                deviceSwitches: this.deviceSwitchCount,
                streamType: (microphoneBlob && systemAudioBlob) ? 'dual-file' : 
                           microphoneBlob ? 'microphone-only' : 'system-only',
                isDualFile: !!(microphoneBlob && systemAudioBlob)
            };
            
            // Cleanup
            this.isRecording = false;
            await this.cleanup();
            
            return result;

        } catch (error) {
            console.error('❌ Failed to stop recording:', error);
            await this.cleanup();
            return {
                success: false,
                error: error.message
            };
        }
    }

    async cleanup() {
        // Stop device polling
        if (this.deviceCheckInterval) {
            clearInterval(this.deviceCheckInterval);
            this.deviceCheckInterval = null;
        }
        
        // Stop streams
        if (this.micStream) {
            this.micStream.getTracks().forEach(track => track.stop());
        }
        if (this.systemStream) {
            this.systemStream.getTracks().forEach(track => track.stop());
        }
        
        // Clear references
        this.micRecorder = null;
        this.systemRecorder = null;
        this.micStream = null;
        this.systemStream = null;
        this.sessionId = null;
        this.micSegments = [];
        this.systemSegments = [];
        
        console.log('🧹 Cleanup complete');
    }

    getRecordingStatus() {
        return {
            isRecording: this.isRecording,
            sessionId: this.sessionId,
            micSegments: this.micSegments?.length || 0,
            systemSegments: this.systemSegments?.length || 0,
            deviceSwitches: this.deviceSwitchCount,
            backend: 'electron-audio-loopback-fixed'
        };
    }
}

// Make available globally with expected name
window.audioLoopbackRenderer = new AudioLoopbackRendererFixed();
console.log('🚀 Fixed audio renderer ready');