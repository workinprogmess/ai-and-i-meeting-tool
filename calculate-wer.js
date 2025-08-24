#!/usr/bin/env node

/**
 * Calculate Word Error Rate (WER) for transcription accuracy
 * WER = (Substitutions + Deletions + Insertions) / Total Words in Reference
 */

const fs = require('fs');
const path = require('path');
const AccuracyMeasurement = require('./src/validation/accuracyMeasurement');

function calculateWER(transcribedFile, referenceFile) {
    console.log('🎯 WER (Word Error Rate) Calculator');
    console.log('=' .repeat(50));
    
    // Load files
    const transcribed = fs.readFileSync(transcribedFile, 'utf8');
    const reference = fs.readFileSync(referenceFile, 'utf8');
    
    console.log(`📝 Transcribed: ${transcribedFile}`);
    console.log(`📖 Reference: ${referenceFile}`);
    console.log();
    
    // Calculate WER
    const accuracy = new AccuracyMeasurement();
    const result = accuracy.compareTexts(reference, transcribed);
    
    // Display results
    console.log('📊 RESULTS:');
    console.log('=' .repeat(50));
    console.log(`\n✅ Accuracy: ${result.metrics.accuracy}%`);
    console.log(`📉 WER: ${(parseFloat(result.metrics.wer) * 100).toFixed(2)}%`);
    console.log(`\n📈 Detailed Metrics:`);
    console.log(`• Reference Words: ${result.reference.wordCount}`);
    console.log(`• Transcribed Words: ${result.hypothesis.wordCount}`);
    console.log(`• Edit Distance: ${result.metrics.editDistance}`);
    console.log(`• Substitutions: ${result.metrics.substitutions}`);
    console.log(`• Deletions: ${result.metrics.deletions}`);
    console.log(`• Insertions: ${result.metrics.insertions}`);
    
    // Quality assessment
    console.log(`\n🏆 Quality Assessment:`);
    const acc = parseFloat(result.metrics.accuracy);
    if (acc >= 95) {
        console.log('⭐ EXCELLENT - Professional quality transcription');
    } else if (acc >= 90) {
        console.log('✅ VERY GOOD - High quality, minor errors');
    } else if (acc >= 85) {
        console.log('✅ GOOD - Meets industry standards');
    } else if (acc >= 80) {
        console.log('⚠️  ACCEPTABLE - Usable but needs improvement');
    } else {
        console.log('❌ POOR - Significant errors, needs optimization');
    }
    
    // Show sample errors
    if (result.errors.details && result.errors.details.length > 0) {
        console.log(`\n❌ Sample Errors (first 10):`);
        result.errors.details.slice(0, 10).forEach(error => {
            if (error.type === 'substitution') {
                console.log(`  • Word ${error.position}: "${error.expected}" → "${error.actual}"`);
            } else if (error.type === 'deletion') {
                console.log(`  • Word ${error.position}: Missing "${error.word}"`);
            } else if (error.type === 'insertion') {
                console.log(`  • Word ${error.position}: Extra "${error.word}"`);
            }
        });
    }
    
    return result;
}

// For testing without reference - analyze transcription quality
function analyzeTranscriptionQuality(transcribedFile) {
    console.log('📊 Transcription Quality Analysis');
    console.log('=' .repeat(50));
    
    const transcribed = fs.readFileSync(transcribedFile, 'utf8');
    
    // Split into chunks (paragraphs)
    const chunks = transcribed.split('\n\n').filter(c => c.trim());
    
    // Analyze each chunk
    const analysis = {
        totalChunks: chunks.length,
        totalWords: 0,
        avgWordsPerChunk: 0,
        shortChunks: 0,
        incompleteChunks: 0,
        qualityIndicators: {
            hasProperCapitalization: 0,
            hasPunctuation: 0,
            coherentSentences: 0,
            fillerWords: 0
        }
    };
    
    chunks.forEach(chunk => {
        const words = chunk.split(' ').filter(w => w.length > 0);
        analysis.totalWords += words.length;
        
        // Check for short/incomplete chunks
        if (words.length < 5) analysis.shortChunks++;
        if (chunk.endsWith('...')) analysis.incompleteChunks++;
        
        // Check quality indicators
        if (/^[A-Z]/.test(chunk)) analysis.qualityIndicators.hasProperCapitalization++;
        if (/[.!?]/.test(chunk)) analysis.qualityIndicators.hasPunctuation++;
        if (words.length > 3 && !chunk.includes('...')) analysis.qualityIndicators.coherentSentences++;
        
        // Count filler words (common in speech)
        const fillers = ['um', 'uh', 'like', 'you know', 'basically', 'actually'];
        fillers.forEach(filler => {
            if (chunk.toLowerCase().includes(filler)) analysis.qualityIndicators.fillerWords++;
        });
    });
    
    analysis.avgWordsPerChunk = (analysis.totalWords / chunks.length).toFixed(1);
    
    // Calculate quality score
    const qualityScore = {
        completeness: ((chunks.length - analysis.incompleteChunks) / chunks.length * 100).toFixed(1),
        coherence: ((chunks.length - analysis.shortChunks) / chunks.length * 100).toFixed(1),
        formatting: (analysis.qualityIndicators.hasProperCapitalization / chunks.length * 100).toFixed(1),
        naturalSpeech: analysis.qualityIndicators.fillerWords > 0 ? 'Yes' : 'No'
    };
    
    // Display results
    console.log(`\n📝 Transcription: ${transcribedFile}`);
    console.log(`\n📈 Statistics:`);
    console.log(`• Total Chunks: ${analysis.totalChunks}`);
    console.log(`• Total Words: ${analysis.totalWords}`);
    console.log(`• Avg Words/Chunk: ${analysis.avgWordsPerChunk}`);
    console.log(`• Incomplete Chunks: ${analysis.incompleteChunks}`);
    
    console.log(`\n🏆 Quality Indicators:`);
    console.log(`• Completeness: ${qualityScore.completeness}%`);
    console.log(`• Coherence: ${qualityScore.coherence}%`);
    console.log(`• Proper Formatting: ${qualityScore.formatting}%`);
    console.log(`• Natural Speech Detected: ${qualityScore.naturalSpeech}`);
    
    // Estimated accuracy based on quality indicators
    const estimatedAccuracy = (
        parseFloat(qualityScore.completeness) * 0.4 +
        parseFloat(qualityScore.coherence) * 0.4 +
        parseFloat(qualityScore.formatting) * 0.2
    ).toFixed(1);
    
    console.log(`\n⚠️  Estimated Accuracy (without reference): ~${estimatedAccuracy}%`);
    console.log('Note: This is an estimate based on transcription quality indicators.');
    console.log('For accurate WER, provide a reference transcript.');
    
    return analysis;
}

// Command line usage
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
        console.log('Usage:');
        console.log('  Calculate WER: node calculate-wer.js <transcribed> <reference>');
        console.log('  Analyze quality: node calculate-wer.js <transcribed>');
        console.log('\nExamples:');
        console.log('  node calculate-wer.js transcript.txt reference.txt');
        console.log('  node calculate-wer.js validation-reports/*_transcript.txt');
        process.exit(1);
    }
    
    if (args.length === 1) {
        // Analyze quality without reference
        analyzeTranscriptionQuality(args[0]);
    } else {
        // Calculate WER with reference
        calculateWER(args[0], args[1]);
    }
}

module.exports = { calculateWER, analyzeTranscriptionQuality };