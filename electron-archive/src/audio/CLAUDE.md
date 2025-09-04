# Audio Processing Guidelines - ai&i

## core requirements
- **zero data loss**: audio recordings are irreplaceable, every second must be preserved
- **real-time processing**: 5-second chunks for live transcription feedback
- **production reliability**: handle 60+ minute meetings without failure

## audio capture standards
### format specifications
- **sample rate**: 16kHz (optimal for speech recognition)
- **channels**: mono (reduces file size, sufficient for meetings)
- **bit depth**: 16-bit PCM (balance of quality vs efficiency)
- **chunk duration**: 5 seconds (real-time feedback without overwhelming APIs)

### recording architecture
- **streaming + saving**: capture for real-time transcription AND save complete audio file
- **PCM buffer management**: accumulate chunks while processing, combine at end
- **WAV file creation**: proper headers, playable files for backup/review
- **error recovery**: partial recordings must still save available audio

## competitive research
### how industry leaders handle audio
- **granola**: captures system audio directly for real-time transcription, no traditional audio file recording
- **otter**: offers both audio/video recording + transcription, mixed accuracy reviews for multi-speaker scenarios
- **zoom**: local recording + cloud backup with automatic transcription

### timing accuracy findings (2025-08-29)
- **our current issue**: consistent ~11% duration loss across recordings (451s → 401s, 308s → 274s)
- **ffmpeg + avfoundation**: known timing issues documented in ffmpeg bug tracker #4089
- **avfoundation delays**: can vary from 0.5-2+ seconds, affects audio-video sync in screen capture
- **industry approach**: successful apps like granola avoid traditional recording, use system audio capture instead

## file management
### storage strategy
- **primary storage**: `audio-temp/session_[ID].wav` for immediate access
- **backup strategy**: consider cloud storage for important meetings
- **cleanup policy**: archive or delete old recordings based on user preference
- **naming convention**: session ID + timestamp for easy identification

## quality assurance
### testing requirements
- **duration tests**: verify 60+ minute recordings work reliably  
- **interruption handling**: ensure recording continues despite app issues
- **format validation**: generated WAV files must be playable
- **size estimation**: ~6MB per minute at 16kHz mono 16-bit

### performance monitoring
- **memory usage**: avoid accumulating too much audio data in RAM
- **disk space**: monitor available storage, warn user when low
- **processing latency**: PCM chunk processing should not block recording
- **error logging**: detailed logs for debugging audio issues