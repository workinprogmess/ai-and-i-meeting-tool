#!/usr/bin/env node

// Test script to reprocess the same audio files with identical prompt
// Tests Gemini's consistency in dual-stream processing

require('dotenv').config();
const SummaryGeneration = require('./src/api/summaryGeneration');

async function reprocessAudioFiles() {
    console.log('🧪 Testing Gemini consistency with identical audio files...');
    console.log('📁 Using existing audio files from session_1756639592651');
    
    const summaryGen = new SummaryGeneration();
    
    // Use the exact same files from your test
    const microphoneFile = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756639592651_microphone.webm';
    const systemAudioFile = '/Users/workinprogmess/ai-and-i/audio-temp/session_1756639592651_system.webm';
    
    try {
        console.log('🎤 Microphone file:', microphoneFile);
        console.log('🔊 System audio file:', systemAudioFile);
        console.log('⏱️  Expected duration: 3.78 minutes (227 seconds)');
        console.log('🔄 Timestamp buffer: +60 seconds (now allowing up to 4:46 vs previous 3:46)');
        
        // Process with identical parameters to original
        const result = await summaryGen.processAudioEndToEnd(microphoneFile, {
            participants: 'v',
            expectedDuration: 3.78, // 227 seconds / 60
            meetingTopic: 'audio testing',
            context: 'reliability testing',
            systemAudioFilePath: systemAudioFile
        });
        
        console.log('✅ Reprocessing complete!');
        console.log('📊 Processing time:', result.processingTime + 'ms');
        console.log('💰 Cost:', '$' + result.cost.totalCost.toFixed(4));
        console.log('📄 Files saved with timestamp:', result.timestamp);
        
        // Show key parts of transcript for comparison
        console.log('\n🔍 TRANSCRIPT PREVIEW (first 500 chars):');
        console.log(result.transcript.substring(0, 500) + '...');
        
        console.log('\n🔍 TRANSCRIPT END (last 200 chars):');
        console.log('...' + result.transcript.slice(-200));
        
        console.log('\n📋 Compare this with original transcript-e2e-meeting-1756639831214.md');
        console.log('🎯 Key test: Does your voice after videos appear this time?');
        
    } catch (error) {
        console.error('❌ Reprocessing failed:', error.message);
    }
}

// Run the test
reprocessAudioFiles();