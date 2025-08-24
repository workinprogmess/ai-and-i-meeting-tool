// const natural = require('natural'); // Optional dependency

/**
 * Accuracy Measurement Tool
 * Compares transcribed text with reference text to calculate accuracy
 */
class AccuracyMeasurement {
    constructor() {
        this.measurements = [];
    }

    /**
     * Calculate Word Error Rate (WER) - industry standard for speech recognition
     * WER = (Substitutions + Deletions + Insertions) / Total Words in Reference
     */
    calculateWER(reference, hypothesis) {
        // Tokenize and normalize
        const refWords = this.normalizeText(reference).split(' ').filter(w => w.length > 0);
        const hypWords = this.normalizeText(hypothesis).split(' ').filter(w => w.length > 0);
        
        if (refWords.length === 0) return 1.0;
        
        // Calculate Levenshtein distance
        const distance = this.levenshteinDistance(refWords, hypWords);
        const wer = distance / refWords.length;
        
        return Math.min(wer, 1.0); // Cap at 100% error rate
    }

    /**
     * Calculate accuracy percentage (inverse of WER)
     */
    calculateAccuracy(reference, hypothesis) {
        const wer = this.calculateWER(reference, hypothesis);
        return (1 - wer) * 100;
    }

    /**
     * Normalize text for comparison
     */
    normalizeText(text) {
        return text
            .toLowerCase()
            .replace(/[.,!?;:'"]/g, '') // Remove punctuation
            .replace(/\s+/g, ' ')        // Normalize whitespace
            .trim();
    }

    /**
     * Calculate Levenshtein distance between two word arrays
     */
    levenshteinDistance(source, target) {
        const sourceLen = source.length;
        const targetLen = target.length;
        
        // Create a 2D array for dynamic programming
        const dp = Array(sourceLen + 1).fill(null).map(() => Array(targetLen + 1).fill(0));
        
        // Initialize base cases
        for (let i = 0; i <= sourceLen; i++) {
            dp[i][0] = i;
        }
        for (let j = 0; j <= targetLen; j++) {
            dp[0][j] = j;
        }
        
        // Fill the dp table
        for (let i = 1; i <= sourceLen; i++) {
            for (let j = 1; j <= targetLen; j++) {
                const cost = source[i - 1] === target[j - 1] ? 0 : 1;
                dp[i][j] = Math.min(
                    dp[i - 1][j] + 1,     // Deletion
                    dp[i][j - 1] + 1,     // Insertion
                    dp[i - 1][j - 1] + cost // Substitution
                );
            }
        }
        
        return dp[sourceLen][targetLen];
    }

    /**
     * Perform detailed comparison and return metrics
     */
    compareTexts(reference, hypothesis, chunkIndex = null) {
        const refWords = this.normalizeText(reference).split(' ').filter(w => w.length > 0);
        const hypWords = this.normalizeText(hypothesis).split(' ').filter(w => w.length > 0);
        
        const distance = this.levenshteinDistance(refWords, hypWords);
        const wer = refWords.length > 0 ? distance / refWords.length : 0;
        const accuracy = (1 - wer) * 100;
        
        // Find specific errors
        const errors = this.findErrors(refWords, hypWords);
        
        const measurement = {
            chunkIndex,
            timestamp: Date.now(),
            reference: {
                text: reference,
                wordCount: refWords.length
            },
            hypothesis: {
                text: hypothesis,
                wordCount: hypWords.length
            },
            metrics: {
                wer: wer.toFixed(4),
                accuracy: accuracy.toFixed(2),
                editDistance: distance,
                substitutions: errors.substitutions,
                deletions: errors.deletions,
                insertions: errors.insertions
            },
            errors: errors.details
        };
        
        this.measurements.push(measurement);
        return measurement;
    }

    /**
     * Find specific types of errors
     */
    findErrors(reference, hypothesis) {
        const errors = {
            substitutions: 0,
            deletions: 0,
            insertions: 0,
            details: []
        };
        
        // Simple heuristic for error detection
        const maxLen = Math.max(reference.length, hypothesis.length);
        
        for (let i = 0; i < maxLen; i++) {
            if (i >= reference.length) {
                errors.insertions++;
                errors.details.push({
                    type: 'insertion',
                    position: i,
                    word: hypothesis[i]
                });
            } else if (i >= hypothesis.length) {
                errors.deletions++;
                errors.details.push({
                    type: 'deletion',
                    position: i,
                    word: reference[i]
                });
            } else if (reference[i] !== hypothesis[i]) {
                errors.substitutions++;
                errors.details.push({
                    type: 'substitution',
                    position: i,
                    expected: reference[i],
                    actual: hypothesis[i]
                });
            }
        }
        
        return errors;
    }

    /**
     * Calculate aggregate statistics for all measurements
     */
    getAggregateStats() {
        if (this.measurements.length === 0) {
            return null;
        }
        
        const accuracies = this.measurements.map(m => parseFloat(m.metrics.accuracy));
        const werValues = this.measurements.map(m => parseFloat(m.metrics.wer));
        
        const totalRefWords = this.measurements.reduce((sum, m) => sum + m.reference.wordCount, 0);
        const totalHypWords = this.measurements.reduce((sum, m) => sum + m.hypothesis.wordCount, 0);
        const totalErrors = this.measurements.reduce((sum, m) => sum + m.metrics.editDistance, 0);
        
        return {
            sampleCount: this.measurements.length,
            averageAccuracy: (accuracies.reduce((a, b) => a + b, 0) / accuracies.length).toFixed(2),
            minAccuracy: Math.min(...accuracies).toFixed(2),
            maxAccuracy: Math.max(...accuracies).toFixed(2),
            stdDevAccuracy: this.calculateStdDev(accuracies).toFixed(2),
            averageWER: (werValues.reduce((a, b) => a + b, 0) / werValues.length).toFixed(4),
            totalWords: {
                reference: totalRefWords,
                hypothesis: totalHypWords,
                ratio: (totalHypWords / totalRefWords).toFixed(3)
            },
            overallWER: (totalErrors / totalRefWords).toFixed(4),
            overallAccuracy: ((1 - totalErrors / totalRefWords) * 100).toFixed(2)
        };
    }

    /**
     * Calculate standard deviation
     */
    calculateStdDev(values) {
        const mean = values.reduce((a, b) => a + b, 0) / values.length;
        const squaredDiffs = values.map(v => Math.pow(v - mean, 2));
        const avgSquaredDiff = squaredDiffs.reduce((a, b) => a + b, 0) / values.length;
        return Math.sqrt(avgSquaredDiff);
    }

    /**
     * Generate accuracy report
     */
    generateReport() {
        const stats = this.getAggregateStats();
        
        if (!stats) {
            return {
                error: 'No measurements available'
            };
        }
        
        return {
            summary: {
                overallAccuracy: stats.overallAccuracy + '%',
                averageAccuracy: stats.averageAccuracy + '%',
                consistency: `${stats.minAccuracy}% - ${stats.maxAccuracy}% (σ=${stats.stdDevAccuracy})`,
                samples: stats.sampleCount,
                totalWordsAnalyzed: stats.totalWords.reference
            },
            performance: {
                meetsTarget85: parseFloat(stats.overallAccuracy) >= 85,
                meetsTarget90: parseFloat(stats.overallAccuracy) >= 90,
                recommendation: this.getRecommendation(parseFloat(stats.overallAccuracy))
            },
            details: stats,
            measurements: this.measurements
        };
    }

    getRecommendation(accuracy) {
        if (accuracy >= 95) {
            return '🏆 Exceptional accuracy - production ready';
        } else if (accuracy >= 90) {
            return '✅ Excellent accuracy - meets high quality standards';
        } else if (accuracy >= 85) {
            return '✅ Good accuracy - meets target requirements';
        } else if (accuracy >= 80) {
            return '⚠️  Acceptable accuracy - consider audio quality improvements';
        } else {
            return '❌ Below target - requires optimization';
        }
    }

    /**
     * Reset measurements
     */
    reset() {
        this.measurements = [];
    }
}

// Export without requiring natural if not installed
try {
    // const natural = require('natural'); // Optional dependency
    module.exports = AccuracyMeasurement;
} catch (e) {
    // Export basic version without natural dependency
    module.exports = AccuracyMeasurement;
}