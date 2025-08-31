/**
 * Renderer-side audio capture using electron-audio-loopback
 * Communicates with main process via IPC for audio recording
 */
class AudioLoopbackRenderer {
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
        
        // Audio configuration
        this.audioBitsPerSecond = 128000;
        this.segmentDuration = 60000; // 60-second segments
        
        // Device change monitoring
        this.deviceChangeHandler = null;
        
        console.log('✅ AudioLoopbackRenderer initialized');
    }

    async startRecording(sessionId) {
        try {
            if (this.isRecording) {
                throw new Error('Recording already in progress');
            }

            console.log('🎙️ Starting dual-stream recording in renderer...');
            
            this.sessionId = sessionId;
            this.recordingStartTime = Date.now();
            this.micSegments = [];
            this.systemSegments = [];
            
            // Import electron-audio-loopback (available in renderer)
            const { getLoopbackAudioMediaStream } = require('electron-audio-loopback');
            
            // Start microphone capture with enhanced AirPods debugging
            console.log('📱 Initializing microphone stream...');
            console.log('🎧 AirPods/Bluetooth headset compatibility check...');
            
            // First, enumerate available audio devices
            console.log('🔍 Enumerating available audio input devices...');
            try {
                const devices = await navigator.mediaDevices.enumerateDevices();
                const audioInputs = devices.filter(device => device.kind === 'audioinput');
                console.log(`📱 Found ${audioInputs.length} audio input devices:`);
                audioInputs.forEach((device, index) => {
                    console.log(`   ${index + 1}. ${device.label || 'Unknown Device'} (ID: ${device.deviceId.substring(0, 8)}...)`);
                    if (device.label.toLowerCase().includes('airpods')) {
                        console.log(`   🎧 ⬆️ AirPods detected: ${device.label}`);
                    }
                });
            } catch (enumError) {
                console.warn('⚠️  Could not enumerate audio devices:', enumError.message);
            }
            
            try {
                // Proper microphone capture using getUserMedia (adaptive device selection)
                console.log('🎯 Using getUserMedia for microphone capture (adaptive device selection)');
                
                // Get optimal audio constraints for meeting recording
                this.micStream = await navigator.mediaDevices.getUserMedia({
                    audio: {
                        // Let system choose best available microphone device
                        // This will automatically use AirPods if connected, built-in mic otherwise
                        echoCancellation: false,  // Better for meeting transcription
                        noiseSuppression: false,  // Preserve natural audio
                        autoGainControl: false,   // Maintain consistent volume
                        sampleRate: 48000        // High quality audio
                    }
                });
                
                console.log('✅ Microphone stream created:', {
                    id: this.micStream.id,
                    tracks: this.micStream.getAudioTracks().length,
                    active: this.micStream.active
                });
                
                // Enhanced diagnostic for AirPods/Bluetooth headset compatibility
                this.micStream.getAudioTracks().forEach((track, index) => {
                    console.log(`🎤 Microphone track ${index}:`, {
                        label: track.label,
                        kind: track.kind,
                        enabled: track.enabled,
                        readyState: track.readyState,
                        constraints: track.getConstraints(),
                        settings: track.getSettings()
                    });
                    
                    // Check if this looks like an AirPods microphone
                    if (track.label.toLowerCase().includes('airpods') || 
                        track.label.toLowerCase().includes('bluetooth')) {
                        console.log(`🎧 Detected Bluetooth audio device: ${track.label}`);
                    }
                });
                
            } catch (micError) {
                console.error('❌ Microphone stream initialization failed:', micError);
                console.log('🔧 This might be an AirPods/Bluetooth compatibility issue');
                // Continue with system audio only
                this.micStream = null;
            }
            
            // Start system audio capture using electron-audio-loopback (getDisplayMedia wrapper)
            console.log('🔊 Initializing system audio stream...');
            console.log('🎧 Note: System audio includes output to AirPods/headsets/speakers');
            console.log('🔍 electron-audio-loopback uses getDisplayMedia() for system audio capture');
            this.systemStream = await getLoopbackAudioMediaStream();
            
            console.log('✅ System audio stream created:', {
                id: this.systemStream.id,
                tracks: this.systemStream.getAudioTracks().length
            });
            
            // Diagnostic: Log audio track details for AirPods/headset compatibility
            this.systemStream.getAudioTracks().forEach((track, index) => {
                console.log(`🔊 System audio track ${index}:`, {
                    label: track.label,
                    kind: track.kind,
                    enabled: track.enabled,
                    readyState: track.readyState
                });
            });
            
            // Create MediaRecorders with segmentation (handle null microphone stream)
            if (this.micStream) {
                this.micRecorder = new MediaRecorder(this.micStream, {
                    mimeType: 'audio/webm;codecs=opus',
                    audioBitsPerSecond: this.audioBitsPerSecond
                });
            } else {
                console.log('⚠️  Microphone recorder not created (stream unavailable)');
                this.micRecorder = null;
            }
            
            this.systemRecorder = new MediaRecorder(this.systemStream, {
                mimeType: 'audio/webm;codecs=opus',
                audioBitsPerSecond: this.audioBitsPerSecond
            });
            
            // Set up microphone recorder events (if available)
            if (this.micRecorder) {
                this.micRecorder.ondataavailable = (event) => {
                    if (event.data.size > 0) {
                        const timestamp = new Date().toISOString();
                        const deviceLabel = this.micStream.getAudioTracks()[0]?.label || 'Unknown';
                        this.micSegments.push(event.data);
                        console.log(`🎤 [${timestamp}] Mic segment: ${event.data.size} bytes, device: "${deviceLabel}" (${this.micSegments.length} total segments)`);
                    }
                };
                
                this.micRecorder.onerror = (event) => {
                    console.error('❌ Microphone recorder error:', event.error);
                };
            }
            
            // Set up system audio recorder events
            this.systemRecorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    const timestamp = new Date().toISOString();
                    const deviceLabel = this.systemStream.getAudioTracks()[0]?.label || 'System Audio';
                    this.systemSegments.push(event.data);
                    console.log(`🔊 [${timestamp}] System segment: ${event.data.size} bytes, source: "${deviceLabel}" (${this.systemSegments.length} total segments)`);
                }
            };
            
            this.systemRecorder.onerror = (event) => {
                console.error('❌ System audio recorder error:', event.error);
            };
            
            // Start recording with segmentation
            if (this.micRecorder) {
                this.micRecorder.start(this.segmentDuration);
                console.log('🎤 Microphone recording started');
            } else {
                console.log('⚠️  Microphone recording skipped (recorder unavailable)');
            }
            
            this.systemRecorder.start(this.segmentDuration);
            console.log('🔊 System audio recording started');
            
            // Set up device change monitoring for seamless switching
            this.setupDeviceChangeMonitoring();
            
            this.isRecording = true;
            
            console.log(`✅ Dual-stream recording started for session ${sessionId}`);
            
            return {
                success: true,
                message: 'Dual-stream electron-audio-loopback recording started',
                sessionId: sessionId
            };

        } catch (error) {
            console.error('❌ Failed to start dual-stream recording:', error);
            await this.cleanup();
            return {
                success: false,
                error: error.message
            };
        }
    }

    async stopRecording() {
        try {
            if (!this.isRecording) {
                throw new Error('No recording in progress');
            }

            console.log('⏹️ Stopping dual-stream recording...');
            const recordingEndTime = Date.now();
            
            // Stop MediaRecorders
            if (this.micRecorder && this.micRecorder.state === 'recording') {
                this.micRecorder.stop();
                console.log('🎤 Microphone recording stopped');
            } else if (this.micRecorder) {
                console.log(`⚠️  Microphone recorder was in ${this.micRecorder.state} state`);
            } else {
                console.log('⚠️  No microphone recorder to stop');
            }
            
            if (this.systemRecorder && this.systemRecorder.state === 'recording') {
                this.systemRecorder.stop();
                console.log('🔊 System audio recording stopped');
            }
            
            // Wait for final data events
            await new Promise(resolve => setTimeout(resolve, 100));
            
            // Calculate actual duration
            const actualDuration = Math.round((recordingEndTime - this.recordingStartTime) / 1000);
            
            console.log(`✅ Dual-stream recording stopped`);
            console.log(`📊 Duration: ${actualDuration}s`);
            console.log(`📊 Microphone segments: ${this.micSegments.length}`);
            console.log(`📊 System audio segments: ${this.systemSegments.length}`);
            
            // Detailed diagnostic of captured segments
            console.log(`🔍 COMPREHENSIVE STREAM ANALYSIS:`);
            console.log(`   • Recording duration: ${actualDuration}s`);
            console.log(`   • Microphone segments: ${this.micSegments.length}`);
            console.log(`   • System audio segments: ${this.systemSegments.length}`);
            
            if (this.micSegments.length > 0) {
                const totalMicSize = this.micSegments.reduce((sum, segment) => sum + segment.size, 0);
                console.log(`   • Microphone total size: ${(totalMicSize / 1024 / 1024).toFixed(2)} MB`);
                console.log(`   • Average mic segment size: ${(totalMicSize / this.micSegments.length / 1024).toFixed(1)} KB`);
            } else {
                console.log(`   ⚠️  NO MICROPHONE DATA CAPTURED`);
            }
            
            if (this.systemSegments.length > 0) {
                const totalSystemSize = this.systemSegments.reduce((sum, segment) => sum + segment.size, 0);
                console.log(`   • System audio total size: ${(totalSystemSize / 1024 / 1024).toFixed(2)} MB`);
                console.log(`   • Average system segment size: ${(totalSystemSize / this.systemSegments.length / 1024).toFixed(1)} KB`);
            } else {
                console.log(`   ⚠️  NO SYSTEM AUDIO DATA CAPTURED`);
            }
            
            // Analysis of data distribution for speaker identification
            const totalSize = (this.micSegments.reduce((sum, s) => sum + s.size, 0)) + 
                            (this.systemSegments.reduce((sum, s) => sum + s.size, 0));
            if (totalSize > 0) {
                const micPercentage = ((this.micSegments.reduce((sum, s) => sum + s.size, 0)) / totalSize * 100).toFixed(1);
                const systemPercentage = ((this.systemSegments.reduce((sum, s) => sum + s.size, 0)) / totalSize * 100).toFixed(1);
                console.log(`   • Data distribution: ${micPercentage}% mic, ${systemPercentage}% system`);
            }
            
            // Create separate audio blobs for two-file approach
            let microphoneBlob = null;
            let systemAudioBlob = null;
            let streamType = 'none';
            
            if (this.micSegments.length > 0) {
                // Create microphone audio file
                console.log(`🎤 Creating microphone audio file`);
                microphoneBlob = new Blob(this.micSegments, { type: 'audio/webm;codecs=opus' });
                console.log(`📦 Microphone audio: ${(microphoneBlob.size / 1024 / 1024).toFixed(2)} MB, ${this.micSegments.length} segments`);
            } else {
                console.warn(`⚠️  No microphone audio captured`);
            }
            
            if (this.systemSegments.length > 0) {
                // Create system audio file
                console.log(`🔊 Creating system audio file`);
                systemAudioBlob = new Blob(this.systemSegments, { type: 'audio/webm;codecs=opus' });
                console.log(`📦 System audio: ${(systemAudioBlob.size / 1024 / 1024).toFixed(2)} MB, ${this.systemSegments.length} segments`);
            } else {
                console.warn(`⚠️  No system audio captured`);
            }
            
            // Determine stream type for logging
            if (microphoneBlob && systemAudioBlob) {
                streamType = 'dual-file';
                console.log(`✅ Two-file approach: Both microphone and system audio captured separately`);
            } else if (microphoneBlob) {
                streamType = 'microphone-only';
                console.log(`🎯 Microphone-only recording`);
            } else if (systemAudioBlob) {
                streamType = 'system-only';
                console.log(`🔊 System-audio-only recording (no microphone)`);
            } else {
                console.error(`❌ No audio streams captured!`);
            }
            
            const result = {
                success: true,
                message: 'Dual-stream recording completed',
                sessionId: this.sessionId,
                microphoneBlob: microphoneBlob,
                systemAudioBlob: systemAudioBlob,
                totalDuration: actualDuration,
                micSegments: this.micSegments.length,
                systemSegments: this.systemSegments.length,
                streamType: streamType,
                isDualFile: streamType === 'dual-file'
            };
            
            // Clean up
            this.isRecording = false;
            await this.cleanup();
            
            return result;

        } catch (error) {
            console.error('❌ Failed to stop dual-stream recording:', error);
            await this.cleanup();
            return {
                success: false,
                error: error.message
            };
        }
    }

    async cleanup() {
        // Remove device change listener
        if (this.deviceChangeHandler) {
            navigator.mediaDevices.removeEventListener('devicechange', this.deviceChangeHandler);
            this.deviceChangeHandler = null;
            console.log('👂 Device change monitoring disabled');
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
        
        console.log('🧹 AudioLoopbackRenderer cleaned up');
    }

    setupDeviceChangeMonitoring() {
        // Monitor for audio device changes during recording
        let switchInProgress = false;
        this.deviceChangeHandler = async () => {
            if (!this.isRecording || switchInProgress) return;
            
            console.log('🔄 Audio device change detected during recording');
            
            try {
                // Check if current microphone stream is still active
                if (this.micStream) {
                    const tracks = this.micStream.getAudioTracks();
                    const activeTrack = tracks.find(track => track.readyState === 'live');
                    
                    if (!activeTrack) {
                        console.log('🔌 Microphone disconnected (likely AirPods removed), switching to built-in mic');
                        switchInProgress = true;
                        await this.switchMicrophoneDevice();
                        // Debounce: shorter wait for more responsive switching
                        setTimeout(() => { switchInProgress = false; }, 500);
                    }
                }
                
                // Also monitor track state changes directly
                if (this.micStream) {
                    this.micStream.getAudioTracks().forEach(track => {
                        if (track.readyState === 'ended') {
                            console.log('🚨 Microphone track ended unexpectedly, forcing device switch');
                            if (!switchInProgress) {
                                switchInProgress = true;
                                this.switchMicrophoneDevice();
                                setTimeout(() => { switchInProgress = false; }, 500);
                            }
                        }
                    });
                }
            } catch (error) {
                console.error('❌ Error handling device change:', error);
                switchInProgress = false;
            }
        };
        
        navigator.mediaDevices.addEventListener('devicechange', this.deviceChangeHandler);
        console.log('👂 Device change monitoring enabled (AirPods removal detection)');
    }

    async switchMicrophoneDevice() {
        try {
            console.log('🔄 Switching to new microphone device (AirPods → Built-in mic)...');
            
            // First enumerate available devices to see what we have
            const devices = await navigator.mediaDevices.enumerateDevices();
            const audioInputs = devices.filter(device => device.kind === 'audioinput');
            console.log(`📱 Available microphones after AirPods removal:`);
            audioInputs.forEach((device, index) => {
                console.log(`   ${index + 1}. ${device.label || 'Unknown Device'}`);
            });
            
            // Stop current microphone recorder gracefully
            if (this.micRecorder && this.micRecorder.state === 'recording') {
                console.log('⏹️ Stopping current microphone recorder...');
                this.micRecorder.stop();
            }
            
            // Stop current microphone stream
            if (this.micStream) {
                console.log('🔌 Disconnecting from current microphone stream...');
                this.micStream.getTracks().forEach(track => track.stop());
            }
            
            // Wait a moment for device cleanup
            await new Promise(resolve => setTimeout(resolve, 200));
            
            // Get new microphone stream (should auto-select built-in mic)
            console.log('🎯 Attempting to connect to available microphone device...');
            this.micStream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    echoCancellation: false,
                    noiseSuppression: false,
                    autoGainControl: false,
                    sampleRate: 48000
                }
            });
            
            const newDevice = this.micStream.getAudioTracks()[0];
            console.log('🎤 Successfully connected to new microphone:', newDevice.label);
            console.log('📊 New device settings:', newDevice.getSettings());
            
            // Create new recorder
            this.micRecorder = new MediaRecorder(this.micStream, {
                mimeType: 'audio/webm;codecs=opus',
                audioBitsPerSecond: this.audioBitsPerSecond
            });
            
            // Set up event handlers
            this.micRecorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    const timestamp = new Date().toISOString();
                    const deviceLabel = this.micStream.getAudioTracks()[0]?.label || 'Switched Device';
                    this.micSegments.push(event.data);
                    console.log(`🔄 [${timestamp}] SWITCHED Mic segment: ${event.data.size} bytes, device: "${deviceLabel}" (${this.micSegments.length} total segments)`);
                }
            };
            
            this.micRecorder.onerror = (event) => {
                console.error('❌ New microphone recorder error:', event.error);
            };
            
            // Start recording with new device
            this.micRecorder.start(this.segmentDuration);
            console.log('✅ Device switch complete - recording resumed with built-in microphone');
            
        } catch (error) {
            console.error('❌ Failed to switch microphone device:', error);
            console.log('⚠️ Microphone recording will continue with system audio only');
        }
    }


    getRecordingStatus() {
        return {
            isRecording: this.isRecording,
            sessionId: this.sessionId,
            micSegments: this.micSegments?.length || 0,
            systemSegments: this.systemSegments?.length || 0,
            backend: 'electron-audio-loopback-renderer'
        };
    }
}

// Make available globally
window.audioLoopbackRenderer = new AudioLoopbackRenderer();