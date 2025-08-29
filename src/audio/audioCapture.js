const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { EventEmitter } = require('events');

/**
 * AudioCapture using ffmpeg + AVFoundation (proven approach from Granola/Loom/Zoom)
 * Captures microphone audio and streams PCM data for real-time transcription
 */
class AudioCapture extends EventEmitter {
    constructor() {
        super();
        
        this.ffmpegProcess = null;
        this.isRecording = false;
        this.sessionId = null;
        // MEMORY OPTIMIZATION: Stream-to-disk instead of accumulating chunks in memory
        this.tempPCMFilePath = null; // temporary file for streaming PCM data
        this.chunkDuration = 5; // seconds per chunk for transcription
        this.currentChunkBuffer = Buffer.alloc(0);
        this.chunkIndex = 0;
        this.totalBytesWritten = 0; // track total audio data for final WAV creation
        
        // Audio configuration for Whisper API
        this.sampleRate = 16000; // 16kHz for Whisper
        this.channels = 1; // Mono
        this.bytesPerSample = 2; // 16-bit samples
        this.bytesPerSecond = this.sampleRate * this.channels * this.bytesPerSample;
        this.chunkSizeBytes = this.bytesPerSecond * this.chunkDuration;
        
        console.log('✅ AudioCapture initialized with ffmpeg + AVFoundation');
    }

    async checkPermissions() {
        console.log('🔐 Microphone permission will be requested by ffmpeg on first use');
        console.log('🔐 For system audio, Screen Recording permission may be required');
        return true;
    }

    async startRecording(sessionId) {
        try {
            if (this.isRecording) {
                throw new Error('Recording already in progress');
            }

            this.sessionId = sessionId;
            this.currentChunkBuffer = Buffer.alloc(0);
            this.chunkIndex = 0;
            this.totalBytesWritten = 0;
            
            // Create temporary PCM file for streaming audio data
            this.tempPCMFilePath = path.join(require('os').tmpdir(), `pcm_stream_${sessionId}.raw`);
            
            // Initialize empty temp file
            const fs = require('fs').promises;
            await fs.writeFile(this.tempPCMFilePath, Buffer.alloc(0));

            console.log('🎙️  Starting ffmpeg audio capture with AVFoundation...');
            
            // Build ffmpeg command for microphone capture
            // Format: ffmpeg -f avfoundation -i ":0" -f s16le -acodec pcm_s16le -ar 16000 -ac 1 -
            // ":0" = audio device 0 (microphone only, no video)
            const ffmpegArgs = [
                '-f', 'avfoundation',           // Use AVFoundation input
                '-i', ':0',                     // Audio device 0 (iMac Microphone)
                '-f', 's16le',                  // Output format: raw PCM
                '-acodec', 'pcm_s16le',        // PCM 16-bit little-endian (Whisper format)
                '-ar', '16000',                 // 16kHz sample rate
                '-ac', '1',                     // Mono audio
                '-loglevel', 'error',           // Only show errors
                '-'                             // Output to stdout
            ];

            console.log('📊 FFmpeg command:', `ffmpeg ${ffmpegArgs.join(' ')}`);

            // Spawn ffmpeg process
            this.ffmpegProcess = spawn('ffmpeg', ffmpegArgs);
            
            // Handle PCM audio data from stdout
            this.ffmpegProcess.stdout.on('data', (pcmData) => {
                // CRITICAL FIX: Handle async processPCMData errors to prevent crashes
                this.processPCMData(pcmData).catch(error => {
                    console.error('❌ Critical error processing PCM data:', error);
                    console.error('❌ This error was caught to prevent app crash');
                    // Emit error event but don't crash the app
                    this.emit('error', {
                        type: 'pcm_processing_error',
                        message: error.message,
                        phase: 'streaming_to_disk'
                    });
                });
            });

            // Handle ffmpeg errors
            this.ffmpegProcess.stderr.on('data', (data) => {
                const message = data.toString();
                if (message.includes('error') || message.includes('Error')) {
                    console.error('❌ FFmpeg error:', message);
                    this.emit('error', new Error(message));
                }
            });

            // Handle process exit
            this.ffmpegProcess.on('exit', (code, signal) => {
                console.log(`📝 FFmpeg process exited with code ${code}, signal ${signal}`);
                if (this.isRecording) {
                    this.isRecording = false;
                    this.emit('stopped', { code, signal });
                }
            });

            this.ffmpegProcess.on('error', (error) => {
                console.error('❌ Failed to start ffmpeg:', error.message);
                this.emit('error', error);
            });
            
            this.isRecording = true;
            
            console.log(`✅ FFmpeg recording started for session ${sessionId}`);
            console.log(`📊 Audio config: ${this.sampleRate}Hz, ${this.channels} channel, ${this.chunkDuration}s chunks`);
            
            return {
                success: true,
                message: 'FFmpeg AVFoundation recording started',
                sessionId: sessionId,
                audioConfig: {
                    sampleRate: this.sampleRate,
                    channels: this.channels,
                    chunkDuration: this.chunkDuration,
                    backend: 'ffmpeg + AVFoundation'
                }
            };

        } catch (error) {
            console.error('❌ Failed to start ffmpeg recording:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    async processPCMData(pcmData) {
        if (!this.isRecording) return;

        // Accumulate PCM data
        this.currentChunkBuffer = Buffer.concat([this.currentChunkBuffer, pcmData]);
        
        // Check if we have enough data for a complete chunk
        while (this.currentChunkBuffer.length >= this.chunkSizeBytes) {
            // Extract exactly the chunk size we need
            const completeChunk = this.currentChunkBuffer.slice(0, this.chunkSizeBytes);
            this.currentChunkBuffer = this.currentChunkBuffer.slice(this.chunkSizeBytes);
            
            // Create chunk info for transcription
            const chunkInfo = {
                index: this.chunkIndex,
                pcmData: completeChunk,
                startTime: Date.now() - (this.chunkDuration * 1000),
                endTime: Date.now(),
                duration: this.chunkDuration,
                sampleRate: this.sampleRate,
                channels: this.channels,
                sessionId: this.sessionId
            };
            
            // MEMORY OPTIMIZATION: Stream chunk to disk immediately instead of storing in memory
            await this.appendChunkToDisk(completeChunk);
            this.chunkIndex++;
            
            console.log(`📦 Streamed PCM chunk ${this.chunkIndex - 1}: ${completeChunk.length} bytes to disk`);
            
            // Emit chunk for real-time transcription (with temp data that gets cleaned up)
            this.emit('chunk', chunkInfo);
        }
    }

    async stopRecording() {
        try {
            if (!this.isRecording || !this.ffmpegProcess) {
                throw new Error('No recording in progress');
            }

            console.log('⏹️  Stopping ffmpeg recording...');
            
            // Send 'q' to ffmpeg to gracefully quit
            this.ffmpegProcess.stdin.write('q');
            this.ffmpegProcess.stdin.end();
            
            // Give ffmpeg a moment to finish
            await new Promise(resolve => setTimeout(resolve, 100));
            
            // Force kill if still running
            if (this.ffmpegProcess.exitCode === null) {
                this.ffmpegProcess.kill('SIGTERM');
            }
            
            // Process any remaining buffer data
            if (this.currentChunkBuffer.length > 0) {
                const finalChunkInfo = {
                    index: this.chunkIndex,
                    pcmData: this.currentChunkBuffer,
                    startTime: Date.now() - ((this.currentChunkBuffer.length / this.bytesPerSecond) * 1000),
                    endTime: Date.now(),
                    duration: this.currentChunkBuffer.length / this.bytesPerSecond,
                    sampleRate: this.sampleRate,
                    channels: this.channels,
                    sessionId: this.sessionId
                };
                
                // Stream final chunk to disk
                await this.appendChunkToDisk(this.currentChunkBuffer);
                console.log(`📦 Final PCM chunk: ${this.currentChunkBuffer.length} bytes`);
                
                // Emit final chunk for transcription
                this.emit('chunk', finalChunkInfo);
            }
            
            this.isRecording = false;
            
            const totalChunks = this.chunkIndex;
            // FIXED: Calculate actual duration from total bytes, not just complete chunks
            const totalDuration = Math.round(this.totalBytesWritten / this.bytesPerSecond);
            
            console.log(`✅ FFmpeg recording stopped`);
            console.log(`📊 Total chunks: ${totalChunks}, Duration: ~${totalDuration}s`);

            // CRITICAL FIX: Save the audio file from chunks
            let audioFilePath = null;
            try {
                audioFilePath = await this.saveAudioFile();
                console.log(`💾 Audio file saved: ${audioFilePath}`);
            } catch (error) {
                console.error(`❌ Failed to save audio file: ${error.message}`);
            }

            const result = {
                success: true,
                message: 'FFmpeg recording stopped',
                sessionId: this.sessionId,
                audioFilePath,
                totalChunks: totalChunks,
                totalDuration: totalDuration,
                audioConfig: {
                    sampleRate: this.sampleRate,
                    channels: this.channels
                }
            };

            // Reset state
            this.ffmpegProcess = null;
            this.sessionId = null;
            this.currentChunkBuffer = Buffer.alloc(0);
            this.chunkIndex = 0;
            this.totalBytesWritten = 0;
            
            // Clean up temp PCM file
            if (this.tempPCMFilePath) {
                try {
                    const fs = require('fs').promises;
                    await fs.access(this.tempPCMFilePath);
                    await fs.unlink(this.tempPCMFilePath);
                    console.log('🗑️ Cleaned up temporary PCM file');
                } catch (error) {
                    // File doesn't exist or already cleaned, that's ok
                    console.log('🗑️ Temp PCM file already cleaned or doesn\'t exist');
                }
            }
            this.tempPCMFilePath = null;

            return result;

        } catch (error) {
            console.error('❌ Failed to stop ffmpeg recording:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    getRecordingStatus() {
        return {
            isRecording: this.isRecording,
            sessionId: this.sessionId,
            chunksProcessed: this.chunkIndex,
            bufferSize: this.currentChunkBuffer?.length || 0
        };
    }
    
    async saveAudioFile() {
        if (!this.tempPCMFilePath || this.totalBytesWritten === 0) {
            throw new Error('No audio data to save - temp file missing or empty');
        }

        const fs = require('fs').promises;
        const path = require('path');
        
        // Create audio-temp directory if it doesn't exist
        const audioTempDir = path.join(process.cwd(), 'audio-temp');
        try {
            await fs.access(audioTempDir);
        } catch {
            await fs.mkdir(audioTempDir, { recursive: true });
        }
        
        const audioFilePath = path.join(audioTempDir, `session_${this.sessionId}.wav`);
        
        // MEMORY OPTIMIZATION: Read PCM data directly from temp file instead of from memory
        const combinedPCM = await fs.readFile(this.tempPCMFilePath);
        console.log(`📾 Read ${combinedPCM.length} bytes of PCM data from temp file`);
        
        // Create WAV header
        const wavHeader = this.createWAVHeader(combinedPCM.length);
        const wavFile = Buffer.concat([wavHeader, combinedPCM]);
        
        // Write WAV file
        await fs.writeFile(audioFilePath, wavFile);
        
        console.log(`📁 Audio file saved: ${audioFilePath} (${(wavFile.length / 1024 / 1024).toFixed(2)} MB)`);
        return audioFilePath;
    }
    
    createWAVHeader(dataLength) {
        const header = Buffer.alloc(44);
        
        // WAV header format
        header.write('RIFF', 0);
        header.writeUInt32LE(36 + dataLength, 4);
        header.write('WAVE', 8);
        header.write('fmt ', 12);
        header.writeUInt32LE(16, 16);  // Subchunk1Size
        header.writeUInt16LE(1, 20);   // AudioFormat (PCM)
        header.writeUInt16LE(this.channels, 22);  // NumChannels
        header.writeUInt32LE(this.sampleRate, 24);  // SampleRate
        header.writeUInt32LE(this.sampleRate * this.channels * 2, 28);  // ByteRate
        header.writeUInt16LE(this.channels * 2, 32);  // BlockAlign
        header.writeUInt16LE(16, 34);  // BitsPerSample
        header.write('data', 36);
        header.writeUInt32LE(dataLength, 40);
        
        return header;
    }

    async appendChunkToDisk(chunkBuffer) {
        if (!this.tempPCMFilePath) {
            throw new Error('Temp PCM file path not initialized');
        }
        
        try {
            // Append PCM data to temporary file using stream to minimize memory usage
            const fs = require('fs').promises;
            await fs.appendFile(this.tempPCMFilePath, chunkBuffer);
            this.totalBytesWritten += chunkBuffer.length;
            
            console.log(`📦 Streamed ${chunkBuffer.length} bytes to temp file (total: ${this.totalBytesWritten} bytes)`);
        } catch (error) {
            // Provide detailed error information for debugging
            console.error(`❌ Failed to write chunk to disk: ${error.message}`);
            console.error(`❌ Temp file path: ${this.tempPCMFilePath}`);
            console.error(`❌ Chunk size: ${chunkBuffer.length} bytes`);
            console.error(`❌ Total bytes written so far: ${this.totalBytesWritten} bytes`);
            
            // Re-throw with more context
            throw new Error(`Failed to stream audio chunk to disk: ${error.message}. This could be due to disk space, permissions, or file system issues.`);
        }
    }

    async cleanup() {
        if (this.isRecording && this.ffmpegProcess) {
            this.ffmpegProcess.kill('SIGTERM');
        }
        
        // Clean up temp PCM file if it exists
        if (this.tempPCMFilePath) {
            try {
                const fs = require('fs').promises;
                await fs.unlink(this.tempPCMFilePath);
                console.log('🗑️ Cleaned up temporary PCM file during cleanup');
            } catch (error) {
                // File might not exist, that's ok
                console.log('🗑️ Temp PCM file already cleaned or doesn\'t exist');
            }
            this.tempPCMFilePath = null;
        }
        
        this.removeAllListeners();
    }
}

module.exports = AudioCapture;