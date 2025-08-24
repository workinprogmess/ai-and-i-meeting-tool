#!/usr/bin/env node

/**
 * Test transcription system with an existing audio file
 * Supports any audio format that ffmpeg can read
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const PerformanceMonitor = require('./src/validation/performanceMonitor');
const WhisperTranscription = require('./src/api/whisperTranscription');

async function testWithAudioFile(audioFilePath, referenceTextPath = null) {
    console.log('🎵 Testing with Audio File');
    console.log(`📁 Input: ${audioFilePath}`);
    console.log('=' .repeat(60));
    
    // Verify file exists
    if (!fs.existsSync(audioFilePath)) {
        console.error('❌ Audio file not found:', audioFilePath);
        process.exit(1);
    }
    
    const monitor = new PerformanceMonitor();
    const whisper = new WhisperTranscription();
    const sessionId = `file_test_${Date.now()}`;
    
    // Get file info
    const stats = fs.statSync(audioFilePath);
    console.log(`📊 File size: ${(stats.size / 1024 / 1024).toFixed(2)} MB`);
    
    // Load reference text if provided
    let referenceText = null;
    if (referenceTextPath && fs.existsSync(referenceTextPath)) {
        referenceText = fs.readFileSync(referenceTextPath, 'utf8');
        console.log(`📝 Reference text loaded for accuracy measurement`);
    }
    
    try {
        // Start monitoring
        monitor.startMonitoring(sessionId);
        
        // Convert audio file to PCM using ffmpeg
        console.log('\n🔄 Converting audio to PCM format...');
        
        const ffmpegArgs = [
            '-i', audioFilePath,              // Input file
            '-f', 's16le',                    // Output format: raw PCM
            '-acodec', 'pcm_s16le',          // PCM 16-bit little-endian
            '-ar', '16000',                   // 16kHz sample rate
            '-ac', '1',                       // Mono
            '-'                               // Output to stdout
        ];
        
        const ffmpeg = spawn('ffmpeg', ffmpegArgs);
        
        let pcmBuffer = Buffer.alloc(0);
        let chunkIndex = 0;
        let totalWords = 0;
        let allTranscriptions = [];
        const chunkDuration = 5; // seconds
        const bytesPerSecond = 16000 * 1 * 2; // sampleRate * channels * bytesPerSample
        const chunkSizeBytes = bytesPerSecond * chunkDuration;
        
        console.log('📊 Processing audio in 5-second chunks...\n');
        
        // Collect PCM data
        ffmpeg.stdout.on('data', async (data) => {
            pcmBuffer = Buffer.concat([pcmBuffer, data]);
            
            // Process complete chunks
            while (pcmBuffer.length >= chunkSizeBytes) {
                const chunk = pcmBuffer.slice(0, chunkSizeBytes);
                pcmBuffer = pcmBuffer.slice(chunkSizeBytes);
                
                const chunkInfo = {
                    index: chunkIndex,
                    pcmData: chunk,
                    duration: chunkDuration,
                    sampleRate: 16000,
                    channels: 1,
                    sessionId: sessionId,
                    startTime: Date.now()
                };
                
                try {
                    // Transcribe chunk
                    console.log(`📦 Processing chunk ${chunkIndex}...`);
                    const result = await whisper.transcribePCMChunk(chunkInfo, {
                        enableSpeakerDiarization: true
                    });
                    
                    if (result.success && result.text) {
                        const words = result.text.split(' ').filter(w => w.length > 0).length;
                        totalWords += words;
                        allTranscriptions.push(result.text);
                        
                        console.log(`✅ Chunk ${chunkIndex}: "${result.text.substring(0, 60)}..."`);
                        console.log(`   Words: ${words}, Cost: $${result.cost.toFixed(4)}`);
                    }
                    
                    // Record metrics
                    monitor.recordChunkProcessed(chunkInfo, result);
                    
                } catch (error) {
                    console.error(`❌ Error processing chunk ${chunkIndex}:`, error.message);
                    monitor.addError(error);
                }
                
                chunkIndex++;
            }
        });
        
        // Handle ffmpeg completion
        await new Promise((resolve, reject) => {
            ffmpeg.on('exit', async (code) => {
                // Process remaining data
                if (pcmBuffer.length > 0) {
                    console.log(`\n📦 Processing final chunk (${(pcmBuffer.length / 1024).toFixed(1)} KB)...`);
                    
                    const finalChunkInfo = {
                        index: chunkIndex,
                        pcmData: pcmBuffer,
                        duration: pcmBuffer.length / bytesPerSecond,
                        sampleRate: 16000,
                        channels: 1,
                        sessionId: sessionId,
                        startTime: Date.now()
                    };
                    
                    try {
                        const result = await whisper.transcribePCMChunk(finalChunkInfo, {
                            enableSpeakerDiarization: true
                        });
                        
                        if (result.success && result.text) {
                            const words = result.text.split(' ').filter(w => w.length > 0).length;
                            totalWords += words;
                            allTranscriptions.push(result.text);
                            console.log(`✅ Final chunk: "${result.text.substring(0, 60)}..."`);
                        }
                        
                        monitor.recordChunkProcessed(finalChunkInfo, result);
                    } catch (error) {
                        console.error('❌ Error processing final chunk:', error.message);
                    }
                }
                
                if (code === 0) {
                    resolve();
                } else {
                    reject(new Error(`FFmpeg exited with code ${code}`));
                }
            });
            
            ffmpeg.stderr.on('data', (data) => {
                // FFmpeg logs progress to stderr, only show errors
                const message = data.toString();
                if (message.includes('Error') || message.includes('error')) {
                    console.error('FFmpeg:', message);
                }
            });
        });
        
        // Stop monitoring
        monitor.stopMonitoring();
        
        // Generate report
        console.log('\n📊 Generating test report...');
        const report = monitor.generateReport();
        const { fileName, summaryPath } = monitor.saveReport();
        
        // Save full transcription
        const fullTranscription = allTranscriptions.join('\n\n');
        const transcriptPath = fileName.replace('.json', '_transcript.txt');
        fs.writeFileSync(transcriptPath, fullTranscription);
        
        // Calculate accuracy if reference provided
        if (referenceText) {
            console.log('\n🎯 Calculating accuracy...');
            const AccuracyMeasurement = require('./src/validation/accuracyMeasurement');
            const accuracy = new AccuracyMeasurement();
            
            const result = accuracy.compareTexts(referenceText, fullTranscription);
            console.log(`Accuracy: ${result.metrics.accuracy}%`);
            console.log(`Word Error Rate: ${result.metrics.wer}`);
        }
        
        // Display results
        console.log('\n' + '=' .repeat(60));
        console.log('TEST RESULTS');
        console.log('=' .repeat(60));
        
        console.log('\n📈 TRANSCRIPTION:');
        console.log(`• Total Chunks: ${chunkIndex + 1}`);
        console.log(`• Total Words: ${totalWords}`);
        console.log(`• Success Rate: ${report.transcription.successRate}`);
        console.log(`• Duration: ${report.duration.formatted}`);
        
        console.log('\n💰 COSTS:');
        console.log(`• Total: ${report.costs.total}`);
        console.log(`• Per Minute: ${report.costs.perMinute}`);
        
        console.log('\n📁 Output Files:');
        console.log(`• Full Report: ${fileName}`);
        console.log(`• Summary: ${summaryPath}`);
        console.log(`• Transcript: ${transcriptPath}`);
        
        console.log('\n✅ Test completed successfully!');
        
        return {
            report,
            transcription: fullTranscription,
            files: {
                report: fileName,
                summary: summaryPath,
                transcript: transcriptPath
            }
        };
        
    } catch (error) {
        console.error('\n❌ Test failed:', error);
        monitor.stopMonitoring();
        throw error;
    }
}

// Command line usage
if (require.main === module) {
    const audioFile = process.argv[2];
    const referenceFile = process.argv[3];
    
    if (!audioFile) {
        console.log('Usage: node test-with-audio-file.js <audio-file> [reference-text-file]');
        console.log('\nExamples:');
        console.log('  node test-with-audio-file.js meeting.mp3');
        console.log('  node test-with-audio-file.js podcast.wav transcript.txt');
        console.log('\nSupported formats: Any audio format ffmpeg can read (mp3, wav, m4a, etc.)');
        process.exit(1);
    }
    
    testWithAudioFile(audioFile, referenceFile)
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
}

module.exports = testWithAudioFile;