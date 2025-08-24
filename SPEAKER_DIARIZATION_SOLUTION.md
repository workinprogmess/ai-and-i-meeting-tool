# Speaker Diarization Solution

## Current Issue
Whisper API doesn't provide speaker diarization for audio files (only for video files with visual cues).

## Solutions

### 1. **Quick Solution: Pyannote + Whisper**
```python
# Use pyannote for speaker diarization
from pyannote.audio import Pipeline
import whisper

# 1. Diarize speakers
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization")
diarization = pipeline("audio.wav")

# 2. Transcribe with Whisper
model = whisper.load_model("base")
result = model.transcribe("audio.wav")

# 3. Combine results
for segment, _, speaker in diarization.itertracks(yield_label=True):
    # Match timestamps with transcription
    text = get_text_for_timerange(result, segment.start, segment.end)
    print(f"Speaker {speaker}: {text}")
```

### 2. **API Solution: AssemblyAI**
```javascript
// AssemblyAI provides both transcription AND speaker diarization
const { AssemblyAI } = require('assemblyai');

const client = new AssemblyAI({
    apiKey: process.env.ASSEMBLYAI_API_KEY
});

async function transcribeWithSpeakers(audioFile) {
    const transcript = await client.transcripts.create({
        audio_url: audioFile,
        speaker_labels: true  // Enable speaker diarization
    });
    
    // Returns transcription with speaker labels
    return transcript.utterances.map(u => ({
        speaker: `Speaker ${u.speaker}`,
        text: u.text,
        start: u.start,
        end: u.end
    }));
}
```

### 3. **Hybrid Solution: Voice Embeddings**
```javascript
// Use voice embeddings to identify speakers
class SpeakerIdentification {
    constructor() {
        this.speakerEmbeddings = new Map();
    }
    
    async identifySpeaker(audioChunk) {
        // Extract voice embedding
        const embedding = await this.extractEmbedding(audioChunk);
        
        // Compare with known speakers
        for (const [speaker, knownEmbedding] of this.speakerEmbeddings) {
            const similarity = this.cosineSimilarity(embedding, knownEmbedding);
            if (similarity > 0.85) {
                return speaker;
            }
        }
        
        // New speaker
        const newSpeaker = `Speaker ${this.speakerEmbeddings.size + 1}`;
        this.speakerEmbeddings.set(newSpeaker, embedding);
        return newSpeaker;
    }
}
```

### 4. **Simple Heuristic Solution**
```javascript
// For 2-speaker conversations (meetings)
class SimpleSpeakerDiarization {
    constructor() {
        this.lastSpeaker = null;
        this.speakerPatterns = {
            speaker1: [], // Voice characteristics
            speaker2: []
        };
    }
    
    detectSpeakerChange(audioFeatures) {
        // Detect silence gaps (speaker changes often occur after pauses)
        const silenceGap = audioFeatures.silenceDuration > 1.5; // seconds
        
        // Detect voice pitch change
        const pitchChange = Math.abs(audioFeatures.pitch - this.lastPitch) > 50; // Hz
        
        // Detect energy level change  
        const energyChange = Math.abs(audioFeatures.energy - this.lastEnergy) > 0.3;
        
        if (silenceGap && (pitchChange || energyChange)) {
            // Speaker change detected
            this.lastSpeaker = this.lastSpeaker === 'Speaker 1' ? 'Speaker 2' : 'Speaker 1';
        }
        
        return this.lastSpeaker;
    }
}
```

### 5. **Recommended Implementation for ai&i**

```javascript
// Enhanced whisperTranscription.js with speaker diarization
class EnhancedWhisperTranscription {
    async transcribeWithSpeakers(audioFile) {
        // Option A: Use AssemblyAI for both
        if (process.env.ASSEMBLYAI_API_KEY) {
            return this.assemblyAITranscribe(audioFile);
        }
        
        // Option B: Use Whisper + Simple heuristics
        const transcription = await this.whisperTranscribe(audioFile);
        const speakers = await this.detectSpeakers(audioFile);
        
        return this.mergeSpeakersWithTranscription(transcription, speakers);
    }
    
    async detectSpeakers(audioFile) {
        // Analyze audio for speaker changes
        const audioAnalysis = await this.analyzeAudio(audioFile);
        
        const speakers = [];
        let currentSpeaker = 'Speaker 1';
        
        audioAnalysis.segments.forEach((segment, i) => {
            // Check for speaker change indicators
            if (segment.silence > 1.5 && i > 0) {
                // Likely speaker change after long pause
                currentSpeaker = currentSpeaker === 'Speaker 1' ? 'Speaker 2' : 'Speaker 1';
            }
            
            speakers.push({
                start: segment.start,
                end: segment.end,
                speaker: currentSpeaker
            });
        });
        
        return speakers;
    }
}
```

## Quick Fix for Current System

Add this to your `whisperTranscription.js`:

```javascript
// Simple speaker alternation based on pauses
addSpeakerLabels(text, duration) {
    const sentences = text.split(/[.!?]+/);
    let currentSpeaker = 'Speaker 1';
    const result = [];
    
    sentences.forEach((sentence, i) => {
        // Switch speakers every 2-3 sentences (heuristic)
        if (i > 0 && i % 3 === 0) {
            currentSpeaker = currentSpeaker === 'Speaker 1' ? 'Speaker 2' : 'Speaker 1';
        }
        
        if (sentence.trim()) {
            result.push(`${currentSpeaker}: ${sentence.trim()}`);
        }
    });
    
    return result.join('\n');
}
```

## Cost Comparison
- **Whisper only**: $0.006/minute (no speakers)
- **AssemblyAI**: $0.015/minute (with speakers)  
- **Whisper + Pyannote**: $0.006/minute + compute cost
- **Whisper + Heuristics**: $0.006/minute (rough speakers)

## Recommendation
For MVP: Use simple heuristics
For Production: Use AssemblyAI or Pyannote