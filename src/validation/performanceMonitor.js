const os = require('os');
const fs = require('fs');
const path = require('path');

/**
 * Performance Monitor for Extended Testing
 * Tracks system resources, transcription accuracy, and performance metrics
 */
class PerformanceMonitor {
    constructor() {
        this.metrics = {
            sessionStartTime: null,
            sessionEndTime: null,
            chunks: [],
            systemMetrics: [],
            transcriptionAccuracy: [],
            apiCosts: 0,
            errors: [],
            warnings: []
        };
        
        this.monitoringInterval = null;
        this.isMonitoring = false;
    }

    startMonitoring(sessionId) {
        this.metrics.sessionStartTime = Date.now();
        this.metrics.sessionId = sessionId;
        this.isMonitoring = true;
        
        console.log('📊 Performance monitoring started for session:', sessionId);
        
        // Monitor system metrics every 10 seconds
        this.monitoringInterval = setInterval(() => {
            this.captureSystemMetrics();
        }, 10000);
        
        this.captureSystemMetrics(); // Initial capture
    }

    captureSystemMetrics() {
        const metric = {
            timestamp: Date.now(),
            memory: {
                total: os.totalmem(),
                free: os.freemem(),
                used: os.totalmem() - os.freemem(),
                percentUsed: ((os.totalmem() - os.freemem()) / os.totalmem() * 100).toFixed(2),
                processHeap: process.memoryUsage().heapUsed,
                processRss: process.memoryUsage().rss
            },
            cpu: {
                loadAverage: os.loadavg(),
                cpus: os.cpus().map(cpu => ({
                    model: cpu.model,
                    speed: cpu.speed,
                    times: cpu.times
                }))
            },
            uptime: process.uptime()
        };
        
        this.metrics.systemMetrics.push(metric);
        
        // Check for performance issues
        if (parseFloat(metric.memory.percentUsed) > 80) {
            this.addWarning(`High memory usage: ${metric.memory.percentUsed}%`);
        }
        
        if (metric.cpu.loadAverage[0] > os.cpus().length * 0.8) {
            this.addWarning(`High CPU load: ${metric.cpu.loadAverage[0].toFixed(2)}`);
        }
    }

    recordChunkProcessed(chunkInfo, transcriptionResult) {
        const chunkMetric = {
            index: chunkInfo.index,
            timestamp: Date.now(),
            processingTime: Date.now() - chunkInfo.startTime,
            duration: chunkInfo.duration,
            bytesProcessed: chunkInfo.pcmData.length,
            transcriptionLength: transcriptionResult.text?.length || 0,
            wordsTranscribed: transcriptionResult.text?.split(' ').filter(w => w.length > 0).length || 0,
            cost: transcriptionResult.cost || 0,
            latency: Date.now() - chunkInfo.endTime,
            success: transcriptionResult.success
        };
        
        this.metrics.chunks.push(chunkMetric);
        this.metrics.apiCosts += chunkMetric.cost;
        
        // Calculate real-time factor
        const realTimeFactor = chunkMetric.processingTime / (chunkInfo.duration * 1000);
        if (realTimeFactor > 1.5) {
            this.addWarning(`Slow processing for chunk ${chunkInfo.index}: ${realTimeFactor.toFixed(2)}x real-time`);
        }
        
        console.log(`📈 Chunk ${chunkInfo.index} metrics:`, {
            words: chunkMetric.wordsTranscribed,
            latency: `${chunkMetric.latency}ms`,
            realTimeFactor: realTimeFactor.toFixed(2)
        });
    }

    recordAccuracyMeasurement(sample) {
        // sample = { chunkIndex, originalText, transcribedText, errors, accuracy }
        this.metrics.transcriptionAccuracy.push({
            ...sample,
            timestamp: Date.now()
        });
    }

    addError(error) {
        this.metrics.errors.push({
            timestamp: Date.now(),
            error: error.message || error,
            stack: error.stack
        });
        console.error('❌ Error recorded:', error);
    }

    addWarning(warning) {
        this.metrics.warnings.push({
            timestamp: Date.now(),
            warning
        });
        console.warn('⚠️  Warning:', warning);
    }

    stopMonitoring() {
        this.metrics.sessionEndTime = Date.now();
        this.isMonitoring = false;
        
        if (this.monitoringInterval) {
            clearInterval(this.monitoringInterval);
            this.monitoringInterval = null;
        }
        
        console.log('📊 Performance monitoring stopped');
    }

    generateReport() {
        const duration = (this.metrics.sessionEndTime - this.metrics.sessionStartTime) / 1000;
        const totalChunks = this.metrics.chunks.length;
        const successfulChunks = this.metrics.chunks.filter(c => c.success).length;
        const totalWords = this.metrics.chunks.reduce((sum, c) => sum + c.wordsTranscribed, 0);
        
        // Calculate averages
        const avgProcessingTime = this.metrics.chunks.reduce((sum, c) => sum + c.processingTime, 0) / totalChunks;
        const avgLatency = this.metrics.chunks.reduce((sum, c) => sum + c.latency, 0) / totalChunks;
        const avgWordsPerChunk = totalWords / totalChunks;
        
        // Memory statistics
        const memoryMetrics = this.metrics.systemMetrics.map(m => parseFloat(m.memory.percentUsed));
        const avgMemoryUsage = memoryMetrics.reduce((a, b) => a + b, 0) / memoryMetrics.length;
        const maxMemoryUsage = Math.max(...memoryMetrics);
        
        // CPU statistics
        const cpuLoads = this.metrics.systemMetrics.map(m => m.cpu.loadAverage[0]);
        const avgCpuLoad = cpuLoads.reduce((a, b) => a + b, 0) / cpuLoads.length;
        const maxCpuLoad = Math.max(...cpuLoads);
        
        // Accuracy calculation (if samples available)
        let overallAccuracy = null;
        if (this.metrics.transcriptionAccuracy.length > 0) {
            const accuracies = this.metrics.transcriptionAccuracy.map(s => s.accuracy);
            overallAccuracy = accuracies.reduce((a, b) => a + b, 0) / accuracies.length;
        }
        
        const report = {
            sessionId: this.metrics.sessionId,
            timestamp: new Date().toISOString(),
            duration: {
                seconds: duration,
                formatted: this.formatDuration(duration)
            },
            transcription: {
                totalChunks,
                successfulChunks,
                failedChunks: totalChunks - successfulChunks,
                successRate: ((successfulChunks / totalChunks) * 100).toFixed(2) + '%',
                totalWords,
                avgWordsPerChunk: avgWordsPerChunk.toFixed(1),
                wordsPerMinute: (totalWords / (duration / 60)).toFixed(1)
            },
            performance: {
                avgProcessingTime: avgProcessingTime.toFixed(0) + 'ms',
                avgLatency: avgLatency.toFixed(0) + 'ms',
                realTimeFactor: (avgProcessingTime / 5000).toFixed(2), // 5s chunks
                maxProcessingTime: Math.max(...this.metrics.chunks.map(c => c.processingTime)) + 'ms'
            },
            accuracy: overallAccuracy ? {
                overall: overallAccuracy.toFixed(2) + '%',
                samples: this.metrics.transcriptionAccuracy.length,
                details: this.metrics.transcriptionAccuracy
            } : 'No accuracy measurements recorded',
            systemResources: {
                memory: {
                    average: avgMemoryUsage.toFixed(2) + '%',
                    maximum: maxMemoryUsage.toFixed(2) + '%',
                    processHeapAvg: (this.metrics.systemMetrics.reduce((sum, m) => 
                        sum + m.memory.processHeap, 0) / this.metrics.systemMetrics.length / 1024 / 1024).toFixed(2) + ' MB'
                },
                cpu: {
                    avgLoad: avgCpuLoad.toFixed(2),
                    maxLoad: maxCpuLoad.toFixed(2),
                    cores: os.cpus().length
                }
            },
            costs: {
                total: '$' + this.metrics.apiCosts.toFixed(4),
                perMinute: '$' + (this.metrics.apiCosts / (duration / 60)).toFixed(4),
                perHour: '$' + (this.metrics.apiCosts / (duration / 3600)).toFixed(2)
            },
            stability: {
                errors: this.metrics.errors.length,
                warnings: this.metrics.warnings.length,
                errorDetails: this.metrics.errors,
                warningDetails: this.metrics.warnings
            },
            recommendations: this.generateRecommendations()
        };
        
        return report;
    }

    generateRecommendations() {
        const recommendations = [];
        
        // Check accuracy
        if (this.metrics.transcriptionAccuracy.length > 0) {
            const avgAccuracy = this.metrics.transcriptionAccuracy.reduce((sum, s) => sum + s.accuracy, 0) / 
                               this.metrics.transcriptionAccuracy.length;
            if (avgAccuracy < 85) {
                recommendations.push('⚠️  Accuracy below target (85%). Consider improving audio quality or microphone setup.');
            } else if (avgAccuracy >= 90) {
                recommendations.push('✅ Excellent accuracy achieved (>90%)');
            }
        }
        
        // Check performance
        const avgLatency = this.metrics.chunks.reduce((sum, c) => sum + c.latency, 0) / this.metrics.chunks.length;
        if (avgLatency > 2000) {
            recommendations.push('⚠️  High latency detected. Consider optimizing chunk size or network connection.');
        }
        
        // Check stability
        if (this.metrics.errors.length > 0) {
            recommendations.push(`⚠️  ${this.metrics.errors.length} errors occurred. Review error details for improvements.`);
        }
        
        if (this.metrics.warnings.length > 5) {
            recommendations.push('⚠️  Multiple warnings detected. Monitor system resources during extended sessions.');
        }
        
        // Check resource usage
        const memoryMetrics = this.metrics.systemMetrics.map(m => parseFloat(m.memory.percentUsed));
        const maxMemory = Math.max(...memoryMetrics);
        if (maxMemory > 80) {
            recommendations.push('⚠️  High memory usage detected. Consider implementing memory optimization.');
        }
        
        if (recommendations.length === 0) {
            recommendations.push('✅ System performing optimally within all parameters');
        }
        
        return recommendations;
    }

    formatDuration(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = Math.floor(seconds % 60);
        
        if (hours > 0) {
            return `${hours}h ${minutes}m ${secs}s`;
        } else if (minutes > 0) {
            return `${minutes}m ${secs}s`;
        } else {
            return `${secs}s`;
        }
    }

    saveReport(outputPath = null) {
        const report = this.generateReport();
        const fileName = outputPath || path.join(
            process.cwd(),
            'validation-reports',
            `validation_${this.metrics.sessionId}_${Date.now()}.json`
        );
        
        // Ensure directory exists
        const dir = path.dirname(fileName);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }
        
        fs.writeFileSync(fileName, JSON.stringify(report, null, 2));
        console.log(`📊 Validation report saved to: ${fileName}`);
        
        // Also save a human-readable summary
        const summaryPath = fileName.replace('.json', '_summary.txt');
        fs.writeFileSync(summaryPath, this.generateTextSummary(report));
        console.log(`📄 Summary saved to: ${summaryPath}`);
        
        return { report, fileName, summaryPath };
    }

    generateTextSummary(report) {
        return `
MILESTONE 1 VALIDATION REPORT
==============================
Session ID: ${report.sessionId}
Date: ${report.timestamp}

DURATION & SCALE
----------------
Total Duration: ${report.duration.formatted}
Total Words Transcribed: ${report.transcription.totalWords}
Words Per Minute: ${report.transcription.wordsPerMinute}

TRANSCRIPTION PERFORMANCE
-------------------------
Success Rate: ${report.transcription.successRate}
Chunks Processed: ${report.transcription.successfulChunks}/${report.transcription.totalChunks}
Average Processing Time: ${report.performance.avgProcessingTime}
Average Latency: ${report.performance.avgLatency}
Real-time Factor: ${report.performance.realTimeFactor}x (lower is better)

ACCURACY MEASUREMENT
--------------------
${typeof report.accuracy === 'object' ? 
  `Overall Accuracy: ${report.accuracy.overall}
Sample Size: ${report.accuracy.samples} measurements` : 
  report.accuracy}

SYSTEM RESOURCES
----------------
Memory Usage:
  Average: ${report.systemResources.memory.average}
  Maximum: ${report.systemResources.memory.maximum}
  Process Heap: ${report.systemResources.memory.processHeapAvg}

CPU Load:
  Average: ${report.systemResources.cpu.avgLoad}
  Maximum: ${report.systemResources.cpu.maxLoad}
  Available Cores: ${report.systemResources.cpu.cores}

COSTS
-----
Total API Cost: ${report.costs.total}
Cost Per Minute: ${report.costs.perMinute}
Projected Hourly Cost: ${report.costs.perHour}

STABILITY
---------
Errors: ${report.stability.errors}
Warnings: ${report.stability.warnings}

RECOMMENDATIONS
---------------
${report.recommendations.map(r => '• ' + r).join('\n')}

==============================
END OF VALIDATION REPORT
`;
    }
}

module.exports = PerformanceMonitor;