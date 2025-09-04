#!/usr/bin/env node

// Test script to reprocess the 12:27 recording for consistency testing
// Tests Gemini's dual-stream chronological ordering reliability

require('dotenv').config();
const SummaryGeneration = require('./src/api/summaryGeneration');

async function reprocess12MinuteRecording() {
    console.log('🧪 Testing Gemini consistency with 12:27 recording...');
    console.log('📁 Using existing audio files from session_1756712067514');
    
    const summaryGen = new SummaryGeneration();
    
    // Use the 12:27 recording files
    const microphoneFile = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756712067514_microphone.webm';
    const systemAudioFile = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756712067514_system.webm';
    
    try {
        console.log('🎤 Microphone file:', microphoneFile);
        console.log('🔊 System audio file:', systemAudioFile);
        console.log('⏱️  Duration: 12:27 (748 seconds)');
        console.log('🔄 Testing: Will missing system audio + AirPods section appear this time?');
        
        // Process with identical parameters to original
        const result = await summaryGen.processAudioEndToEnd(microphoneFile, {
            participants: 'v',
            expectedDuration: 12.45, // 748 seconds / 60
            meetingTopic: 'meeting',
            context: 'consistency testing',
            systemAudioFilePath: systemAudioFile
        });
        
        console.log('✅ Reprocessing complete!');
        console.log('📊 Processing time:', result.processingTime + 'ms');
        console.log('💰 Cost:', '$' + result.cost.totalCost.toFixed(4));
        console.log('📄 Files saved with timestamp:', result.timestamp);
        
        // Show key parts of transcript for comparison
        console.log('\n🔍 TRANSCRIPT PREVIEW (first 500 chars):');
        console.log(result.transcript.substring(0, 500) + '...');
        
        console.log('\n🔍 TRANSCRIPT END (last 300 chars):');
        console.log('...' + result.transcript.slice(-300));
        
        console.log('\n📋 Compare with original transcript-e2e-meeting-1756712855467.md');
        console.log('🎯 Key test questions:');
        console.log('   • Did missing system audio + AirPods section appear?');
        console.log('   • Is chronological ordering different?');
        console.log('   • Is mic + AirPods removed still at the end?');
        
    } catch (error) {
        console.error('❌ Reprocessing failed:', error.message);
    }
}

// Run the consistency test
reprocess12MinuteRecording();