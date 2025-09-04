const OpenAI = require('openai');
const fs = require('fs');
const path = require('path');
const ffmpeg = require('fluent-ffmpeg');

class WhisperTranscription {
    constructor() {
        this.openai = null;
        this.initializeClient();
        this.costPerMinute = 0.006; // $0.006 per minute for Whisper API
    }

    initializeClient() {
        try {
            // Load environment variables
            require('dotenv').config();
            
            const apiKey = process.env.OPENAI_API_KEY;
            if (!apiKey) {
                throw new Error('OPENAI_API_KEY not found in environment variables. Please add it to your .env file.');
            }

            this.openai = new OpenAI({
                apiKey: apiKey,
                organization: process.env.OPENAI_ORG_ID || undefined
            });

            console.log('✅ OpenAI client initialized successfully');
        } catch (error) {
            console.error('❌ Failed to initialize OpenAI client:', error.message);
            throw error;
        }
    }

    // Create WAV file from PCM buffer (no ffmpeg conversion needed!)
    createWavFromPCM(pcmBuffer, sampleRate = 16000, channels = 1) {
        const bytesPerSample = 2; // 16-bit samples
        const byteRate = sampleRate * channels * bytesPerSample;
        const blockAlign = channels * bytesPerSample;
        
        // WAV header (44 bytes)
        const wavHeader = Buffer.alloc(44);
        
        // RIFF chunk descriptor
        wavHeader.write('RIFF', 0);
        wavHeader.writeUInt32LE(36 + pcmBuffer.length, 4);
        wavHeader.write('WAVE', 8);
        
        // fmt sub-chunk
        wavHeader.write('fmt ', 12);
        wavHeader.writeUInt32LE(16, 16);           // Subchunk1Size (16 for PCM)
        wavHeader.writeUInt16LE(1, 20);            // AudioFormat (1 for PCM)
        wavHeader.writeUInt16LE(channels, 22);     // NumChannels
        wavHeader.writeUInt32LE(sampleRate, 24);   // SampleRate
        wavHeader.writeUInt32LE(byteRate, 28);     // ByteRate
        wavHeader.writeUInt16LE(blockAlign, 32);   // BlockAlign
        wavHeader.writeUInt16LE(16, 34);           // BitsPerSample
        
        // data sub-chunk
        wavHeader.write('data', 36);
        wavHeader.writeUInt32LE(pcmBuffer.length, 40);
        
        // Combine header and PCM data
        return Buffer.concat([wavHeader, pcmBuffer]);
    }

    // New method: Transcribe PCM chunk directly (AudioTee pattern)
    async transcribePCMChunk(chunkInfo, options = {}) {
        try {
            if (!this.openai) {
                throw new Error('OpenAI client not initialized');
            }

            const { pcmData, sampleRate, channels, index, duration } = chunkInfo;
            
            if (!pcmData || pcmData.length === 0) {
                throw new Error('No PCM data provided');
            }

            console.log(`🎵 Transcribing PCM chunk ${index}: ${pcmData.length} bytes, ${duration}s`);

            // Create WAV file from PCM buffer (no file I/O needed!)
            const wavBuffer = this.createWavFromPCM(pcmData, sampleRate, channels);
            
            // Check size limit (25MB for Whisper API)
            if (wavBuffer.length > 25 * 1024 * 1024) {
                throw new Error('Audio chunk too large. Maximum size is 25MB.');
            }

            // Create readable stream from WAV buffer
            const { Readable } = require('stream');
            const audioStream = new Readable();
            audioStream.push(wavBuffer);
            audioStream.push(null); // End stream
            
            // Set filename for the stream (Whisper API expects this)
            audioStream.path = `chunk_${index}.wav`;
            
            // Default transcription options
            const transcriptionOptions = {
                file: audioStream,
                model: 'whisper-1',
                response_format: 'verbose_json',
                timestamp_granularities: ['segment'],
                ...options
            };

            // Add speaker diarization if requested
            if (options.enableSpeakerDiarization) {
                transcriptionOptions.speaker_labels = true;
            }

            const transcription = await this.openai.audio.transcriptions.create(transcriptionOptions);

            console.log(`✅ PCM transcription completed for chunk ${index}`);

            return this.processPCMTranscriptionResult(transcription, chunkInfo);

        } catch (error) {
            console.error('❌ Transcription failed:', error.message);
            
            // Handle specific API errors
            if (error.status === 401) {
                throw new Error('Invalid OpenAI API key. Please check your .env file.');
            } else if (error.status === 413) {
                throw new Error('Audio file too large. Maximum size is 25MB.');
            } else if (error.status === 429) {
                throw new Error('API rate limit exceeded. Please wait and try again.');
            }
            
            throw error;
        }
    }

    processTranscriptionResult(transcription, audioFilePath) {
        const result = {
            success: true,
            text: transcription.text,
            duration: transcription.duration,
            language: transcription.language,
            segments: transcription.segments || [],
            audioFile: audioFilePath,
            timestamp: new Date().toISOString(),
            cost: this.calculateCost(transcription.duration)
        };

        // Process segments for speaker diarization if available
        if (transcription.segments && transcription.segments.length > 0) {
            result.segments = transcription.segments.map(segment => ({
                id: segment.id,
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speaker: segment.speaker || null, // Speaker ID from diarization
                confidence: segment.avg_logprob || null
            }));

            // Extract unique speakers
            const speakers = [...new Set(result.segments
                .map(s => s.speaker)
                .filter(s => s !== null)
            )];
            
            result.speakers = speakers.length > 0 ? speakers : ['Unknown Speaker'];
            result.hasSpeakerDiarization = speakers.length > 0;
        } else {
            result.segments = [];
            result.speakers = ['Unknown Speaker'];
            result.hasSpeakerDiarization = false;
        }

        console.log(`📊 Transcription stats: ${result.text.length} chars, ${result.duration}s, $${result.cost.toFixed(4)}`);
        
        return result;
    }

    processPCMTranscriptionResult(transcription, chunkInfo) {
        const result = {
            success: true,
            text: transcription.text,
            duration: transcription.duration,
            language: transcription.language,
            segments: transcription.segments || [],
            chunkInfo: {
                index: chunkInfo.index,
                startTime: chunkInfo.startTime,
                endTime: chunkInfo.endTime,
                duration: chunkInfo.duration,
                sessionId: chunkInfo.sessionId
            },
            timestamp: new Date().toISOString(),
            cost: this.calculateCost(transcription.duration)
        };

        // Process segments for speaker diarization if available
        if (transcription.segments && transcription.segments.length > 0) {
            result.segments = transcription.segments.map(segment => ({
                id: segment.id,
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speaker: segment.speaker || null, // Speaker ID from diarization
                confidence: segment.avg_logprob || null
            }));

            // Extract unique speakers
            const speakers = [...new Set(result.segments
                .map(s => s.speaker)
                .filter(s => s !== null)
            )];
            
            result.speakers = speakers.length > 0 ? speakers : ['Unknown Speaker'];
            result.hasSpeakerDiarization = speakers.length > 0;
        } else {
            result.segments = [];
            result.speakers = ['Unknown Speaker'];
            result.hasSpeakerDiarization = false;
        }

        console.log(`📊 PCM chunk ${chunkInfo.index}: ${result.text.length} chars, ${result.duration}s, $${result.cost.toFixed(4)}`);
        
        return result;
    }

    calculateCost(durationInSeconds) {
        const minutes = durationInSeconds / 60;
        return minutes * this.costPerMinute;
    }

    async transcribeRealTimeChunk(chunkInfo, options = {}) {
        try {
            // Add timestamp context for real-time processing
            const enhancedOptions = {
                ...options,
                enableSpeakerDiarization: true, // Always enable for meeting transcription
                prompt: "This is a segment from a meeting or conversation. Include speaker transitions and maintain context."
            };

            const result = await this.transcribeAudioChunk(chunkInfo.filePath, enhancedOptions);
            
            // Add chunk context
            result.chunkInfo = {
                index: chunkInfo.chunkIndex,
                startTime: chunkInfo.startTime,
                endTime: chunkInfo.endTime,
                duration: chunkInfo.duration
            };

            return result;

        } catch (error) {
            console.error('❌ Real-time transcription failed:', error.message);
            return {
                success: false,
                error: error.message,
                chunkInfo: chunkInfo
            };
        }
    }

    // Utility method to validate API key
    async testApiConnection() {
        try {
            if (!this.openai) {
                throw new Error('OpenAI client not initialized');
            }

            // Make a simple API call to test connection
            const models = await this.openai.models.list();
            console.log('✅ OpenAI API connection successful');
            return { success: true, message: 'API connection verified' };
        } catch (error) {
            console.error('❌ OpenAI API connection failed:', error.message);
            return { success: false, error: error.message };
        }
    }

    // Get estimated cost for audio duration
    estimateCost(durationInSeconds) {
        return this.calculateCost(durationInSeconds);
    }
}

module.exports = WhisperTranscription;