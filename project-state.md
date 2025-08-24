# AI&I Project State

## Project Overview
AI Meeting Transcription Tool using Electron + OpenAI Whisper API + Speaker Diarization

## Current Phase & Milestone
**Phase 1 - Milestone 1**: ✅ COMPLETE - Real-time transcription working with FFmpeg + AVFoundation
**Phase 1 - Milestone 2**: ✅ COMPLETE - Sally Rooney-style human-like summaries
**Current**: Ready for End-to-End Workflow (Real Meeting → Transcribe → Summarize)

## Critical Technical Architecture Decision ⚠️
**PROVEN APPROACH**: FFmpeg + AVFoundation (same as Granola, Loom, Zoom)
- ❌ NOT AudioTee (system audio only, no mic)
- ❌ NOT node-osx-audio (compatibility issues)  
- ❌ NOT node-mac-recorder alone (MP4 format issues)
- ✅ **FFmpeg with AVFoundation** - Industry standard, battle-tested

## Completed Steps ✅

### Phase 1 - Milestone 1: Complete Real-time Transcription System
1. **Project Foundation** ✅ - Basic structure, Electron app
2. **Mac Audio Permissions** ✅ - Screen recording & microphone access
3. **Audio Capture Evolution**:
   - Started with mock recording ✅
   - Tried node-mac-recorder (MP4 issues) ❌
   - Researched AudioTee (system audio only) ❌
   - Attempted osx-audio (Node version mismatch) ❌
   - **SOLUTION: FFmpeg + AVFoundation** ✅
4. **Whisper API Integration** ✅
   - Real-time PCM chunk processing
   - 5-second chunks for low latency
   - Speaker diarization enabled (but not supported by Whisper for audio)
   - Cost tracking: $0.006/minute
5. **Real-time UI Updates** ✅
   - Live transcription display
   - Enhanced visibility (green highlights for speech)
   - System messages muted
6. **Validation Framework** ✅
   - Performance monitoring
   - WER calculation tools
   - Extended test runner
   - Quick validation scripts

### Validation Test Results 🎯
**1-Minute Quick Test:**
- **Success Rate**: 100%
- **Processing Speed**: 1.47x real-time
- **Latency**: 2.3 seconds average
- **Cost**: $0.30/hour projected
- **Stability**: 0 errors

**Twitter Video Test (3.5 minutes):**
- **Total Words**: 702 transcribed
- **Estimated Accuracy**: ~84.5% (15% WER)
- **Cost**: $0.022 total
- **Quality**: Good, usable with minor cleanup

### Phase 1 - Milestone 2: Sally Rooney-Style Human-like Summaries ✅
7. **LLM Provider Research** ✅ - Comprehensive cost/quality analysis
8. **Sally Rooney Prompt Framework** ✅ - Emotional intelligence + business substance  
9. **Multi-LLM Integration** ✅ - GPT-5 + Gemini 1.5 Pro implementation
10. **Summary Generation Pipeline** ✅
    - Fixed GPT-5 reasoning token extraction issue
    - Proper file naming (gpt5-topic1.md, gem15-topic2.md)
    - Structured output: opening, key points, decisions, action items
    - Cost tracking and performance monitoring
11. **Quality Comparison Framework** ✅ - Side-by-side testing and analysis

### Summary Generation Test Results 🎯
**GPT-5 Performance:**
- **Cost**: $0.0054 per 3-min meeting summary  
- **Speed**: 24.8 seconds processing
- **Style**: Structured, business-focused with sally rooney warmth
- **Quality**: Excellent accuracy, clear action items

**Gemini 1.5 Pro Performance:**  
- **Cost**: $0.0059 per 3-min meeting summary
- **Speed**: 9.3 seconds processing (2.7x faster)
- **Style**: Emotionally perceptive, warmer narrative tone
- **Quality**: Excellent emotional intelligence, structured output

**Cost Scaling**: ~$0.03-0.06 per hour-long meeting summary

## Current Technical Stack
```javascript
// Complete ai&i Pipeline
FFmpeg (AVFoundation) → PCM Stream → Whisper API → Transcript → LLM → Sally Rooney Summary

// Audio Capture  
ffmpeg -f avfoundation -i ":0" -f s16le -acodec pcm_s16le -ar 16000 -ac 1 -

// Summary Generation
Transcript → [GPT-5 | Gemini 1.5 Pro] → Structured Summary (.md files)
```

## Key Files Structure
```
ai-and-i/
├── main.js                         # Electron main + real-time transcription
├── .env                           # OPENAI_API_KEY
├── project-state.md               # THIS FILE - Session continuity
├── MILESTONE_1_COMPLETION_REPORT.md # Comprehensive report
├── WER_OPTIMIZATION_GUIDE.md      # How to reach <5% WER
├── SPEAKER_DIARIZATION_SOLUTION.md # Speaker identification options
├── src/
│   ├── audio/
│   │   └── audioCapture.js        # FFmpeg + AVFoundation implementation
│   ├── api/
│   │   ├── whisperTranscription.js # Whisper API with PCM support
│   │   └── summaryGeneration.js   # GPT-5 + Gemini 1.5 Pro integration
│   ├── renderer/
│   │   ├── index.html             # UI with enhanced transcription display
│   │   ├── renderer.js            # Real-time updates, speaker labels
│   │   └── styles.css             # Green highlights for speech
│   ├── validation/
│   │   ├── performanceMonitor.js  # System metrics tracking
│   │   ├── accuracyMeasurement.js # WER calculation
│   │   └── extendedTestRunner.js  # 30-60 min test framework
│   └── storage/
├── run-validation-test.js         # Quick validation test (1-60 min)
├── test-with-audio-file.js        # Test any audio file  
├── test-summary-generation.js     # Test sally rooney summaries
├── debug-gpt5.js                  # GPT-5 debugging utilities
├── sally_rooney_prompt_framework.md # Prompt engineering framework
├── calculate-wer.js               # WER accuracy measurement
├── transcripts/                   # JSON transcripts from sessions
├── summaries/                     # GPT-5 & Gemini generated summaries
├── validation-reports/            # Test reports and summaries
└── audio-temp/                    # Temporary audio files

Dependencies: 
- electron, openai, @google/generative-ai, dotenv
- ffmpeg (system dependency - brew install ffmpeg)
- gh (github cli - brew install gh)
- NO native Node modules needed!
```

## Running the System

### Basic Usage
```bash
# Start app for real-time transcription
npm start

# Quick validation test (2 minutes)
node run-validation-test.js 2

# Test with audio file
node test-with-audio-file.js ~/Downloads/meeting.mp3

# Test summary generation
node test-summary-generation.js

# Calculate WER (with reference)
node calculate-wer.js transcribed.txt reference.txt
```

### Validation Commands
```bash
# Extended 30-minute test
node run-validation-test.js 30

# View latest report
cat validation-reports/*_summary.txt
```

## Known Issues & Solutions

### 1. Audio Format Compatibility
**Problem**: node-mac-recorder creates MP4 that ffmpeg can't read
**Solution**: Use ffmpeg directly with AVFoundation

### 2. Speaker Diarization
**Problem**: Whisper API doesn't provide speaker labels for audio
**Solutions**:
- Use AssemblyAI ($0.015/min with speakers)
- Add pyannote for speaker detection
- Simple heuristics based on pauses

### 3. Memory Usage
**Issue**: 98% memory usage during tests
**TODO**: Implement buffer cleanup and memory optimization

### 4. WER Improvement
**Current**: ~15% WER (84.5% accuracy)
**Target**: <5% WER
**Path**: See WER_OPTIMIZATION_GUIDE.md

## Next Steps: End-to-End Workflow

### Immediate Tasks  
1. **Real Meeting Integration**
   - Record actual meeting with transcription
   - Generate sally rooney-style summary automatically
   - Test full pipeline: Audio → Transcript → Summary

2. **Workflow Optimization**
   - Add summary generation to main electron app
   - Auto-generate summaries after meetings end
   - Save summaries alongside transcripts

### Technical Optimizations
1. **Reduce WER to <10%**
   - Increase chunk size to 30s
   - Add noise reduction
   - Implement context awareness

2. **Memory Optimization**
   - Fix 98% memory usage issue
   - Implement streaming cleanup
   - Add memory pressure handling

3. **Cost Optimization**
   - Batch processing for non-real-time
   - Implement local Whisper for offline
   - Add cost controls/limits

## Session Context for Resume
**CRITICAL**: Always use FFmpeg + AVFoundation approach. Do NOT try AudioTee, osx-audio, or other experimental libraries - they don't work for microphone capture.

**Working Pipeline**:
```javascript
// This works perfectly:
const ffmpegArgs = [
    '-f', 'avfoundation',
    '-i', ':0',  // Microphone
    '-f', 's16le',
    '-acodec', 'pcm_s16le',
    '-ar', '16000',
    '-ac', '1',
    '-loglevel', 'error',
    '-'
];
```

## Important Discoveries
1. **AudioTee** only captures system audio, not microphone
2. **node-mac-recorder** creates incompatible MP4 files
3. **Whisper API** doesn't support speaker diarization for audio
4. **FFmpeg + AVFoundation** is the proven solution used by all major apps
5. **5-second chunks** provide good balance of latency and context
6. **Cost**: $0.30-0.40/hour is sustainable for most use cases

## Test Results Archive
- `validation_1755932041000`: 1-min test, 100% success, 68 words
- `file_test_1756036758188`: Twitter video, 702 words, ~84.5% accuracy

---
Last Updated: 2025-08-24 (Milestone 2 COMPLETE - Sally Rooney Summaries)
Session Duration: ~8 hours  
Major Achievements: 
- Milestone 1: Real-time transcription with FFmpeg + AVFoundation
- Milestone 2: Human-like summaries with GPT-5 + Gemini 1.5 Pro
- Open source MIT licensed project on GitHub