#!/usr/bin/env node

// Test script for single-stream processing approach
// Process mic and system audio separately, then merge chronologically

require('dotenv').config();
const SummaryGeneration = require('./src/api/summaryGeneration');

async function testSingleStreamProcessing() {
    console.log('🧪 Testing single-stream processing approach...');
    console.log('📁 Using 12:27 recording from session_1756712067514');
    
    const summaryGen = new SummaryGeneration();
    
    // Use the 12:27 recording files
    const microphoneFile = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756712067514_microphone.webm';
    const systemAudioFile = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756712067514_system.webm';
    
    try {
        console.log('🎤 Microphone file:', microphoneFile);
        console.log('🔊 System audio file:', systemAudioFile);
        console.log('⏱️  Duration: 12:27 (748 seconds)');
        console.log('🔄 Testing: Single-stream processing + programmatic merge');
        console.log('✨ Expected: 100% content capture with perfect chronological order');
        
        // Process with single-stream approach (USE_SINGLE_STREAM_PROCESSING=true in .env)
        const result = await summaryGen.processAudioEndToEnd(microphoneFile, {
            participants: 'v',
            expectedDuration: 12.45,
            meetingTopic: 'single stream test',
            context: 'single-stream processing validation',
            systemAudioFilePath: systemAudioFile
        });
        
        console.log('✅ Single-stream processing complete!');
        console.log('📊 Processing time:', result.processingTime + 'ms');
        console.log('💰 Cost:', '$' + result.cost.totalCost.toFixed(4));
        console.log('📄 Files saved with timestamp:', result.timestamp);
        console.log('🔧 Provider:', result.provider);
        
        // Show key parts of transcript for comparison
        console.log('\n🔍 TRANSCRIPT PREVIEW (first 500 chars):');
        console.log(result.transcript.substring(0, 500) + '...');
        
        console.log('\n🔍 TRANSCRIPT END (last 300 chars):');
        console.log('...' + result.transcript.slice(-300));
        
        console.log('\n🎯 Key success metrics:');
        console.log('   • Missing system audio + AirPods section captured?');
        console.log('   • Chronological ordering correct?'); 
        console.log('   • All device switching segments present?');
        console.log('   • Speaker identification consistent?');
        
    } catch (error) {
        console.error('❌ Single-stream processing failed:', error.message);
    }
}

// Run the single-stream test
testSingleStreamProcessing();