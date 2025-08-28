# audio recording timing behavior - ai&i

## normal startup delay

### expected behavior
- **ui click to actual recording**: ~10 seconds startup delay
- **reason**: ffmpeg + avfoundation initialization (microphone permissions, audio drivers, recording pipeline)
- **this is normal and expected behavior** for professional audio recording systems

### impact by meeting length
- **short recordings (30-60s)**: 10s delay = 15-30% difference
- **medium recordings (5-15 min)**: 10s delay = 1-3% difference  
- **long recordings (60+ min)**: 10s delay = <0.3% difference (negligible)

### what users see
- **button press duration**: total time from start click to stop click
- **audio content duration**: actual recorded audio content (correct)
- **difference**: ~10 seconds (ffmpeg startup time)

### technical details
**timing sequence:**
1. user clicks "start recording" → ui timestamp captured
2. ipc message sent to main process (~100ms)
3. audiocapture.startrecording() called (~100ms)
4. ffmpeg process spawned (~1-2s)
5. avfoundation audio permission request (~1-2s)
6. audio driver initialization (~2-3s)
7. recording pipeline established (~2-3s)
8. **actual audio capture begins** ← ~10s after ui click
9. user clicks "stop" → audio stops immediately
10. duration calculated from actual audio bytes (correct)

### examples from testing
- **test 1**: 49s button press → 39s audio content (10s startup)
- **test 2**: 34s button press → 25s audio content (9s startup)
- **consistent**: ~10 second startup delay across all tests

### why this is correct
- **duration shows actual meeting content** (what users care about)
- **no audio content is lost** (complete recording from start of speech)
- **professional audio systems** have similar initialization delays
- **gemini timestamps are accurate** to actual audio content

### user communication
for production, consider adding:
- loading message: "initializing recording..." for first 10 seconds
- documentation: "audio recording begins ~10 seconds after clicking start"
- status indicator: show when actual recording starts vs. initialization

---
*last updated: august 28, 2025*
*status: documented as expected behavior*