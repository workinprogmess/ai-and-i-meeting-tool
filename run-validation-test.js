#!/usr/bin/env node

/**
 * Quick Validation Test for Milestone 1
 * Run this to perform a validation test of the transcription system
 */

const PerformanceMonitor = require('./src/validation/performanceMonitor');
const AudioCapture = require('./src/audio/audioCapture');
const WhisperTranscription = require('./src/api/whisperTranscription');

async function runQuickValidation(durationMinutes = 2) {
    console.log('🚀 Milestone 1 Quick Validation Test');
    console.log(`📊 Duration: ${durationMinutes} minutes`);
    console.log('=' .repeat(50));
    
    const monitor = new PerformanceMonitor();
    const audioCapture = new AudioCapture();
    const whisper = new WhisperTranscription();
    
    const sessionId = `validation_${Date.now()}`;
    const startTime = Date.now();
    const targetDuration = durationMinutes * 60 * 1000;
    
    let chunkCount = 0;
    let totalWords = 0;
    
    try {
        // Start monitoring
        monitor.startMonitoring(sessionId);
        
        // Setup chunk handler
        audioCapture.on('chunk', async (chunkInfo) => {
            const processStart = Date.now();
            
            try {
                console.log(`\n📦 Processing chunk ${chunkInfo.index}...`);
                
                // Transcribe
                const result = await whisper.transcribePCMChunk(chunkInfo, {
                    enableSpeakerDiarization: true
                });
                
                // Record metrics
                monitor.recordChunkProcessed(chunkInfo, result);
                
                if (result.success && result.text) {
                    const words = result.text.split(' ').filter(w => w.length > 0).length;
                    totalWords += words;
                    
                    console.log(`✅ Transcribed: "${result.text.substring(0, 80)}..."`);
                    console.log(`   Words: ${words}, Latency: ${Date.now() - processStart}ms, Cost: $${result.cost.toFixed(4)}`);
                    
                    chunkCount++;
                }
                
            } catch (error) {
                console.error(`❌ Error processing chunk:`, error.message);
                monitor.addError(error);
            }
        });
        
        // Start recording
        console.log('\n🎙️  Starting audio capture...');
        console.log('📢 PLEASE SPEAK CLEARLY INTO YOUR MICROPHONE\n');
        
        const startResult = await audioCapture.startRecording(sessionId);
        if (!startResult.success) {
            throw new Error(`Failed to start: ${startResult.error}`);
        }
        
        // Progress timer
        const progressTimer = setInterval(() => {
            const elapsed = Date.now() - startTime;
            const remaining = targetDuration - elapsed;
            
            if (remaining > 0) {
                const elapsedSec = Math.floor(elapsed / 1000);
                const remainingSec = Math.floor(remaining / 1000);
                console.log(`\n⏱️  Elapsed: ${elapsedSec}s, Remaining: ${remainingSec}s`);
                console.log(`📊 Chunks: ${chunkCount}, Words: ${totalWords}`);
            }
        }, 10000); // Every 10 seconds
        
        // Wait for test duration
        await new Promise(resolve => setTimeout(resolve, targetDuration));
        
        // Stop recording
        clearInterval(progressTimer);
        console.log('\n⏹️  Stopping recording...');
        await audioCapture.stopRecording();
        
        // Stop monitoring
        monitor.stopMonitoring();
        
        // Generate and display report
        console.log('\n📊 Generating validation report...');
        const report = monitor.generateReport();
        const { fileName, summaryPath } = monitor.saveReport();
        
        // Display summary
        console.log('\n' + '=' .repeat(60));
        console.log('VALIDATION TEST RESULTS');
        console.log('=' .repeat(60));
        
        console.log('\n📈 PERFORMANCE:');
        console.log(`• Duration: ${report.duration.formatted}`);
        console.log(`• Success Rate: ${report.transcription.successRate}`);
        console.log(`• Total Words: ${report.transcription.totalWords}`);
        console.log(`• Words/Minute: ${report.transcription.wordsPerMinute}`);
        console.log(`• Avg Latency: ${report.performance.avgLatency}`);
        console.log(`• Processing Speed: ${report.performance.realTimeFactor}x real-time`);
        
        console.log('\n💰 COSTS:');
        console.log(`• Total: ${report.costs.total}`);
        console.log(`• Per Minute: ${report.costs.perMinute}`);
        console.log(`• Projected Hourly: ${report.costs.perHour}`);
        
        console.log('\n💻 RESOURCES:');
        console.log(`• Memory: ${report.systemResources.memory.average} avg`);
        console.log(`• CPU Load: ${report.systemResources.cpu.avgLoad} avg`);
        
        console.log('\n✅ VALIDATION STATUS:');
        const meetsRequirements = 
            parseFloat(report.transcription.successRate) >= 95 &&
            parseFloat(report.performance.realTimeFactor) < 0.5 &&
            report.stability.errors === 0;
        
        if (meetsRequirements) {
            console.log('🎉 PASSED - System meets all requirements');
        } else {
            console.log('⚠️  Review recommendations below');
        }
        
        console.log('\n📋 RECOMMENDATIONS:');
        report.recommendations.forEach(rec => console.log(`  ${rec}`));
        
        console.log('\n📁 Full report saved to:');
        console.log(`  JSON: ${fileName}`);
        console.log(`  Summary: ${summaryPath}`);
        
        console.log('\n' + '=' .repeat(60));
        
        return report;
        
    } catch (error) {
        console.error('\n❌ Validation failed:', error);
        monitor.addError(error);
        monitor.stopMonitoring();
        throw error;
    }
}

// Run the test
const duration = parseFloat(process.argv[2]) || 2; // Default 2 minutes
console.log('Starting validation test...\n');

runQuickValidation(duration)
    .then(report => {
        console.log('\n✅ Validation test completed successfully!');
        
        // Exit with appropriate code
        const successRate = parseFloat(report.transcription.successRate);
        if (successRate >= 95) {
            console.log('🏆 System validation PASSED');
            process.exit(0);
        } else {
            console.log('⚠️  System needs optimization');
            process.exit(1);
        }
    })
    .catch(error => {
        console.error('\n❌ Test failed:', error);
        process.exit(1);
    });