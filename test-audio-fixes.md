# audio recording fixes test checklist

## test scenarios for comprehensive fix

### 1. recording start delay (fixed)
- [ ] press record button
- [ ] verify sidebar timer starts immediately (not 3-6s later)
- [ ] speak immediately after pressing record
- [ ] verify first words are captured in transcript

### 2. airpods removal test (fixed)
- [ ] start recording with airpods connected
- [ ] record 30 seconds with airpods
- [ ] remove airpods mid-recording
- [ ] continue speaking for 30 seconds
- [ ] verify post-airpods audio is captured

### 3. device switching reliability (fixed)
- [ ] monitor console for device polling messages (every 2 seconds)
- [ ] check for "device changed" messages when airpods removed
- [ ] verify automatic microphone recovery attempts
- [ ] confirm recording continues after device switch

### 4. segment capture verification
- [ ] check console for mic segment messages with timestamps
- [ ] verify segments are being captured continuously
- [ ] monitor segment sizes and timing

### 5. memory and cleanup
- [ ] record for 2+ minutes
- [ ] stop recording
- [ ] verify cleanup messages in console
- [ ] check that streams are properly stopped

## expected console output patterns

### successful start:
```
✅ AudioLoopbackRendererFixed initialized
🎙️ Starting dual-stream recording...
⚡ Fast-starting audio capture...
✅ Microphone started: AirPods
✅ System audio started
✅ Recording started in XXXms
👂 Device polling started (2s intervals)
```

### successful device switch:
```
🔄 Device changed: AirPods → MacBook Pro Microphone
🔄 Handling device disconnect (attempt 1)...
🎯 Getting new microphone...
✅ New microphone connected: MacBook Pro Microphone
✅ Microphone recording resumed
```

### segment capture:
```
🎤 Mic segment 1: XXXX bytes at X.Xs
🔊 System segment 1: XXXX bytes
```

## key improvements in fixed version

1. **immediate recording start**: no more 3-6 second delay
2. **poll-based monitoring**: checks every 2 seconds for device changes
3. **automatic recovery**: attempts to reconnect when device disconnected
4. **device switch counting**: tracks number of switches for diagnostics
5. **actual recording time tracking**: accurate timing from when recording actually starts
6. **robust error handling**: continues with available streams if one fails

## verification steps

1. run `npm start` to launch the app
2. open developer console to monitor logs
3. perform each test scenario above
4. verify all post-airpods audio is captured
5. confirm no initial audio loss
6. check final transcript includes all segments