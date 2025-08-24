# Pyannote + Whisper Implementation Guide

## Overview
Pyannote.audio is the best open-source speaker diarization library, used by many production systems.

## Architecture Options

### Option 1: Local Python Service (Recommended for MVP)
```
[Node.js App] → HTTP → [Python Service with Pyannote] → Diarization
     ↓                                                      ↓
[Whisper API] ← Merge timestamps ← ← ← ← ← ← ← ← ← ← ← ← ↓
```

### Implementation

#### 1. Python Service (diarization_service.py)
```python
from flask import Flask, request, jsonify
from pyannote.audio import Pipeline
import torch
import numpy as np
from scipy.io import wavfile
import tempfile
import os

app = Flask(__name__)

# Load model once (requires Hugging Face token)
pipeline = Pipeline.from_pretrained(
    "pyannote/speaker-diarization-3.1",
    use_auth_token="YOUR_HF_TOKEN"
)

# Use GPU if available
if torch.cuda.is_available():
    pipeline = pipeline.to(torch.device("cuda"))

@app.route('/diarize', methods=['POST'])
def diarize_audio():
    """
    Accepts PCM audio data and returns speaker segments
    """
    try:
        # Get PCM data from request
        pcm_data = request.data
        sample_rate = request.args.get('sample_rate', 16000, type=int)
        
        # Convert PCM to WAV temporarily
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
            # Write WAV header and PCM data
            samples = np.frombuffer(pcm_data, dtype=np.int16)
            wavfile.write(tmp_file.name, sample_rate, samples)
            
            # Run diarization
            diarization = pipeline(tmp_file.name)
            
            # Clean up
            os.unlink(tmp_file.name)
        
        # Convert to JSON-serializable format
        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                'start': turn.start,
                'end': turn.end,
                'speaker': speaker,
                'duration': turn.end - turn.start
            })
        
        return jsonify({
            'success': True,
            'segments': segments,
            'num_speakers': len(diarization.labels())
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'gpu': torch.cuda.is_available()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555, debug=False)
```

#### 2. Node.js Integration (enhancedWhisper.js)
```javascript
const axios = require('axios');

class WhisperWithDiarization {
    constructor() {
        this.diarizationUrl = 'http://localhost:5555/diarize';
        this.whisperApi = new WhisperTranscription();
    }
    
    async transcribeWithSpeakers(pcmData, sampleRate = 16000) {
        try {
            // 1. Get speaker segments from Pyannote
            console.log('🎯 Getting speaker diarization...');
            const diarizationResponse = await axios.post(
                this.diarizationUrl + `?sample_rate=${sampleRate}`,
                pcmData,
                {
                    headers: { 'Content-Type': 'application/octet-stream' },
                    maxBodyLength: Infinity
                }
            );
            
            const speakers = diarizationResponse.data.segments;
            console.log(`✅ Found ${diarizationResponse.data.num_speakers} speakers`);
            
            // 2. Get transcription from Whisper
            console.log('📝 Getting transcription...');
            const transcription = await this.whisperApi.transcribePCMChunk({
                pcmData,
                sampleRate,
                channels: 1
            });
            
            // 3. Merge speaker segments with transcription
            const result = this.mergeTranscriptionWithSpeakers(
                transcription,
                speakers
            );
            
            return result;
            
        } catch (error) {
            console.error('❌ Diarization failed:', error.message);
            // Fallback to Whisper-only
            return this.whisperApi.transcribePCMChunk({ pcmData, sampleRate });
        }
    }
    
    mergeTranscriptionWithSpeakers(transcription, speakers) {
        // Whisper provides word-level timestamps in verbose_json format
        const words = transcription.words || [];
        const segments = [];
        
        for (const speaker of speakers) {
            // Find words that fall within this speaker's time range
            const speakerWords = words.filter(word => 
                word.start >= speaker.start && word.end <= speaker.end
            );
            
            if (speakerWords.length > 0) {
                segments.push({
                    speaker: speaker.speaker,
                    start: speaker.start,
                    end: speaker.end,
                    text: speakerWords.map(w => w.word).join(' '),
                    confidence: speakerWords.reduce((sum, w) => 
                        sum + (w.probability || 1), 0) / speakerWords.length
                });
            }
        }
        
        // Format final output
        return {
            success: true,
            fullText: transcription.text,
            segments: segments,
            speakers: [...new Set(speakers.map(s => s.speaker))],
            formattedTranscript: this.formatTranscript(segments)
        };
    }
    
    formatTranscript(segments) {
        return segments.map(seg => 
            `[${this.formatTime(seg.start)}] ${seg.speaker}: ${seg.text}`
        ).join('\n\n');
    }
    
    formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }
}
```

### Setup Requirements

#### 1. Install Python Dependencies
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install packages
pip install torch torchaudio
pip install pyannote.audio
pip install flask scipy numpy

# For M1/M2 Macs (Apple Silicon)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

#### 2. Get Hugging Face Token
1. Sign up at https://huggingface.co
2. Accept pyannote model terms: https://huggingface.co/pyannote/speaker-diarization-3.1
3. Create token: https://huggingface.co/settings/tokens
4. Add to environment: `export HF_TOKEN=your_token_here`

#### 3. Start Services
```bash
# Terminal 1: Python diarization service
python diarization_service.py

# Terminal 2: Node.js app
npm start
```

## Costs & Performance

### Pyannote Costs
- **Model**: FREE (open source)
- **Compute**: Local CPU/GPU only
- **Processing time**: 
  - CPU (M2): ~0.5x real-time (2 min audio = 1 min processing)
  - GPU (NVIDIA): ~0.1x real-time (2 min audio = 12 sec processing)
  - Apple Silicon: ~0.3x real-time

### Total System Costs
```
Current (Whisper only): $0.30/hour
With Pyannote (local): $0.30/hour (no additional API cost)
Electricity cost: ~$0.01/hour (negligible)
```

### Memory Requirements
- Pyannote model: ~500MB RAM
- Processing overhead: ~200MB per minute of audio
- Total for 1-hour meeting: ~1.5GB RAM

## Alternative: Cloud-Based Solutions

### AssemblyAI (Simpler but Costs More)
```javascript
// No Python needed - pure API solution
const { AssemblyAI } = require('assemblyai');

const client = new AssemblyAI({
    apiKey: process.env.ASSEMBLYAI_API_KEY  // ~$0.015/minute
});

async function transcribeWithSpeakers(audioFile) {
    const transcript = await client.transcripts.create({
        audio_url: audioFile,
        speaker_labels: true,
        speakers_expected: 2  // Optional: if you know speaker count
    });
    
    // Returns with speaker labels built-in
    return transcript.utterances;
}
```

**Costs**: $0.015/minute = $0.90/hour (3x more than Whisper)

## Recommendation for MVP

**Use Pyannote + Whisper because:**
1. **No additional API costs** (runs locally)
2. **Best accuracy** for speaker diarization
3. **Privacy** - audio stays on device
4. **Customizable** - can fine-tune for your voice

**Setup time**: 2-3 hours
**Complexity**: Medium (Python service needed)
**Quality**: Production-ready