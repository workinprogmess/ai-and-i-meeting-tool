# milestone 3.3(a): improvement plan - achieving 90% accuracy with current architecture

## executive summary
incremental improvements to achieve 90%+ transcription accuracy without architectural changes. focus on stereo merging at capture time, audio preprocessing, chunked processing, and intelligent metadata handling within our existing electron-audio-loopback setup.

## current state analysis

### critical failures identified
1. **two-file problem**: 30-50% content loss from poor temporal alignment
   - gemini/deepgram cannot reliably merge two separate streams
   - timestamp drift between microphone.webm and system.webm
   - inconsistent results even with identical inputs

2. **acoustic coupling**: content unintelligible when airpods removed
   - system audio → speakers → microphone pickup
   - creates overlapping audio ai cannot separate
   - phase cancellation and echo issues

3. **service inconsistencies**: 33% variation between attempts
   - gemini: non-deterministic despite temperature=0
   - deepgram: similar loss patterns even with nova-3
   - both services fail on same content (audio quality issue)

4. **compression artifacts**: webm 128kbps lossy encoding
   - frequency masking in speech ranges
   - reduced signal-to-noise ratio
   - compounds with acoustic issues

## phase 1: immediate improvements (1-2 days)

### 1.1 stereo merge at capture time (highest priority)
```javascript
// src/renderer/audioLoopbackRenderer.js - modify existing
async stopRecording() {
    // create single stereo file instead of two separate files
    const stereoBlob = await this.createStereoFile(
        this.micSegments,    // left channel
        this.systemSegments  // right channel
    );
    
    // save as single file with clear channel separation
    const audioPath = await this.saveStereoFile(stereoBlob);
    
    // send ONE file with metadata about channels
    return {
        audioPath,
        metadata: {
            leftChannel: 'microphone',
            rightChannel: 'system_audio',
            startTime: this.recordingStartTime,
            duration: this.recordingDuration
        }
    };
}

async createStereoFile(micSegments, systemSegments) {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    
    // decode both streams
    const micBuffer = await this.decodeSegments(micSegments);
    const sysBuffer = await this.decodeSegments(systemSegments);
    
    // create stereo buffer with perfect alignment
    const length = Math.max(micBuffer.length, sysBuffer.length);
    const stereoBuffer = audioContext.createBuffer(2, length, audioContext.sampleRate);
    
    // copy to channels (left = mic, right = system)
    stereoBuffer.copyToChannel(micBuffer.getChannelData(0), 0);
    stereoBuffer.copyToChannel(sysBuffer.getChannelData(0), 1);
    
    // encode back to webm (or wav if we implement conversion)
    return this.encodeToWebM(stereoBuffer);
}
```

**expected improvement**: 20-30% better accuracy from solving temporal alignment

### 1.2 audio preprocessing pipeline (complements stereo merge)
```javascript
// src/audio/audioPreprocessor.js
class AudioPreprocessor {
    async processForTranscription(stereoPath) {
        // step 1: convert to wav (lossless) if still webm
        const wavPath = await this.convertToWav(stereoPath);
        
        // step 2: apply noise gate to both channels
        const gatedPath = await this.applyNoiseGate(wavPath, {
            threshold: -40,  // db
            ratio: 10,
            attack: 0.01,
            release: 0.1
        });
        
        // step 3: normalize volume per channel
        const normalizedPath = await this.normalizeAudio(gatedPath, {
            target: -16,  // lufs
            peak: -1      // db
        });
        
        return normalizedPath;
    }
}
```

**expected improvement**: 10-15% better accuracy from cleaner audio

### 1.3 intelligent device detection
```javascript
// src/audio/deviceManager.js
class DeviceManager {
    monitorAudioDevices() {
        navigator.mediaDevices.addEventListener('devicechange', async (event) => {
            const devices = await navigator.mediaDevices.enumerateDevices();
            const airpodsConnected = devices.some(d => 
                d.label.toLowerCase().includes('airpods')
            );
            
            if (!airpodsConnected && this.wasUsingAirpods) {
                // airpods removed - take action
                this.handleAirpodsRemoval();
            }
        });
    }
    
    handleAirpodsRemoval() {
        // option 1: pause system audio recording
        // option 2: reduce system volume programmatically
        // option 3: increase noise gate threshold
        // option 4: warn user to reconnect
    }
}
```

**expected improvement**: prevent 30% content loss from device switching

### 1.4 chunked processing for better accuracy
```javascript
// src/api/chunkProcessor.js
class ChunkProcessor {
    async processInChunks(audioPath, chunkDuration = 60000) {
        const chunks = await this.splitAudioFile(audioPath, chunkDuration);
        const results = [];
        
        for (const [index, chunk] of chunks.entries()) {
            // process each chunk with context
            const result = await this.transcribeChunk(chunk, {
                chunkIndex: index,
                previousContext: results[index - 1]?.context || null,
                metadata: {
                    startTime: index * chunkDuration,
                    endTime: (index + 1) * chunkDuration
                }
            });
            results.push(result);
        }
        
        return this.mergeChunkResults(results);
    }
    
    async transcribeChunk(chunk, context) {
        // send to gemini/deepgram with enhanced prompt
        const prompt = `
            This is chunk ${context.chunkIndex + 1} of a recording.
            Previous context: ${context.previousContext}
            Time range: ${context.metadata.startTime}ms - ${context.metadata.endTime}ms
            Left channel: microphone (@me)
            Right channel: system audio (@speaker)
            Maintain speaker consistency across chunks.
        `;
        
        return await transcribe(chunk, prompt);
    }
}
```

**expected improvement**: 15-20% better accuracy from reduced complexity per chunk

### 1.5 enhanced metadata and prompting
```javascript
// src/api/transcriptionEnhancer.js
class TranscriptionEnhancer {
    createEnhancedPrompt(audioMetadata) {
        return `
            CRITICAL AUDIO INFORMATION:
            - This is a STEREO file with two distinct sources
            - LEFT CHANNEL (0): Microphone input - label as @me
            - RIGHT CHANNEL (1): System audio - label as @speaker
            - Recording started at: ${audioMetadata.startTime}
            - Duration: ${audioMetadata.duration}ms
            - Channels are perfectly synchronized at capture
            
            INSTRUCTIONS:
            1. Process left and right channels independently
            2. Never mix content between channels
            3. If channels overlap temporally, transcribe both
            4. Maintain chronological order based on audio timing
            5. Use @me for left channel, @speaker for right channel
            
            QUALITY NOTES:
            - Audio is ${audioMetadata.bitrate}kbps ${audioMetadata.format}
            - Both channels recorded simultaneously
            - No timestamp drift between channels
        `;
    }
}
```

**expected improvement**: 10-15% better accuracy from clearer instructions

### 1.6 enhanced bitrate (already implemented)
- increased from 128kbps → 256kbps
- reduces compression artifacts
- **expected improvement**: 5-10% better accuracy

## phase 2: dual-service redundancy (2-3 days)

### 2.1 parallel processing
```javascript
// src/api/dualServiceTranscription.js
class DualServiceTranscription {
    async transcribeWithRedundancy(audioPath) {
        // preprocess audio first
        const cleanAudio = await preprocessor.processForTranscription(audioPath);
        
        // send to both services in parallel
        const [geminiResult, deepgramResult] = await Promise.all([
            this.transcribeWithGemini(cleanAudio),
            this.transcribeWithDeepgram(cleanAudio)
        ]);
        
        // merge intelligently
        return this.intelligentMerge(geminiResult, deepgramResult);
    }
    
    intelligentMerge(result1, result2) {
        // use confidence scores
        // prefer content that appears in both
        // handle unique content carefully
        // maintain chronological order
    }
}
```

**expected improvement**: 15-20% better completeness from redundancy

### 2.2 confidence-based merging
```javascript
mergeSentences(geminiSentence, deepgramSentence) {
    // calculate similarity
    const similarity = this.calculateSimilarity(geminiSentence, deepgramSentence);
    
    if (similarity > 0.8) {
        // very similar - pick higher confidence
        return geminiConfidence > deepgramConfidence ? 
               geminiSentence : deepgramSentence;
    } else if (similarity > 0.5) {
        // somewhat similar - merge words
        return this.mergeAtWordLevel(geminiSentence, deepgramSentence);
    } else {
        // different content - include both
        return `${geminiSentence} [OR] ${deepgramSentence}`;
    }
}
```

**expected improvement**: 10% reduction in missing content

### 2.3 retry logic with exponential backoff
```javascript
async transcribeWithRetry(audioPath, maxRetries = 3) {
    for (let i = 0; i < maxRetries; i++) {
        try {
            const result = await this.transcribe(audioPath);
            if (result.confidence > 0.7) return result;
            
            // low confidence - retry with different params
            await this.wait(Math.pow(2, i) * 1000);
        } catch (error) {
            console.log(`attempt ${i + 1} failed, retrying...`);
        }
    }
}
```

**expected improvement**: 5% better reliability

## phase 3: advanced audio processing (3-4 days)

### 3.1 voice activity detection (vad)
```javascript
// src/audio/voiceActivityDetector.js
class VoiceActivityDetector {
    detectSpeechSegments(audioBuffer) {
        // use webrtcvad or similar
        const segments = [];
        let inSpeech = false;
        let speechStart = 0;
        
        for (let i = 0; i < audioBuffer.length; i += frameSize) {
            const frame = audioBuffer.slice(i, i + frameSize);
            const isSpeech = this.vad.process(frame);
            
            if (isSpeech && !inSpeech) {
                speechStart = i;
                inSpeech = true;
            } else if (!isSpeech && inSpeech) {
                segments.push({
                    start: speechStart,
                    end: i,
                    data: audioBuffer.slice(speechStart, i)
                });
                inSpeech = false;
            }
        }
        
        return segments;
    }
}
```

**expected improvement**: 10-15% better speaker separation

### 3.2 acoustic echo cancellation
```javascript
// src/audio/echoCancellation.js
class EchoCancellation {
    constructor() {
        // use speex or webrtc aec
        this.aec = new WebRTCAEC();
    }
    
    removeEcho(micAudio, systemAudio) {
        // system audio is the reference (echo source)
        // mic audio contains echo + voice
        return this.aec.process(micAudio, systemAudio);
    }
}
```

**expected improvement**: 20% reduction in acoustic coupling issues

### 3.3 spectral subtraction for noise reduction
```javascript
reduceNoise(audioBuffer) {
    // estimate noise spectrum during silence
    const noiseProfile = this.estimateNoiseProfile(audioBuffer);
    
    // subtract noise spectrum from signal
    const fft = new FFT(audioBuffer);
    const spectrum = fft.forward();
    
    for (let i = 0; i < spectrum.length; i++) {
        spectrum[i] = Math.max(0, spectrum[i] - noiseProfile[i]);
    }
    
    return fft.inverse(spectrum);
}
```

**expected improvement**: 10% cleaner audio

## implementation timeline

### week 1
- [x] increase bitrate to 256kbps (done)
- [ ] implement wav conversion pipeline
- [ ] add basic noise gate
- [ ] test with consistent airpods usage
- [ ] measure accuracy improvements

### week 2
- [ ] implement dual-service redundancy
- [ ] build confidence-based merging
- [ ] add retry logic
- [ ] test with problematic recordings
- [ ] optimize merge algorithms

### week 3 (if needed)
- [ ] implement vad for speaker separation
- [ ] add echo cancellation
- [ ] implement spectral noise reduction
- [ ] comprehensive testing
- [ ] performance optimization

## success metrics

### target improvements
- **current baseline**: ~50-70% accuracy (with airpods switching)
- **phase 1 target**: 70-80% accuracy
- **phase 2 target**: 80-85% accuracy
- **phase 3 target**: 85-90% accuracy
- **acceptable threshold**: 85% (good enough for most users)

### measurement approach
1. create test set of 10 recordings with known transcripts
2. measure word error rate (wer) for each improvement
3. track specific problem areas (device switching, overlapping audio)
4. gather user feedback on perceived quality

## risk assessment

### low risk items ✅
- audio preprocessing (well-understood)
- device detection (browser apis available)
- dual-service approach (simple parallelization)

### medium risk items ⚠️
- intelligent merging (requires tuning)
- echo cancellation (cpu intensive)
- vad implementation (accuracy varies)

### mitigation strategies
- implement features behind flags
- test each improvement in isolation
- maintain rollback capability
- monitor performance metrics

## cost analysis

### development time
- phase 1: 1-2 days (low complexity)
- phase 2: 2-3 days (medium complexity)
- phase 3: 3-4 days (higher complexity)
- **total**: 6-9 days (vs 14+ for architectural pivot)

### runtime costs
- transcription: same as current ($0.054/hour)
- dual-service: 2x cost ($0.108/hour) if using both
- processing: minimal cpu overhead

### cost-benefit
- **investment**: 6-9 days development
- **benefit**: 85-90% accuracy (up from 50-70%)
- **roi**: significant improvement without architectural risk

## decision framework

### proceed to phase 2 if:
- phase 1 achieves >75% accuracy
- audio preprocessing shows measurable improvement
- device handling prevents acoustic coupling

### proceed to phase 3 if:
- phase 2 achieves >80% accuracy
- dual-service approach works well
- users still report issues with specific scenarios

### consider architectural pivot (3.3b) if:
- cannot achieve >85% accuracy
- audio quality remains primary bottleneck
- users demand real-time transcription

## immediate next steps

1. **today**: implement wav conversion pipeline
2. **tomorrow**: add noise gate and test
3. **day 3**: implement device detection
4. **day 4**: measure improvements and decide on phase 2

## conclusion

this incremental approach offers:
- **lower risk** than complete rewrite
- **faster results** (days vs weeks)
- **preserves existing work**
- **learns from each improvement**

recommended: **start with phase 1 immediately**