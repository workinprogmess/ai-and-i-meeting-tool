# AI&I Project State

## Project Overview
AI Meeting Transcription Tool using Electron + OpenAI Whisper API + Speaker Diarization

## Current Phase & Milestone
**Phase 1 - Milestone 1**: ✅ COMPLETE - Real-time transcription working with FFmpeg + AVFoundation
**Phase 1 - Milestone 2**: ✅ COMPLETE - Sally Rooney-style human-like summaries
**Phase 1 - Milestone 2.5**: ✅ COMPLETE - Human-centered meeting intelligence as default experience
**Phase 1 - Milestone 3**: ⏳ IN PROGRESS - Beta-ready product experience (10-14 days)
**Phase 1 - Milestone 3.1.9**: ⏳ IN PROGRESS - Memory optimization & auto-updater validation
**Phase 1 - Milestone 4**: 📋 PLANNED - Enhanced collaboration and deployment (14-21 days)

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

### Phase 1 - Milestone 2.5: Human-Centered Meeting Intelligence ✅ COMPLETE
12. **Minimal Book-like UI Redesign** ✅ - Inter Tight typography, clean layout
13. **Sidebar Recordings List** ✅ - All meetings accessible from sidebar
14. **Tabbed Meeting View** ✅ - Summary vs Transcript tabs with copy functionality
15. **Integrated Workflow** ✅ - Record → Auto-transcribe → Auto-summarize
16. **Real-time Status Indicators** ✅ - Pastel recording dots, clean status updates
17. **Critical Production Bug Fixes** ✅
    - Fixed AudioCapture to save audio files (prevented data loss)
    - Fixed RecordingsDB persistence issues  
    - Fixed UI display showing "undefined undefined 3000"
18. **Development Guidelines Framework** ✅ - Comprehensive CLAUDE.md standards
19. **Data Recovery from CTO Meeting Crisis** ✅ - Partial transcript recovery, lessons learned
20. **Gemini End-to-End Pipeline as Default** ✅
    - Enhanced transcripts with @speaker references, _topic emphasis_, 🔵🟡🟠 emotional context
    - Human-centered summaries with relationship dynamics and meeting intelligence
    - Single API call efficiency vs multi-step whisper → gemini approach
    - Revolutionary differentiation from basic meeting tools

### Phase 1 - Milestone 3.1.9: Clean Gemini End-to-End Implementation ✅ CORE COMPLETE
21. **Removed All Whisper Dependencies** ✅ - Clean gemini-only pipeline in main.js
22. **Single Toggle Recording Button** ✅ - Unified start/stop UX with proper state management
23. **Meeting Sidebar Integration** ✅ - Meetings appear in sidebar during recording with processing states
24. **Wave Animation & Timer** ✅ - Visual feedback during recording with proper cleanup
25. **Welcome Message Implementation** ✅ - "your transcript and summary will be here soon, v" 
26. **Cost Display Fixes** ✅ - Proper cost tracking with totals and averages
27. **Enhanced Loading States** ✅ - Improved user feedback messages throughout workflow
28. **Memory Optimization** ⏳ IN PROGRESS - Stream-to-disk architecture to fix 98% usage
29. **Auto-updater Validation** 🔄 PENDING - Comprehensive testing of GitHub release system

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
FFmpeg (AVFoundation) → PCM Stream → Whisper API → Transcript → Auto-Summary → UI

// Audio Capture  
ffmpeg -f avfoundation -i ":0" -f s16le -acodec pcm_s16le -ar 16000 -ac 1 -

// End-to-End Workflow
Record → Live Transcription → Auto Sally Rooney Summary → Tabbed UI Display

// Summary Generation
Transcript → [GPT-5 | Gemini 1.5 Pro] → Formatted Summary + Copy Function
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
**Issue**: 98% memory usage during tests - IDENTIFIED ROOT CAUSE
**Solution**: Stream-to-disk architecture instead of accumulating audio chunks in memory
**Status**: ⏳ IN PROGRESS - Implementing streaming audio capture system

### 4. WER Improvement
**Current**: ~15% WER (84.5% accuracy)
**Target**: <5% WER
**Path**: See WER_OPTIMIZATION_GUIDE.md

## Phase 1 - Milestone 3: Beta-Ready Product Experience (10-14 Days)

### 3.1 App Packaging & Distribution (Days 1-3)
- **electron-builder setup** for .dmg distribution
- **auto-updater configuration** (self-hosted updates)
- **icon refinement** and app metadata
- **build pipeline** for releases
- **target:** distributable app for beta users

### 3.2 Reliability Improvements (Days 4-6) 
- **error recovery** for network failures during recording
- **audio backup** during processing (prevent data loss)
- **memory optimization** ⏳ IN PROGRESS - stream-to-disk audio architecture
- **beta feedback collection** mechanisms
- **target:** stable experience for 60+ minute meetings

### 3.3 Enhanced UI for Beta (Days 7-9)
- **onboarding flow** for new users
- **better recording management** (search, filters, export)
- **usage indicators** and meeting metadata display
- **account/settings page** foundation
- **target:** polished experience for beta users

### 3.4 Authentication & Backend (Days 10-12)
- **supabase pro setup** ($25/month for 100gb storage + 8gb database)
- **google oauth implementation** in electron (web flow)
- **user schema design** and session management
- **recordings sync** to cloud storage
- **target:** user accounts and data persistence

### 3.5 Payment Integration (Days 13-14)
- **stripe setup** with granola-inspired pricing
- **subscription gates** (free: 10 meetings, pro: $25/month unlimited)
- **basic billing portal** for plan management
- **usage tracking** per user
- **target:** monetization framework

## Phase 1 - Milestone 4: Enhanced Collaboration (14-21 Days)

### 4.1 Calendar Integration
- **google calendar sync** for automatic meeting detection
- **meeting context** pre-population (participants, agenda)
- **post-meeting summary** delivery to attendees

### 4.2 Collaborative Features  
- **meeting sharing** with attendees
- **team workspaces** for organizations
- **comment/annotation** system on transcripts
- **export formats** (pdf, notion, slack integration)

### 4.3 Advanced Intelligence
- **action item extraction** and follow-up tracking  
- **meeting series analysis** (recurring themes, progress tracking)
- **participant insights** (contribution analysis, speaking time)

### 4.4 Enterprise Ready
- **sso integration** (okta, azure ad)
- **admin dashboard** for team management
- **compliance features** (data retention, audit logs)
- **custom branding** and white-label options

## Technical Research: Supabase vs Firebase

### Decision: Supabase Pro ($25/month)

**cost analysis at scale:**
- **100 users:** supabase $25/month vs firebase $40-60/month
- **1,000 users:** supabase $25-50/month vs firebase $200-400/month  
- **10,000 users:** supabase $100-200/month vs firebase $2000+/month

**key advantages:**
- **fixed pricing model** vs firebase's expensive usage-based costs
- **better for large files** (50gb uploads vs firebase's expensive storage/egress)
- **postgresql database** perfect for meeting→user→transcript relationships
- **unified authentication** included in base pricing
- **open-source** foundation prevents vendor lock-in

**architecture decision:**
- **metadata in postgres:** user accounts, meeting records, subscription status
- **large files in supabase storage:** audio files, full transcripts, summaries
- **single provider simplicity** vs multi-service complexity

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

## Development Workflow: Git Branching Strategy

### New Approach (Following Industry Best Practices)
- **main/master branch:** stable, production-ready releases only (v1.0, v1.1, etc.)
- **develop branch:** integration branch for all features in development  
- **feature/milestone-x-y:** individual feature branches off develop

### Benefits
- **main stays stable** for users downloading releases
- **parallel development** of multiple features
- **proper release management** with version tags
- **hotfix capability** without breaking ongoing development

### Implementation
```bash
# create develop branch from current main
git checkout -b develop
git push -u origin develop

# future feature work
git checkout develop
git checkout -b feature/milestone-3-packaging
# ... work on feature ...
git checkout develop
git merge feature/milestone-3-packaging
```

## Current Session Context (2025-08-26)

### Technical Decisions Made Today
1. **Backend Selection:** supabase pro ($25/month) over firebase for cost efficiency and postgresql database
2. **Git Workflow:** implemented main/develop/feature branching with versioning: v0.1 (m1), v0.2 (m2), v0.25 (m2.5), v0.3 (m3)
3. **Milestone 3 Priority Reordering:** app packaging first → reliability → ui → auth → payments (user's strategic insight)
4. **Pricing Strategy:** copy granola's model - free: 10 meetings, pro: $25/month unlimited
5. **Repository Updates:** updated readme.md, created develop branch, tagged v0.25, created github release

### Key Insights from Friend's Git Advice
- proper branching strategy essential for beta deployment
- main branch = stable releases only
- develop branch = integration of all features
- feature branches = individual milestone work
- enables parallel development and proper release management

### Current State
- **branch:** develop (with milestone 3/4 roadmap)
- **tagged:** v0.25 (milestone 2.5 complete)  
- **next:** start feature/milestone-3-packaging branch for electron-builder setup
- **licensing:** mit for now, business source license research postponed until actual users

### Session Continuity Notes
- readme.md updated to reflect gemini end-to-end breakthrough vs basic meeting tools
- project-state.md contains comprehensive milestone 3/4 plans and supabase research
- git workflow established with proper version tagging scheme
- ready to begin milestone 3.1: app packaging (days 1-3 of 14-day beta-ready plan)

## Current Session Context (2025-08-27)

### milestone 3.1 progress: app packaging & distribution

**issue discovered & resolved: electron-builder stack overflow**
- **problem**: electron-builder v26.0.12 had infinite recursion bug in nodeModulesCollector
- **failed attempts**: 
  - file exclusion patterns in package.json
  - fresh node_modules installation
  - minimal configuration approach
- **solution**: downgraded to electron-builder v24.13.3 (stable version)
- **result**: successful .dmg and .zip builds at ~112MB each

**version correction**: updated from incorrect 1.0.1 → correct v0.3.0 (milestone 3)

**auto-updater implementation completed:**
- installed electron-updater v6.6.2 with github releases integration
- configured auto-updater event handlers (check, download, install)
- added ipc handlers for manual update controls  
- set up github releases as update server (provider: github)
- auto-check for updates on app startup (production builds only)

**beta testing feedback (critical issues discovered):**
- **dmg installation failure**: "damaged, move to trash" error prevents app installation
- **app icon formatting**: sharp corners + grey space in applications folder display
- **menu bar icon color**: black text invisible on macos menu bar (fixed to white/bold)
- **user experience**: need in-app update notifications like figma/amie (sidebar bottom)
- **milestone 3.1 incomplete**: memory optimization, universal binaries, error recovery pending

**current build output:**
```
dist/ai&i-0.3.0-arm64.dmg (112MB)
dist/ai&i-0.3.0-arm64-mac.zip (113MB)  
dist/latest-mac.yml (auto-updater metadata)
```

**packaging status:**
- ✅ basic .dmg distribution working  
- ✅ custom ai&i branding icons implemented
- ✅ auto-updater configuration complete (electron-updater + github releases)
- ❌ **critical issue**: dmg shows "damaged, move to trash" error - blocks installation
- ❌ **app icon display**: sharp corners + grey space in applications folder
- ✅ **menu bar icon**: fixed to white/bold for proper macos styling
- ⚠️  no code signing (likely cause of dmg damaged error)
- ⚠️  arm64 only (need intel + universal builds)  
- 📋 next: fix dmg installation, app icon formatting, in-app update notifications

---
Last Updated: 2025-08-27 (milestone 3.1 packaging in progress)
Session Duration: ~22 hours across multiple sessions  
Major Achievements: 
- milestone 1: real-time transcription with ffmpeg + avfoundation
- milestone 2: human-like summaries with gpt-5 + gemini 1.5 pro  
- milestone 2.5: human-centered meeting intelligence as default experience
- **milestone 3.1 (partial): working .dmg distribution with electron-builder v24.13.3**
- breakthrough: gemini end-to-end pipeline with emotional journey transcripts
- differentiation: revolutionary alternative to basic meeting tools (granola/otter)
- crisis resolved: 50-minute cto meeting recovery + production reliability fixes
- technical decisions: supabase pro backend, proper git workflow, electron-builder downgrade
- open source mit licensed project on github (license review pending)

## Phase 1 - Milestone 3.1.9: Clean Gemini End-to-End Implementation 🚀

### Critical Learning & Course Correction
**Problem Identified**: milestone 2.5 was marked complete but integration was broken
- gemini end-to-end method (`processAudioEndToEnd`) existed but was never called by main.js
- whisper live transcription still running (should have been removed)
- recording workflow got stuck in "generating summary" state
- dual pipeline complexity created version conflicts and ui sync issues

**Solution**: clean implementation with gemini-only pipeline

### Core Architecture Changes
**Pipeline Simplification**:
- ❌ **Remove entirely**: whisper api, live transcription, real-time chunks
- ✅ **Single pipeline**: audio file → gemini 2.5 flash → transcript + summary
- ✅ **Clean main.js**: record → save audio → gemini processing → ui update

### User Experience Design  
**Recording Flow**:
1. **Single Toggle Button**: "start recording" ↔ "stop recording" 
2. **Immediate Sidebar Meeting**: appears when recording starts with timer
3. **Visual Recording State**: 
   - main screen: timer + beautiful wave animation
   - sidebar meeting: timer + smaller wave animation
4. **No Live Transcription**: clean, distraction-free recording

**Post-Recording Flow**:
1. **Stop → Welcome Message**: "your transcript and summary will be here soon, v"
2. **Tabs with Loading States**: show transcript and summary tabs immediately
3. **Sequential Population**: transcript appears first, then summary (as generated)
4. **User Name**: hardcoded as "v" until authentication in later milestone

### Cost Tracking Enhancement
**Comprehensive Cost Analytics**:
- total historical spend (all whisper + gemini costs from past sessions)
- current meeting cost (gemini end-to-end processing) 
- average cost per meeting (total spend ÷ number of meetings)
- display in status bar area

### Technical Implementation Tasks
1. **Remove Whisper Dependencies**: clean removal of whisperTranscription.js usage
2. **Integrate Gemini Pipeline**: main.js calls `processAudioEndToEnd` method  
3. **UI Redesign**: remove live transcript area, add wave animations
4. **Cost System**: aggregate historical costs, calculate averages
5. **Stress Test Milestone 3.1**: auto-updater, icons, installation workflows

### Success Criteria
- ✅ single button recording workflow
- ✅ clean gemini-only processing (no whisper)
- ✅ beautiful recording animations and states
- ✅ reliable meeting completion and sidebar population  
- ✅ comprehensive cost tracking with averages
- ✅ all milestone 3.1 features working (auto-updater, icons, installation)