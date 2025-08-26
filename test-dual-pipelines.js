#!/usr/bin/env node

/**
 * test both pipelines with twitter video
 * pipeline a: whisper → gemini summary  
 * pipeline b: gemini end-to-end (audio → transcript + summary + speakers)
 */

require('dotenv').config();
const WhisperTranscription = require('./src/api/whisperTranscription');
const SummaryGeneration = require('./src/api/summaryGeneration');
const fs = require('fs');
const path = require('path');

async function testDualPipelines() {
    const audioFile = 'audio-temp/twitter-video-test.wav';
    
    if (!fs.existsSync(audioFile)) {
        console.error('❌ twitter video audio file not found');
        console.log('💡 run: ffmpeg -i ~/Downloads/"twitter video.mp4" -vn -acodec pcm_s16le -ar 16000 -ac 1 audio-temp/twitter-video-test.wav');
        process.exit(1);
    }
    
    const stats = fs.statSync(audioFile);
    const fileSizeMB = (stats.size / 1024 / 1024).toFixed(2);
    console.log(`🎬 testing dual pipelines with twitter video (${fileSizeMB} mb)`);
    
    const startTime = Date.now();
    const results = {};
    
    // pipeline a: whisper → gemini summary
    console.log('\n🎵 === pipeline a: whisper → gemini summary ===');
    try {
        console.log('📝 step 1: whisper transcription...');
        const whisper = new WhisperTranscription();
        
        const transcriptionResult = await whisper.transcribeAudioFile(audioFile, {
            enableSpeakerDiarization: true,
            language: 'en'
        });
        
        if (transcriptionResult.error) {
            throw new Error(`whisper failed: ${transcriptionResult.error}`);
        }
        
        console.log(`✅ whisper complete: ${transcriptionResult.segments?.length || 0} segments`);
        console.log(`💰 whisper cost: $${transcriptionResult.cost?.toFixed(4)}`);
        
        console.log('📝 step 2: gemini summary generation...');
        const summaryGen = new SummaryGeneration();
        
        const summaryResult = await summaryGen.generateSummary(transcriptionResult, {
            provider: 'gemini',
            participants: ['speaker 1', 'speaker 2'],
            duration: 30,
            topic: 'twitter video discussion',
            context: 'social media content'
        });
        
        results.pipelineA = {
            provider: 'whisper + gemini',
            transcription: transcriptionResult,
            summary: summaryResult.gemini,
            totalCost: (transcriptionResult.cost || 0) + (summaryResult.gemini?.cost?.totalCost || 0),
            processingTime: Date.now() - startTime,
            status: 'success'
        };
        
        console.log(`✅ pipeline a complete: $${results.pipelineA.totalCost.toFixed(4)} total cost`);
        
    } catch (error) {
        console.error('❌ pipeline a failed:', error.message);
        results.pipelineA = {
            provider: 'whisper + gemini',
            error: error.message,
            status: 'failed'
        };
    }
    
    // pipeline b: gemini end-to-end
    console.log('\n🎯 === pipeline b: gemini end-to-end ===');
    try {
        const summaryGen = new SummaryGeneration();
        
        const endToEndResult = await summaryGen.processAudioEndToEnd(audioFile, {
            participants: 'twitter video speakers',
            expectedDuration: 30,
            meetingTopic: 'twitter video discussion',
            context: 'social media content analysis'
        });
        
        if (endToEndResult.error) {
            throw new Error(`gemini end-to-end failed: ${endToEndResult.error}`);
        }
        
        results.pipelineB = {
            provider: 'gemini-end-to-end',
            result: endToEndResult,
            totalCost: endToEndResult.cost?.totalCost || 0,
            processingTime: endToEndResult.processingTime,
            status: 'success'
        };
        
        console.log(`✅ pipeline b complete: $${results.pipelineB.totalCost.toFixed(4)} cost`);
        
    } catch (error) {
        console.error('❌ pipeline b failed:', error.message);
        results.pipelineB = {
            provider: 'gemini-end-to-end',
            error: error.message,
            status: 'failed'
        };
    }
    
    // comparison analysis
    const totalTime = Date.now() - startTime;
    
    console.log('\n📊 === dual pipeline comparison ===');
    console.log(`total test time: ${(totalTime / 1000).toFixed(1)} seconds`);
    
    if (results.pipelineA.status === 'success') {
        console.log(`pipeline a: $${results.pipelineA.totalCost.toFixed(4)} cost, whisper + gemini approach`);
        console.log(`  - transcript segments: ${results.pipelineA.transcription.segments?.length || 0}`);
        console.log(`  - summary length: ${results.pipelineA.summary?.summary?.length || 0} chars`);
    } else {
        console.log(`pipeline a: failed (${results.pipelineA.error})`);
    }
    
    if (results.pipelineB.status === 'success') {
        console.log(`pipeline b: $${results.pipelineB.totalCost.toFixed(4)} cost, gemini end-to-end`);
        console.log(`  - transcript length: ${results.pipelineB.result.transcript?.length || 0} chars`);
        console.log(`  - summary length: ${results.pipelineB.result.summary?.length || 0} chars`);
        console.log(`  - speaker analysis: ${results.pipelineB.result.speakerAnalysis ? 'yes' : 'no'}`);
        console.log(`  - emotional dynamics: ${results.pipelineB.result.emotionalDynamics ? 'yes' : 'no'}`);
    } else {
        console.log(`pipeline b: failed (${results.pipelineB.error})`);
    }
    
    // preview outputs
    if (results.pipelineA.status === 'success' && results.pipelineA.summary?.summary) {
        console.log('\n--- pipeline a summary preview ---');
        console.log(results.pipelineA.summary.summary.substring(0, 300) + '...');
    }
    
    if (results.pipelineB.status === 'success' && results.pipelineB.result.summary) {
        console.log('\n--- pipeline b summary preview ---');
        console.log(results.pipelineB.result.summary.substring(0, 300) + '...');
    }
    
    // save comparison
    const comparisonData = {
        timestamp: Date.now(),
        audioFile,
        fileSizeMB: parseFloat(fileSizeMB),
        totalProcessingTime: totalTime,
        results,
        recommendation: getRecommendation(results)
    };
    
    const comparisonFile = `summaries/dual_pipeline_twitter_${Date.now()}.json`;
    fs.writeFileSync(comparisonFile, JSON.stringify(comparisonData, null, 2));
    console.log(`\n💾 comparison saved to ${comparisonFile}`);
    
    console.log(`\n🏆 recommendation: ${comparisonData.recommendation}`);
    
    return comparisonData;
}

function getRecommendation(results) {
    const aSuccess = results.pipelineA.status === 'success';
    const bSuccess = results.pipelineB.status === 'success';
    
    if (bSuccess && !aSuccess) return 'pipeline b (gemini end-to-end) - only working option';
    if (aSuccess && !bSuccess) return 'pipeline a (whisper + gemini) - only working option';
    if (!aSuccess && !bSuccess) return 'both pipelines failed - needs debugging';
    
    // both successful - compare on features and cost
    const aCost = results.pipelineA.totalCost;
    const bCost = results.pipelineB.totalCost;
    
    if (bCost < aCost * 1.2) { // if b is within 20% cost of a
        return 'pipeline b (gemini end-to-end) - single api, speaker analysis, emotional context';
    }
    
    return 'pipeline a (whisper + gemini) - proven approach, good cost efficiency';
}

// run the test
testDualPipelines().then(results => {
    console.log('\n🎉 dual pipeline test complete!');
    console.log('✅ ready to refine transcript and summary formats based on results');
    process.exit(0);
}).catch(error => {
    console.error('\n💥 dual pipeline test failed:', error);
    process.exit(1);
});