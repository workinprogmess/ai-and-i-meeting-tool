const { EventEmitter } = require('events');
const fs = require('fs').promises;
const path = require('path');

/**
 * AudioCaptureLoopback using electron-audio-loopback (milestone 3.2)
 * Replaces FFmpeg + AVFoundation to eliminate 10-11% audio data loss
 * Implements dual-stream capture for speaker recognition like Granola
 */
class AudioCaptureLoopback extends EventEmitter {
    constructor() {
        super();
        
        this.isRecording = false;
        this.sessionId = null;
        
        // Dual-stream architecture
        this.micRecorder = null;
        this.systemRecorder = null;
        this.micStream = null;
        this.systemStream = null;
        
        // Audio segments for memory management
        this.micSegments = [];
        this.systemSegments = [];
        
        // Recording timing
        this.recordingStartTime = null;
        this.recordingEndTime = null;
        
        // Audio configuration
        this.sampleRate = 48000; // Higher quality than FFmpeg's 16kHz
        this.channels = 1; // Mono
        this.audioBitsPerSecond = 128000; // Good quality opus encoding
        this.segmentDuration = 60000; // 60-second segments for memory management
        
        // Temporary file paths
        this.micTempPath = null;
        this.systemTempPath = null;
        
        console.log('✅ AudioCaptureLoopback initialized with electron-audio-loopback + dual-stream architecture');
    }

    async checkPermissions() {
        console.log('🔐 electron-audio-loopback will request permissions on first use');
        console.log('🔐 Microphone permission required for user audio');
        console.log('🔐 Screen recording permission required for system audio');
        return true;
    }

    async startRecording(sessionId) {
        try {
            if (this.isRecording) {
                throw new Error('Recording already in progress');
            }

            console.log('🎙️ Starting dual-stream recording with electron-audio-loopback...');
            
            this.sessionId = sessionId;
            this.recordingStartTime = Date.now();
            this.micSegments = [];
            this.systemSegments = [];
            
            // Create temporary file paths
            const tempDir = require('os').tmpdir();
            this.micTempPath = path.join(tempDir, `mic_stream_${sessionId}.webm`);
            this.systemTempPath = path.join(tempDir, `system_stream_${sessionId}.webm`);
            
            // Import electron-audio-loopback in renderer context
            const { getLoopbackAudioMediaStream } = require('electron-audio-loopback');
            
            // Start microphone capture
            console.log('📱 Initializing microphone stream...');
            this.micStream = await getLoopbackAudioMediaStream({
                systemAudio: false,
                microphone: true
            });
            
            console.log('✅ Microphone stream created:', {
                id: this.micStream.id,
                tracks: this.micStream.getAudioTracks().length
            });
            
            // Diagnostic: Log microphone track details for AirPods/headset compatibility
            this.micStream.getAudioTracks().forEach((track, index) => {
                console.log(`🎤 Microphone track ${index}:`, {
                    label: track.label,
                    kind: track.kind,
                    enabled: track.enabled,
                    readyState: track.readyState
                });
            });
            
            // Start system audio capture  
            console.log('🔊 Initializing system audio stream...');
            console.log('🎧 Note: System audio includes output to AirPods/headsets/speakers');
            this.systemStream = await getLoopbackAudioMediaStream({
                systemAudio: true,
                microphone: false
            });
            
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
            
            // Create MediaRecorders with segmentation for memory management
            this.micRecorder = new MediaRecorder(this.micStream, {
                mimeType: 'audio/webm;codecs=opus',
                audioBitsPerSecond: this.audioBitsPerSecond
            });
            
            this.systemRecorder = new MediaRecorder(this.systemStream, {
                mimeType: 'audio/webm;codecs=opus',
                audioBitsPerSecond: this.audioBitsPerSecond
            });
            
            // Set up microphone recorder events
            this.micRecorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    this.micSegments.push(event.data);
                    console.log(`📱 Mic segment: ${event.data.size} bytes (${this.micSegments.length} total)`);
                }
            };
            
            this.micRecorder.onerror = (event) => {
                console.error('❌ Microphone recorder error:', event.error);
                this.emit('error', new Error(`Microphone recording failed: ${event.error.message}`));
            };
            
            // Set up system audio recorder events
            this.systemRecorder.ondataavailable = (event) => {
                if (event.data.size > 0) {
                    this.systemSegments.push(event.data);
                    console.log(`🔊 System segment: ${event.data.size} bytes (${this.systemSegments.length} total)`);
                }
            };
            
            this.systemRecorder.onerror = (event) => {
                console.error('❌ System audio recorder error:', event.error);
                this.emit('error', new Error(`System audio recording failed: ${event.error.message}`));
            };
            
            // Start recording with segmentation
            this.micRecorder.start(this.segmentDuration);
            this.systemRecorder.start(this.segmentDuration);
            
            this.isRecording = true;
            
            console.log(`✅ Dual-stream recording started for session ${sessionId}`);
            console.log(`📊 Configuration: ${this.audioBitsPerSecond}bps, ${this.segmentDuration}ms segments`);
            
            return {
                success: true,
                message: 'Dual-stream electron-audio-loopback recording started',
                sessionId: sessionId,
                audioConfig: {
                    sampleRate: this.sampleRate,
                    channels: this.channels,
                    audioBitsPerSecond: this.audioBitsPerSecond,
                    segmentDuration: this.segmentDuration,
                    backend: 'electron-audio-loopback',
                    streams: ['microphone', 'system-audio']
                }
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
            this.recordingEndTime = Date.now();
            
            // Stop MediaRecorders
            if (this.micRecorder && this.micRecorder.state === 'recording') {
                this.micRecorder.stop();
            }
            if (this.systemRecorder && this.systemRecorder.state === 'recording') {
                this.systemRecorder.stop();
            }
            
            // Wait for final data events
            await new Promise(resolve => setTimeout(resolve, 100));
            
            // Stop and cleanup streams
            if (this.micStream) {
                this.micStream.getTracks().forEach(track => track.stop());
            }
            if (this.systemStream) {
                this.systemStream.getTracks().forEach(track => track.stop());
            }
            
            // Calculate actual duration from system time
            const actualDuration = Math.round((this.recordingEndTime - this.recordingStartTime) / 1000);
            
            console.log(`✅ Dual-stream recording stopped`);
            console.log(`📊 Duration: ${actualDuration}s`);
            console.log(`📊 Microphone segments: ${this.micSegments.length}`);
            console.log(`📊 System audio segments: ${this.systemSegments.length}`);
            
            // Merge and save audio files
            let audioFilePath = null;
            try {
                audioFilePath = await this.mergeAndSaveAudio();
                console.log(`💾 Audio file saved: ${audioFilePath}`);
            } catch (error) {
                console.error(`❌ Failed to save audio file: ${error.message}`);
            }
            
            const result = {
                success: true,
                message: 'Dual-stream electron-audio-loopback recording stopped',
                sessionId: this.sessionId,
                audioFilePath,
                totalDuration: actualDuration, // Accurate system time duration
                micSegments: this.micSegments.length,
                systemSegments: this.systemSegments.length,
                audioConfig: {
                    sampleRate: this.sampleRate,
                    channels: this.channels,
                    backend: 'electron-audio-loopback'
                }
            };
            
            // Reset state
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

    async mergeAndSaveAudio() {
        if (this.micSegments.length === 0 && this.systemSegments.length === 0) {
            throw new Error('No audio segments to save');
        }
        
        // Create audio-temp directory if it doesn't exist
        const audioTempDir = path.join(process.cwd(), 'audio-temp');
        try {
            await fs.access(audioTempDir);
        } catch {
            await fs.mkdir(audioTempDir, { recursive: true });
        }
        
        // For now, prioritize microphone audio (user speech)
        // Later we can implement proper dual-stream mixing
        const primarySegments = this.micSegments.length > 0 ? this.micSegments : this.systemSegments;
        const streamType = this.micSegments.length > 0 ? 'microphone' : 'system';
        
        console.log(`🎯 Using ${streamType} stream as primary audio (${primarySegments.length} segments)`);
        
        // Merge segments into single blob
        const mergedBlob = new Blob(primarySegments, { type: 'audio/webm' });
        
        // Convert blob to buffer for file writing
        const buffer = Buffer.from(await mergedBlob.arrayBuffer());
        
        // Save as WebM file (we'll convert to WAV later if needed)
        const audioFilePath = path.join(audioTempDir, `session_${this.sessionId}.webm`);
        await fs.writeFile(audioFilePath, buffer);
        
        console.log(`📁 Audio file saved: ${audioFilePath} (${(buffer.length / 1024 / 1024).toFixed(2)} MB)`);
        return audioFilePath;
    }

    getRecordingStatus() {
        return {
            isRecording: this.isRecording,
            sessionId: this.sessionId,
            micSegments: this.micSegments?.length || 0,
            systemSegments: this.systemSegments?.length || 0,
            backend: 'electron-audio-loopback'
        };
    }

    async cleanup() {
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
        
        // Clean up temp files if they exist
        if (this.micTempPath) {
            try {
                await fs.access(this.micTempPath);
                await fs.unlink(this.micTempPath);
                console.log('🗑️ Cleaned up microphone temp file');
            } catch (error) {
                // File doesn't exist, that's ok
            }
        }
        
        if (this.systemTempPath) {
            try {
                await fs.access(this.systemTempPath);
                await fs.unlink(this.systemTempPath);
                console.log('🗑️ Cleaned up system audio temp file');
            } catch (error) {
                // File doesn't exist, that's ok
            }
        }
        
        this.removeAllListeners();
    }
}

module.exports = AudioCaptureLoopback;