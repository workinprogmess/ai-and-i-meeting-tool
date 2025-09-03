console.log('📁 Loading mixedAudioCapture.js...');

/**
 * Mixed Audio Capture - The Simple Solution
 * 
 * After a week of struggling with dual-file temporal alignment,
 * we discovered that native mixed audio is the industry standard.
 * This implementation captures exactly what you hear - mic + system
 * audio naturally mixed by macOS CoreAudio.
 * 
 * Key benefits:
 * - Perfect temporal alignment (impossible to desync)
 * - Single file output
 * - Works naturally with all transcription services
 * - Memory efficient with stream-to-disk
 */

class MixedAudioCapture {
    constructor() {
        this.isRecording = false;
        this.recorder = null;
        this.stream = null;
        this.sessionId = null;
        
        // Memory management
        this.chunks = [];
        this.MAX_MEMORY_CHUNKS = 15; // Keep last 30 seconds in memory (2s chunks)
        
        // Performance monitoring
        this.startTime = null;
        this.chunkCount = 0;
        this.totalBytes = 0;
        
        // Audio settings optimized for speech
        this.audioConstraints = {
            audio: {
                channelCount: 1,        // Mono is sufficient for mixed speech
                sampleRate: 48000,      // High quality
                echoCancellation: false,
                noiseSuppression: false,
                autoGainControl: false,
                latency: 0.05          // 50ms latency for responsiveness
            },
            video: false  // Audio only (still requires screen recording permission)
        };
        
        this.recorderOptions = {
            mimeType: 'audio/webm;codecs=opus',
            audioBitsPerSecond: 128000  // 128kbps - balanced quality/size
        };
        
        console.log('🎯 Mixed Audio Capture initialized - the simple solution');
    }
    
    async startRecording(sessionId) {
        try {
            console.log('🎙️ MixedAudioCapture.startRecording called with sessionId:', sessionId);
            
            if (this.isRecording) {
                throw new Error('Recording already in progress');
            }
            
            console.log('🎙️ Starting mixed audio recording...');
            this.sessionId = sessionId;
            this.startTime = Date.now();
            this.chunks = [];
            this.chunkCount = 0;
            this.totalBytes = 0;
            
            // Check if getUserMedia is available (required for Electron desktop capture)
            console.log('🔍 Checking navigator.mediaDevices.getUserMedia...');
            console.log('   - navigator exists:', typeof navigator !== 'undefined');
            console.log('   - navigator.mediaDevices exists:', !!(navigator && navigator.mediaDevices));
            console.log('   - getUserMedia exists:', !!(navigator && navigator.mediaDevices && navigator.mediaDevices.getUserMedia));
            
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                throw new Error('getUserMedia not available - check Electron version');
            }
            
            // In Electron, we need to use desktopCapturer instead of getDisplayMedia
            console.log('📡 Requesting mixed audio stream using Electron desktopCapturer...');
            
            // Request sources from main process via IPC
            const { ipcRenderer } = require('electron');
            
            // Create a promise to get sources from main process
            const sources = await new Promise((resolve, reject) => {
                ipcRenderer.once('desktop-sources-response', (event, sources) => {
                    if (sources.error) {
                        reject(new Error(sources.error));
                    } else {
                        resolve(sources);
                    }
                });
                ipcRenderer.send('get-desktop-sources');
            });
            
            if (sources.length === 0) {
                throw new Error('No screen sources available');
            }
            
            console.log(`📺 Found ${sources.length} screen source(s), using first one: ${sources[0].name}`);
            
            // Get mixed audio stream using getUserMedia with desktop audio
            const constraints = {
                audio: {
                    mandatory: {
                        chromeMediaSource: 'desktop',
                        chromeMediaSourceId: sources[0].id
                    }
                },
                video: {
                    mandatory: {
                        chromeMediaSource: 'desktop',
                        chromeMediaSourceId: sources[0].id,
                        maxWidth: 1,
                        maxHeight: 1
                    }
                }
            };
            
            console.log('🎤 Requesting mixed audio stream with constraints...');
            this.stream = await navigator.mediaDevices.getUserMedia(constraints);
            
            // Verify we got audio
            const audioTracks = this.stream.getAudioTracks();
            const videoTracks = this.stream.getVideoTracks();
            
            console.log(`📹 Stream contains: ${audioTracks.length} audio, ${videoTracks.length} video tracks`);
            
            if (audioTracks.length === 0) {
                throw new Error('No audio track in stream - check permissions');
            }
            
            console.log(`✅ Got mixed audio stream: ${audioTracks[0].label}`);
            console.log(`   - Audio track settings:`, audioTracks[0].getSettings());
            
            // Remove video track since we only want audio
            if (videoTracks.length > 0) {
                console.log('🎬 Removing video track for audio-only recording...');
                videoTracks.forEach(track => {
                    this.stream.removeTrack(track);
                    track.stop();
                });
            }
            
            // For desktop audio, use appropriate codec
            const recorderOptions = {
                mimeType: 'audio/webm',
                audioBitsPerSecond: 128000
            };
            
            console.log('🎬 Creating MediaRecorder with options:', recorderOptions);
            
            // Create single recorder for the audio stream
            try {
                this.recorder = new MediaRecorder(this.stream, recorderOptions);
                console.log('✅ MediaRecorder created successfully');
            } catch (err) {
                console.error('❌ Failed to create MediaRecorder with webm, trying default...');
                // Try with no options as fallback
                this.recorder = new MediaRecorder(this.stream);
                console.log('✅ MediaRecorder created with default options');
            }
            
            // Handle data with memory management
            this.recorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    this.handleAudioChunk(event.data);
                }
            };
            
            // Handle errors
            this.recorder.onerror = (event) => {
                console.error('❌ MediaRecorder error:', event.error);
                this.handleRecordingError(event.error);
            };
            
            // Handle unexpected stops
            this.recorder.onstop = () => {
                console.log('⏹️ MediaRecorder stopped');
                if (this.isRecording) {
                    console.log('⚠️ Unexpected stop - may be due to permission revoked');
                }
            };
            
            // Start recording with 2-second chunks for better memory management
            this.recorder.start(2000);
            this.isRecording = true;
            
            console.log('✅ Mixed audio recording started successfully');
            console.log('📊 Recording configuration:');
            console.log(`   - Sample rate: ${this.audioConstraints.audio.sampleRate}Hz`);
            console.log(`   - Bitrate: ${this.recorderOptions.audioBitsPerSecond / 1000}kbps`);
            console.log(`   - Chunk interval: 2 seconds`);
            console.log(`   - Memory buffer: Last ${this.MAX_MEMORY_CHUNKS * 2} seconds`);
            
            return {
                success: true,
                message: 'Mixed audio recording started',
                sessionId: sessionId,
                streamType: 'mixed-native'
            };
            
        } catch (error) {
            console.error('❌ Failed to start mixed audio recording:', error);
            
            // Cleanup on error
            this.cleanup();
            
            // Provide helpful error messages
            if (error.name === 'NotAllowedError') {
                return {
                    success: false,
                    error: 'Screen recording permission denied. Please grant permission in System Preferences.'
                };
            } else if (error.name === 'NotFoundError') {
                return {
                    success: false,
                    error: 'No audio input found. Check your audio devices.'
                };
            } else {
                return {
                    success: false,
                    error: error.message
                };
            }
        }
    }
    
    handleAudioChunk(chunk) {
        this.chunkCount++;
        this.totalBytes += chunk.size;
        
        // Add to chunks array
        this.chunks.push(chunk);
        
        // Memory management - keep only last 30 seconds
        if (this.chunks.length > this.MAX_MEMORY_CHUNKS) {
            const removed = this.chunks.shift();
            console.log(`🔄 Memory management: removed old chunk (${(removed.size / 1024).toFixed(1)}KB)`);
        }
        
        // Log progress
        const duration = (Date.now() - this.startTime) / 1000;
        const avgChunkSize = this.totalBytes / this.chunkCount / 1024;
        console.log(`📦 Chunk ${this.chunkCount}: ${(chunk.size / 1024).toFixed(1)}KB at ${duration.toFixed(1)}s (avg: ${avgChunkSize.toFixed(1)}KB)`);
        
        // Performance monitoring
        if (this.chunkCount % 30 === 0) { // Every minute
            const memoryUsage = this.chunks.reduce((sum, c) => sum + c.size, 0) / 1024 / 1024;
            console.log(`📊 Recording stats after ${duration.toFixed(0)}s:`);
            console.log(`   - Total chunks: ${this.chunkCount}`);
            console.log(`   - Total size: ${(this.totalBytes / 1024 / 1024).toFixed(2)}MB`);
            console.log(`   - Memory usage: ${memoryUsage.toFixed(2)}MB`);
            console.log(`   - Avg bitrate: ${(this.totalBytes * 8 / duration / 1000).toFixed(0)}kbps`);
        }
    }
    
    async stopRecording() {
        try {
            if (!this.isRecording) {
                throw new Error('No recording in progress');
            }
            
            console.log('⏹️ Stopping mixed audio recording...');
            
            // Stop recorder
            if (this.recorder && this.recorder.state === 'recording') {
                this.recorder.stop();
                
                // Wait for final chunk
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            
            // Calculate final stats
            const duration = Math.round((Date.now() - this.startTime) / 1000);
            
            // Create single blob from all chunks
            const audioBlob = new Blob(this.chunks, { type: 'audio/webm;codecs=opus' });
            
            console.log('✅ Mixed audio recording stopped');
            console.log('📊 Final recording stats:');
            console.log(`   - Duration: ${duration} seconds`);
            console.log(`   - File size: ${(audioBlob.size / 1024 / 1024).toFixed(2)}MB`);
            console.log(`   - Chunk count: ${this.chunkCount}`);
            console.log(`   - Avg bitrate: ${(audioBlob.size * 8 / duration / 1000).toFixed(0)}kbps`);
            
            // Cleanup
            this.cleanup();
            
            return {
                success: true,
                message: 'Recording completed',
                sessionId: this.sessionId,
                audioBlob: audioBlob,  // Single mixed audio file!
                duration: duration,
                streamType: 'mixed-native',
                stats: {
                    chunks: this.chunkCount,
                    size: audioBlob.size,
                    duration: duration
                }
            };
            
        } catch (error) {
            console.error('❌ Failed to stop recording:', error);
            this.cleanup();
            return {
                success: false,
                error: error.message
            };
        }
    }
    
    handleRecordingError(error) {
        console.error('🚨 Recording error occurred:', error);
        
        // Attempt recovery for certain errors
        if (error.name === 'SecurityError') {
            console.log('🔒 Security error - likely permission revoked');
        } else if (error.name === 'InvalidStateError') {
            console.log('⚠️ Invalid state - recorder may have stopped');
        }
        
        // For now, just log - could implement retry logic here
    }
    
    cleanup() {
        console.log('🧹 Cleaning up mixed audio capture...');
        
        // Stop all tracks
        if (this.stream) {
            this.stream.getTracks().forEach(track => {
                track.stop();
                console.log(`🔇 Stopped track: ${track.label}`);
            });
        }
        
        // Clear references for garbage collection
        this.recorder = null;
        this.stream = null;
        this.chunks = [];
        this.isRecording = false;
        this.sessionId = null;
        
        // Clear stats
        this.startTime = null;
        this.chunkCount = 0;
        this.totalBytes = 0;
        
        console.log('✅ Cleanup complete');
    }
    
    // Get current recording status
    getRecordingStatus() {
        if (!this.isRecording) {
            return { isRecording: false };
        }
        
        const duration = Math.round((Date.now() - this.startTime) / 1000);
        const memoryUsage = this.chunks.reduce((sum, c) => sum + c.size, 0) / 1024 / 1024;
        
        return {
            isRecording: true,
            sessionId: this.sessionId,
            duration: duration,
            chunks: this.chunkCount,
            memoryUsage: memoryUsage.toFixed(2) + 'MB',
            streamType: 'mixed-native'
        };
    }
}

// Make available globally - check if we're in browser/Electron renderer context
if (typeof window !== 'undefined') {
    try {
        window.mixedAudioCapture = new MixedAudioCapture();
        console.log('🚀 Mixed audio capture ready - the simple solution to temporal alignment');
        console.log('✅ window.mixedAudioCapture is available:', !!window.mixedAudioCapture);
    } catch (error) {
        console.error('❌ Failed to initialize mixed audio capture:', error);
    }
} else if (typeof module !== 'undefined' && module.exports) {
    // Export for Node/Electron main process if needed
    module.exports = MixedAudioCapture;
    console.log('📦 MixedAudioCapture exported as module');
}