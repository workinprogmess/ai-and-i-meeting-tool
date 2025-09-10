# device switching architecture for ai&i

## acknowledgment
special thanks to our audio engineering friend whose production expertise transformed this from a basic implementation into a robust, professional-grade solution. their insights on segmentation, quality guards, and timeline preservation were invaluable.

## problem statement
meeting tools must handle dynamic audio device changes seamlessly:
- users plug in airpods mid-meeting
- bluetooth devices disconnect unexpectedly  
- users switch between headphones and speakers
- system audio devices change (external displays, etc)

without proper handling, these switches cause:
- complete audio loss
- app crashes
- corrupted recordings
- poor quality capture (telephony mode)

## design evolution

### initial approach: single continuous file
**concept**: keep writing to same file through device changes
**problem**: avaudioengine locks to initial device, can't switch mid-recording
**result**: error -10851 (kAudioUnitErr_InvalidPropertyValue)

### considered approach: buffer preservation  
**concept**: cache buffers in memory, recreate engine, continue writing
**risk**: memory pressure, complexity, potential data loss

### final approach: segmented recording with independent pipelines
**concept**: separate recorder classes, segment files on device changes, stitch at end
**benefits**: 
- production-proven reliability
- independent mic/system pipelines
- perfect timeline reconstruction
- graceful error recovery

## architecture overview

```
┌─────────────────────────────────────────────────────┐
│                   ContentView                        │
│                  (UI Controller)                     │
└─────────────┬──────────────────┬────────────────────┘
              │                  │
    ┌─────────▼────────┐  ┌─────▼──────────┐
    │   MicRecorder    │  │ SystemRecorder  │
    │  (Independent)   │  │ (Independent)   │
    └─────────┬────────┘  └─────┬──────────┘
              │                  │
    ┌─────────▼────────────────▼─────────┐
    │      Segment Files + Metadata       │
    │  mic_001.wav    system_001.wav     │
    │  mic_002.wav    system_001.wav     │
    │  (device switch)  (unchanged)       │
    └─────────────┬───────────────────────┘
                  │
            ┌─────▼─────┐
            │  FFmpeg   │
            │ Stitching │
            └───────────┘
```

## key design decisions

### 1. independent pipelines
**decision**: mic and system audio operate independently
**rationale**: 
- device changes often affect only one pipeline
- reduces disruption (system continues if mic switches)
- simpler error handling

### 2. segmentation strategy
**decision**: new segment file on every device change
**rationale**:
- prevents file corruption
- enables inspection of individual segments
- allows recovery from partial failures
- simplifies timeline tracking

### 3. metadata tracking
**decision**: comprehensive metadata for each segment
```swift
struct AudioSegmentMetadata {
    startSessionTime: TimeInterval  // when in session
    endSessionTime: TimeInterval    // enables reconstruction
    deviceName: String              // user visibility
    sampleRate: Double              // quality detection
}
```
**rationale**: enables perfect timeline reconstruction even with gaps

### 4. quality guards
**decision**: block auto-switch to telephony quality (8/16khz)
**rationale**:
- protects users from degraded recordings
- telephony mode sounds terrible for transcription
- user consent required for quality downgrade

### 5. debouncing
**decision**: 1-2 second debounce on device changes
**rationale**:
- airpods connection sequence causes multiple notifications
- prevents rapid flapping
- allows hardware to settle

## implementation details

### device detection (macos)
```swift
// primary: core audio property listeners
AudioObjectPropertyAddress for kAudioHardwarePropertyDefaultInputDevice

// secondary: avaudioengine notifications  
AVAudioEngineConfigurationChange

// tertiary: avaudiosession (ios compatibility)
AVAudioSession.routeChangeNotification

// avoid: polling (wasteful)
```

### segment boundaries
```
[recording starts]
mic_1234567890_001.wav     [0.0s - 45.3s]
[airpods connected]
mic_1234567890_002.wav     [45.8s - 120.0s]  // 0.5s gap for switch
[recording ends]
```

### warmup & discard
- discard first 0.5-1.0s after each segment start
- prevents clicks and hardware settling artifacts
- applied independently per pipeline

### crossfading
- 10-50ms linear fade at segment boundaries
- prevents audible clicks
- applied during stitching phase

### thread safety
```swift
private let segmentQueue = DispatchQueue(label: "segment.queue")
// all metadata operations go through this queue
```

### error recovery
1. segment write fails → log error, start new segment
2. device unavailable → fall back to default
3. format mismatch → attempt conversion
4. catastrophic failure → save metadata for recovery

## edge cases handled

### rapid device switching
**scenario**: user rapidly plugs/unplugs headphones
**solution**: rate limiting (max 3 switches per 10 seconds)
**ux**: "devices changing rapidly - holding current mic"

### airpods telephony mode
**scenario**: airpods connect in 16khz call mode
**solution**: quality check before switching
**ux**: "airpods in call mode (low quality) [switch anyway] [keep current]"

### bluetooth disconnection
**scenario**: airpods battery dies mid-recording
**solution**: immediate fallback to built-in mic
**ux**: seamless with notification

### system audio changes
**scenario**: external display connected/disconnected
**solution**: system pipeline handles independently
**ux**: transparent to user

## testing scenarios

1. **basic switching**
   - start with built-in → connect airpods → verify switch
   - start with airpods → disconnect → verify fallback

2. **quality protection**
   - force airpods to telephony mode → verify warning
   - test quality assessment logic

3. **rapid changes**
   - rapid plug/unplug → verify debouncing
   - rate limiting → verify protection

4. **pipeline independence**
   - change mic while system continues
   - change display while mic continues

5. **error conditions**
   - disk full during segment write
   - device disappears mid-write
   - format conversion failures

## performance considerations

- segment files: ~10mb per minute (48khz mono)
- metadata: <1kb per segment
- memory: minimal (streaming to disk)
- cpu: <5% during recording
- latency: ~180ms gap during switch (acceptable)

## future enhancements

1. **predictive switching**: detect device approach (bluetooth rssi)
2. **cloud backup**: upload segments in real-time
3. **live transcription**: process segments as completed
4. **intelligent stitching**: content-aware crossfades
5. **device preferences**: remember quality choices

## conclusion

this architecture provides:
- **reliability**: production-proven segmentation approach
- **quality**: protection against degraded audio
- **flexibility**: independent pipeline management
- **recoverability**: comprehensive metadata tracking
- **user experience**: minimal disruption during switches

the design balances complexity with robustness, ensuring that critical meeting recordings are never lost due to device changes.

## references
- apple's core audio documentation
- screencapturekit best practices
- professional audio workstation designs
- our friend's production expertise

---
*document created: 2025-01-10*
*architecture version: 1.0*