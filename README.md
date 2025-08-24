# ai&i

A real-time meeting transcription tool using OpenAI Whisper API with speaker diarization.

## Project Structure

```
ai-and-i/
├── main.js                 # Electron main process
├── package.json            # Dependencies and scripts
├── src/
│   ├── renderer/           # Frontend UI (vanilla HTML/CSS/JS)
│   │   ├── index.html      # Main UI
│   │   ├── styles.css      # Styling
│   │   └── renderer.js     # Frontend logic
│   ├── audio/              # Audio capture logic
│   ├── storage/            # JSON file storage
│   └── api/                # OpenAI Whisper API integration
├── assets/                 # Static assets
└── transcripts/            # Saved meeting transcripts (JSON)
```

## Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Run production build
npm start
```

## Milestone 1 Features

- [x] Electron app foundation
- [ ] Mac screen recording audio capture
- [ ] OpenAI Whisper API integration
- [ ] Speaker diarization
- [ ] Real-time transcript display
- [ ] JSON file storage
- [ ] API cost tracking

## Technical Decisions

- **Audio Capture**: Mac screen recording API for system audio
- **Transcription**: OpenAI Whisper API with chunking
- **UI Framework**: Vanilla HTML/CSS for rapid development
- **Storage**: JSON files per meeting for simplicity
- **Platform**: Mac-focused for Milestone 1