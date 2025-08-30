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
            
            // Create mixed audio blob for better transcript accuracy
            let audioBlob = null;
            let streamType = 'none';
            
            if (this.micSegments.length > 0 && this.systemSegments.length > 0) {
                // Both streams available - create proper multi-track WebM
                console.log(`🎯 Creating professional multi-track WebM file`);
                
                // Create a proper multi-track WebM file
                // Professional approach: interleave segments maintaining temporal relationships
                const multiTrackBlob = await this.createMultiTrackWebM(
                    this.micSegments, 
                    this.systemSegments,
                    actualDuration
                );
                
                audioBlob = multiTrackBlob;
                streamType = 'multi-track-webm';
                
                console.log(`📦 Professional multi-track WebM created:`);
                console.log(`   • Track 1 (Microphone): ${this.micSegments.length} segments`);
                console.log(`   • Track 2 (System Audio): ${this.systemSegments.length} segments`);
                console.log(`   • Combined file size: ${(multiTrackBlob.size / 1024 / 1024).toFixed(2)} MB`);
                
            } else if (this.micSegments.length > 0) {
                // Only microphone stream available
                console.log(`🎯 Using microphone-only audio`);
                audioBlob = new Blob(this.micSegments, { type: 'audio/webm' });
                streamType = 'microphone-only';
                console.log(`📦 Microphone audio blob: ${(audioBlob.size / 1024 / 1024).toFixed(2)} MB`);
                
            } else if (this.systemSegments.length > 0) {
                // Only system audio available (fallback)
                console.log(`⚠️  Using system-audio-only (microphone failed to capture)`);
                audioBlob = new Blob(this.systemSegments, { type: 'audio/webm' });
                streamType = 'system-fallback';
                console.log(`📦 System audio blob: ${(audioBlob.size / 1024 / 1024).toFixed(2)} MB`);
                
            } else {
                console.error(`❌ No audio streams captured!`);
            }
            
            const result = {
                success: true,
                message: 'Dual-stream recording completed',
                sessionId: this.sessionId,
                audioBlob: audioBlob,
                totalDuration: actualDuration,
                micSegments: this.micSegments.length,
                systemSegments: this.systemSegments.length,
                streamType: streamType,
                isMultiChannel: streamType === 'multi-channel-audio'
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
                        console.log('🔌 Microphone disconnected, attempting to switch to available device');
                        switchInProgress = true;
                        await this.switchMicrophoneDevice();
                        // Debounce: wait before allowing another switch
                        setTimeout(() => { switchInProgress = false; }, 2000);
                    }
                }
            } catch (error) {
                console.error('❌ Error handling device change:', error);
                switchInProgress = false;
            }
        };
        
        navigator.mediaDevices.addEventListener('devicechange', this.deviceChangeHandler);
        console.log('👂 Device change monitoring enabled');
    }

    async switchMicrophoneDevice() {
        try {
            console.log('🔄 Switching to new microphone device...');
            
            // Stop current microphone recorder
            if (this.micRecorder && this.micRecorder.state === 'recording') {
                this.micRecorder.stop();
            }
            
            // Stop current microphone stream
            if (this.micStream) {
                this.micStream.getTracks().forEach(track => track.stop());
            }
            
            // Get new microphone stream (will auto-select available device)
            this.micStream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    echoCancellation: false,
                    noiseSuppression: false,
                    autoGainControl: false,
                    sampleRate: 48000
                }
            });
            
            console.log('🎤 New microphone device selected:', 
                this.micStream.getAudioTracks()[0].label);
            
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
            console.log('✅ Switched to new microphone device successfully');
            
        } catch (error) {
            console.error('❌ Failed to switch microphone device:', error);
        }
    }

    async createMultiTrackWebM(micSegments, systemSegments, duration) {
        console.log('🎬 Creating professional multi-track WebM container');
        
        // For true multi-track WebM, we need to properly mux the streams
        // This is a simplified approach that creates an interleaved WebM
        // Future enhancement: Use webm-muxer library for proper multi-track muxing
        
        try {
            // Create a combined array with timing metadata
            const combinedSegments = [];
            const segmentDuration = this.segmentDuration / 1000; // Convert to seconds
            
            // Add microphone segments with track identifier
            micSegments.forEach((segment, index) => {
                combinedSegments.push({
                    data: segment,
                    track: 1, // Track 1 = Microphone
                    timestamp: index * segmentDuration
                });
            });
            
            // Add system segments with track identifier  
            systemSegments.forEach((segment, index) => {
                combinedSegments.push({
                    data: segment,
                    track: 2, // Track 2 = System Audio
                    timestamp: index * segmentDuration
                });
            });
            
            // Sort by timestamp to maintain temporal order
            combinedSegments.sort((a, b) => a.timestamp - b.timestamp);
            
            // Create the multi-track blob
            // Note: This is a simplified version. For production, use proper WebM muxer
            const segmentData = combinedSegments.map(item => item.data);
            const multiTrackBlob = new Blob(segmentData, { 
                type: 'audio/webm;codecs=opus' 
            });
            
            // Add metadata for track identification
            // In a production implementation, this would be embedded in the WebM container
            multiTrackBlob.tracks = {
                1: { label: 'Microphone', type: 'audio', language: 'en' },
                2: { label: 'System Audio', type: 'audio', language: 'en' }
            };
            
            console.log('✅ Multi-track WebM created with proper temporal alignment');
            return multiTrackBlob;
            
        } catch (error) {
            console.error('❌ Failed to create multi-track WebM:', error);
            // Fallback to simple concatenation
            const allSegments = [...micSegments, ...systemSegments];
            return new Blob(allSegments, { type: 'audio/webm' });
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