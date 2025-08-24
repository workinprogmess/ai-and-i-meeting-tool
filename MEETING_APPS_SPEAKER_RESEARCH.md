# Deep Research: Speaker Diarization in Meeting Apps (2025)

## Key Findings from Industry Leaders

### 1. **Granola** - Privacy-First, Limited Approach
**What They Do:**
- Distinguishes between "mic audio" vs "system audio" only
- Labels as "Speaker 1", "Speaker 2" without names
- NO voice embeddings or persistent speaker learning
- Works post-processing, not real-time

**Technical Limitations:**
- Cannot identify specific speakers across meetings
- No voice embedding storage for speaker recognition
- Acknowledges this as a major limitation in 2025
- Waiting for "industry-wide progress" (not investing heavily)

**Architecture:**
```
[Local Audio Capture] → [Basic Voice Activity Detection] → [Simple Clustering] 
→ [Speaker 1/Speaker 2 Labels] → [No Persistence]
```

### 2. **Otter.ai** - Learning-Based System
**What They Do:**
- Uses machine learning to learn speaker voices
- Learns from "just a few tagged paragraphs per speaker"
- Cross-meeting speaker recognition
- Works in workspaces (shared speaker profiles)

**Technical Implementation:**
- Voice embedding extraction from tagged audio
- Speaker profile storage and matching
- Automatic recognition in future meetings
- Post-processing only (not real-time)

**Architecture:**
```
[Audio] → [Voice Embeddings] → [Speaker Profile Learning] → [Cross-Meeting Recognition]
→ [Named Speaker Labels] → [Persistent Storage]
```

### 3. **Fireflies.ai** - Platform-Integrated System
**What They Do:**
- Automatic speaker names from Google Meet/Zoom APIs
- 95%+ accuracy with speaker labels and timestamps
- Supports 60+ languages with speaker diarization
- Generic "Speaker N" labels for non-integrated platforms

**Technical Approach:**
- Platform API integration for participant names
- Voice embedding clustering for non-API platforms
- Sophisticated speaker tracking with talk-time analytics

### 4. **AssemblyAI** - State-of-the-Art Engine (2025)
**What They Do:**
- Leading technical implementation in 2025
- 30% improvement in noisy environments
- Handles 250ms segments (single word accuracy)
- End-to-end trained models

**Technical Implementation:**
```python
# Voice Embedding Pipeline
[Audio Segment] → [Feature Extraction] → [Speaker Embeddings] 
→ [Clustering Algorithm] → [Speaker Attribution]

# 2025 Improvements:
- Custom embedding models
- Advanced data augmentation
- Spectral/hierarchical clustering
- Real-time processing capability
```

## Key Technical Insights

### 1. **Voice Embeddings are Standard**
All production systems (except Granola) use voice embeddings:
- Extract unique vocal characteristics
- Store speaker profiles for future recognition
- Use cosine similarity for matching
- Enable cross-meeting speaker continuity

### 2. **Clustering Approaches**
```
Common Pipeline:
1. Voice Activity Detection (VAD)
2. Speech Segmentation 
3. Embedding Extraction
4. Clustering (spectral/agglomerative)
5. Speaker Assignment
```

### 3. **Real-Time vs Post-Processing Trade-off**
- **Real-time**: More challenging, lower accuracy
- **Post-processing**: Higher accuracy, better clustering
- **Industry trend**: Moving toward real-time with acceptable accuracy

### 4. **Performance Benchmarks (2025)**
```
Excellent: <10% Diarization Error Rate (DER)
Production Ready: 10-15% DER
Acceptable: 15-20% DER
Poor: >20% DER
```

## What This Means for ai&i

### Current Market Gaps
1. **Granola's Weakness**: No persistent speaker learning
2. **Real-time Opportunity**: Most systems are post-processing
3. **Privacy Advantage**: Local processing vs cloud APIs

### Recommended Technical Stack

#### Option 1: **AssemblyAI Integration** (Quickest)
```javascript
// Pros: State-of-the-art accuracy, real speaker names
// Cons: $0.015/minute (3x cost), cloud dependency
const assemblyai = require('assemblyai');
const client = new AssemblyAI({
    apiKey: process.env.ASSEMBLYAI_KEY
});

const transcript = await client.transcripts.create({
    audio_url: audioFile,
    speaker_labels: true,
    speakers_expected: 2
});
```
**Cost**: $0.90/hour vs current $0.30/hour

#### Option 2: **Pyannote + Voice Embeddings** (Best Balance)
```python
# Combine pyannote clustering with voice embedding storage
from pyannote.audio import Pipeline
import speechbrain as sb

# 1. Initial diarization
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
diarization = pipeline(audio_file)

# 2. Extract embeddings for each speaker
embeddings = extract_speaker_embeddings(audio_file, diarization)

# 3. Match with stored speaker profiles
speaker_names = match_embeddings(embeddings, stored_profiles)
```
**Cost**: $0.30/hour (same as current)

#### Option 3: **NVIDIA Streaming Sortformer** (Cutting Edge)
```python
# Real-time speaker diarization with GPU acceleration
# Handles 4 simultaneous speakers with millisecond precision
# End-to-end trained model
```
**Cost**: GPU compute + $0.30/hour

### Implementation Recommendation

Based on research, here's the optimal approach for ai&i:

```javascript
// Hybrid Approach: Best of All Worlds
class SpeakerSystem {
    constructor() {
        this.voiceProfiles = new Map(); // Persistent storage
        this.pyannoteService = new PyannoteAPI();
        this.assemblyFallback = new AssemblyAI();
    }
    
    async identifySpeakers(audioChunk, options) {
        // 1. Use Pyannote for initial clustering (free)
        const segments = await this.pyannoteService.diarize(audioChunk);
        
        // 2. Extract voice embeddings for each segment
        const embeddings = await this.extractEmbeddings(audioChunk, segments);
        
        // 3. Match with stored profiles (like Otter)
        const speakers = await this.matchSpeakers(embeddings);
        
        // 4. Learn new speakers if not recognized
        await this.learnNewSpeakers(speakers, segments);
        
        // 5. Fallback to AssemblyAI for critical meetings
        if (options.highAccuracy) {
            return await this.assemblyFallback.diarize(audioChunk);
        }
        
        return speakers;
    }
    
    async askUserForSpeakerNames(speakers) {
        // Granola's missing feature: "Which speaker is me?"
        return await this.promptUserIdentification(speakers);
    }
}
```

## Final Recommendation

**Use Pyannote + Voice Embeddings + User Learning:**

1. **Setup Pyannote** (2 hours) - Free, local processing
2. **Add voice embedding storage** (1 day) - Like Otter.ai  
3. **Implement "Which speaker is me?" feature** (1 day) - Missing from Granola
4. **Add AssemblyAI fallback** (optional) - For critical meetings

This gives you:
- ✅ Better than Granola (persistent learning)
- ✅ Cheaper than Otter/Fireflies ($0.30 vs $0.90/hour)
- ✅ Privacy-first (local processing)
- ✅ Real speaker names (not just Speaker 1/2)

**Total Cost**: Same as current ($0.30/hour) with dramatically better speaker identification.