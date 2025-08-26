# ai&i

ai meeting transcription tool with human-like summaries and emotional intelligence.

**current state:** milestone 2.5 complete - breakthrough human-centered meeting intelligence

## what makes ai&i different

unlike granola/otter's basic transcripts, ai&i provides:
- **enhanced transcripts:** speaker labels, topic emphasis, emotional context indicators  
- **human-like summaries:** relationship dynamics and meeting intelligence (not corporate bullet points)
- **single api approach:** gemini 2.5 flash end-to-end processing vs multi-step pipelines

## current capabilities

✅ **real-time transcription** - ffmpeg + avfoundation + whisper api  
✅ **human-like summaries** - sally rooney style emotional intelligence  
✅ **enhanced transcripts** - @speaker references, _topic emphasis_, 🔵🟡🟠 emotional journey  
✅ **clean ui** - book-like interface with sidebar recordings and tabbed view  
✅ **cost efficient** - $0.30/hour transcription, $0.03-0.06/hour summary generation  

## project structure

```
ai-and-i/
├── main.js                         # electron main + real-time transcription
├── src/
│   ├── audio/audioCapture.js       # ffmpeg + avfoundation implementation  
│   ├── api/
│   │   ├── whisperTranscription.js # whisper api integration
│   │   └── summaryGeneration.js    # gemini 2.5 flash end-to-end
│   ├── renderer/                   # clean book-like ui
│   └── storage/                    # recordings database
├── summaries/                      # generated transcripts + summaries
└── audio-temp/                     # captured audio files
```

## usage

```bash
# start the app
npm start

# test summary generation  
node test-summary-generation.js

# test with audio file
node test-with-audio-file.js ~/path/to/meeting.mp3
```

## technical breakthrough: gemini end-to-end

replaced whisper → gemini pipeline with single gemini 2.5 flash call:
- **2.7x faster processing** (9.3s vs 24.8s)  
- **enhanced transcripts** with speaker analysis and emotional context
- **human-centered summaries** with relationship dynamics
- **cost competitive** at $0.0059 per 3-minute meeting

## next: phase 1 - milestone 3 (beta ready)

planning authentication, payments, app packaging for 5-10 beta users.

---

**license:** mit  
**status:** milestone 2.5 complete, ready for milestone 3 planning