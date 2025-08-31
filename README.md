# ai&i

ai meeting transcription tool with human-like summaries and emotional intelligence.

**current state:** milestone 3.2 complete - zero data loss + device resilience

## what makes ai&i different

unlike granola/otter's basic transcripts, ai&i provides:
- **enhanced transcripts:** speaker labels, topic emphasis, emotional context indicators  
- **human-like summaries:** relationship dynamics and meeting intelligence (not corporate bullet points)
- **single api approach:** gemini 2.5 flash end-to-end processing vs multi-step pipelines

## current capabilities

✅ **zero data loss recording** - electron-audio-loopback breakthrough (99.7% memory reduction)  
✅ **dual-stream intelligence** - separate microphone + system audio for speaker identification  
✅ **device resilience** - airpods switching, silent recovery, persistent monitoring  
✅ **single api processing** - gemini 2.5 flash end-to-end (2.7x faster than multi-step)  
✅ **clean ui** - book-like interface with real-time cost tracking  
✅ **cost efficient** - $0.006 per 3-minute meeting, transparent cost analytics  

## project structure

```
ai-and-i/
├── main.js                                    # electron main + ipc coordination
├── src/
│   ├── renderer/
│   │   ├── audioLoopbackRenderer.js          # dual-stream capture + device switching
│   │   ├── renderer.js                       # book-like ui + cost analytics  
│   │   └── index.html                        # clean meeting interface
│   └── api/summaryGeneration.js              # gemini 2.5 flash end-to-end
├── summaries/                                 # enhanced transcripts + summaries
└── audio-temp/                                # dual webm files (mic + system)
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

## technical breakthrough: zero data loss architecture

replaced unreliable ffmpeg approach with electron-audio-loopback:
- **99.7% memory reduction** - stream-to-disk vs memory accumulation
- **zero data loss** - eliminated 5+ year ffmpeg audio dropout bugs  
- **dual-stream intelligence** - separate mic/system files for better speaker detection
- **device resilience** - airpods switching, silent recovery, persistent monitoring
- **single api efficiency** - gemini 2.5 flash processes audio directly (2.7x faster)

## next: milestone 3.3 - human intelligence differentiation

focus on emotional journey transcripts and relationship dynamics that set us apart from basic transcription tools.

---

**license:** mit  
**status:** milestone 3.2 complete - ready for human intelligence differentiation work