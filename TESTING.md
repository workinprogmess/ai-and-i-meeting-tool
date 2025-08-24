# AI&I Testing Checklist

## Pre-Testing Setup ✅
- [x] OpenAI API dependencies installed (openai, dotenv)
- [x] .env file created (needs actual API key)
- [x] Electron app launching successfully
- [x] macOS permissions system triggered

## Testing Phases

### Phase 1: Basic Functionality Tests
- [ ] **App Launch**
  - [ ] Electron window opens correctly
  - [ ] UI elements load (Record/Stop buttons, transcript area, cost counter)
  - [ ] Console shows no critical errors

- [ ] **API Connection Test**
  - [ ] Add valid OpenAI API key to .env
  - [ ] Click "Start Recording"
  - [ ] Verify "Testing OpenAI API connection..." message
  - [ ] Should show "✅ OpenAI API connection successful" OR error message

- [ ] **Permission Handling**
  - [ ] System Preferences should open automatically
  - [ ] App appears in Security & Privacy > Screen Recording
  - [ ] Grant permission and test recording start

### Phase 2: Recording Workflow Tests
- [ ] **Mock Recording Test**
  - [ ] Click "Start Recording" with all permissions
  - [ ] Verify status changes to "Recording"
  - [ ] Check that session ID is generated
  - [ ] Verify buttons state (Record disabled, Stop enabled)

- [ ] **Audio Chunk Processing**
  - [ ] Wait for 10-second chunks to be created
  - [ ] Check console for "Audio chunk created" messages
  - [ ] Verify audio-temp directory gets files
  - [ ] Look for "🎵 Transcribing audio:" messages (if API key valid)

- [ ] **Stop Recording Test**
  - [ ] Click "Stop Recording"
  - [ ] Verify status changes back to "Ready"
  - [ ] Check that transcript saving process completes
  - [ ] Verify JSON file created in transcripts/ directory

### Phase 3: API Integration Tests
- [ ] **Whisper API Integration**
  - [ ] Provide valid OpenAI API key
  - [ ] Start recording and wait for chunk processing
  - [ ] Verify real transcription appears (not mock text)
  - [ ] Check for speaker diarization results
  - [ ] Monitor API cost tracking updates

- [ ] **Error Handling Tests**
  - [ ] Test with invalid API key
  - [ ] Test with no API key
  - [ ] Test with network disconnection
  - [ ] Verify appropriate error messages shown

### Phase 4: Data Persistence Tests
- [ ] **Transcript Storage**
  - [ ] Complete a recording session
  - [ ] Check transcripts/ directory for JSON file
  - [ ] Verify JSON structure includes:
    - sessionId, timestamp, duration
    - transcript text and segments
    - speaker information
    - cost tracking
    - metadata

- [ ] **File Management**
  - [ ] Verify audio-temp files are created during recording
  - [ ] Check cleanup process after recording stops
  - [ ] Test multiple recording sessions

## Current Testing Status
**Phase**: 1 (Basic Functionality Tests)
**App Status**: ✅ Launched successfully
**Next Action**: Add valid OpenAI API key and test connection

## Testing Notes
- App started without errors
- macOS permission registration triggered
- Ready for API key configuration

---
Updated: 2025-08-22