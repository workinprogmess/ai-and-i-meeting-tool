#!/usr/bin/env node

// Test script to validate Whisper transcription with real audio file
const path = require('path');
const fs = require('fs');
const WhisperTranscription = require('./src/api/whisperTranscription');

async function testTranscription() {
    try {
        console.log('🎵 Testing Whisper transcription with real audio file...');
        
        // Get the latest audio file
        const audioDir = path.join(__dirname, 'audio-temp');
        const files = fs.readdirSync(audioDir).filter(f => f.endsWith('.wav'));
        
        if (files.length === 0) {
            throw new Error('No audio files found in audio-temp directory');
        }
        
        // Get a reasonably sized file (not the huge ones)
        let testFile = '';
        let testSize = 0;
        
        files.forEach(file => {
            const filePath = path.join(audioDir, file);
            const stats = fs.statSync(filePath);
            // Look for files between 1MB and 20MB
            if (stats.size > 1024*1024 && stats.size < 20*1024*1024) {
                testFile = file;
                testSize = stats.size;
            }
        });
        
        // If no good file found, use the smallest one
        if (!testFile && files.length > 0) {
            testFile = files[0];
            testSize = fs.statSync(path.join(audioDir, testFile)).size;
        }
        
        // Use our test sine wave file instead
        const testAudioFile = path.join(audioDir, 'test_sine.wav');
        if (fs.existsSync(testAudioFile)) {
            const audioFilePath = testAudioFile;
            console.log(`📁 Testing with sine wave file: ${path.basename(testAudioFile)}`);
        } else {
            throw new Error('Test audio file not found. Run: ffmpeg -f lavfi -i \"sine=frequency=440:duration=10\" -acodec pcm_s16le -ar 16000 -ac 1 audio-temp/test_sine.wav');
        }
        
        const audioFilePath = testAudioFile;
        
        // Initialize transcription service
        const whisper = new WhisperTranscription();
        
        // Test chunk structure (simulating real-time chunk)
        const chunkInfo = {
            filePath: audioFilePath,
            startTime: Date.now() - 15000, // 15 seconds ago
            endTime: Date.now(),
            duration: 15,
            chunkIndex: 0
        };
        
        console.log('🎯 Starting transcription...');
        const result = await whisper.transcribeRealTimeChunk(chunkInfo, {
            enableSpeakerDiarization: true
        });
        
        if (result.success) {
            console.log('✅ Transcription successful!');
            console.log('📝 Text:', result.text);
            console.log('👥 Speakers:', result.speakers);
            console.log('💰 Cost: $' + result.cost.toFixed(4));
            console.log('⏱️  Duration:', result.duration + 's');
            
            if (result.segments && result.segments.length > 0) {
                console.log('🎭 Speaker segments:');
                result.segments.forEach((segment, i) => {
                    console.log(`  ${i+1}. [${segment.start.toFixed(1)}s-${segment.end.toFixed(1)}s] ${segment.speaker || 'Unknown'}: ${segment.text}`);
                });
            }
        } else {
            console.error('❌ Transcription failed:', result.error);
        }
        
    } catch (error) {
        console.error('❌ Test failed:', error.message);
        process.exit(1);
    }
}

testTranscription().then(() => {
    console.log('🎉 Transcription test completed successfully!');
    process.exit(0);
}).catch(error => {
    console.error('💥 Transcription test failed:', error);
    process.exit(1);
});