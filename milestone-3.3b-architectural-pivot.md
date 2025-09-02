# milestone 3.3(b): architectural pivot - core audio with file-based or streaming options

## executive summary
architectural transformation to use native core audio apis for pristine audio capture, with option for either file-based processing (simpler, same cost) or real-time streaming (complex, 28x cost). we build this together - i write the c++, you test and iterate.

## justification for architectural pivot

### why consider this if 3.3(a) doesn't achieve 85% accuracy
1. **source-level separation**: core audio captures before any mixing occurs
2. **lossless quality**: raw pcm instead of compressed webm
3. **os-level integration**: direct access to audio hardware
4. **proven approach**: granola and other successful apps use this

### what core audio solves that current approach cannot
- **true dual-stream isolation**: mic and system never mix at source
- **hardware-level timestamps**: microsecond precision synchronization
- **zero compression artifacts**: raw pcm data throughout
- **professional audio quality**: 48khz/24-bit if needed

## two implementation options

### option a: core audio + file-based (recommended to start)
```
Core Audio → RAW PCM/WAV files → Batch transcription → Summary
```
- **same workflow** as current system
- **same costs** ($0.054/hour)
- **better quality** (uncompressed, perfectly separated)
- **development time**: 5-7 days

### option b: core audio + streaming (if real-time needed)
```
Core Audio → Stream to Deepgram/AssemblyAI → Real-time transcript
```
- **real-time feedback** during recording
- **28x more expensive** ($1.52/hour)
- **more complex** (websocket management)
- **development time**: 10-12 days

## collaborative development approach

### we build this together
**your role:**
- test recordings with different scenarios
- provide feedback on quality
- identify edge cases
- normal git workflow

**my role:**
- write all c++ code
- create node.js bindings
- handle compilation setup
- debug native issues

**together:**
- design the javascript api
- test with real recordings
- iterate on improvements
- package for distribution

### no scary requirements
- **no xcode ide needed** (just command line tools)
- **no c++ learning required** (i write it all)
- **no consultant needed** (we are the team)
- **same electron packaging** (users never know)

## implementation phases

### phase 1: core audio capture module (3-4 days)

#### simple native module
```cpp
// src/native/CoreAudioCapture.mm - i write this
class CoreAudioCapture {
public:
    void StartCapture() {
        // capture mic and system audio separately
        StartMicrophoneCapture();
        StartSystemAudioCapture();
    }
    
    void StopCapture() {
        // return two audio buffers or file paths
    }
};
```

#### javascript wrapper (we write together)
```javascript
// src/audio/coreAudioBridge.js
const native = require('../native/build/Release/core-audio.node');

class CoreAudioBridge {
    async startRecording() {
        return native.startCapture();
    }
    
    async stopRecording() {
        const { micBuffer, sysBuffer } = native.stopCapture();
        
        // option a: save as files
        if (USE_FILE_MODE) {
            return this.saveAsFiles(micBuffer, sysBuffer);
        }
        
        // option b: stream
        if (USE_STREAMING) {
            return this.streamToServices(micBuffer, sysBuffer);
        }
    }
}
```

### phase 2a: file-based processing (2 days)

#### save as high-quality files
```javascript
async saveAsFiles(micBuffer, sysBuffer) {
    // save as wav (uncompressed) or high-bitrate webm
    const micPath = await this.saveWAV(micBuffer, 'microphone.wav');
    const sysPath = await this.saveWAV(sysBuffer, 'system.wav');
    
    // or create single stereo file
    const stereoPath = await this.createStereoWAV(micBuffer, sysBuffer);
    
    return { micPath, sysPath, stereoPath };
}
```

#### process with existing transcription
```javascript
// use our existing gemini/deepgram code
const transcript = await processAudioEndToEnd(stereoPath);
```

### phase 2b: streaming implementation (optional, 3-4 days)

#### streaming setup (if needed later)
```javascript
class StreamingProcessor {
    constructor() {
        this.deepgram = new DeepgramStreaming();
        this.bufferSize = 8192; // samples
    }
    
    streamToServices(micBuffer, sysBuffer) {
        // send audio chunks as they arrive
        coreAudio.on('audioData', (chunk) => {
            this.deepgram.send(chunk);
        });
    }
}
```

## technical implementation details

### build configuration (automatic)
```json
// binding.gyp - i set this up once
{
  "targets": [{
    "target_name": "core-audio-capture",
    "sources": ["src/native/CoreAudioCapture.mm"],
    "link_settings": {
      "libraries": [
        "-framework CoreAudio",
        "-framework AudioToolbox"
      ]
    }
  }]
}
```

### package.json changes (minimal)
```json
{
  "scripts": {
    "postinstall": "node-gyp rebuild",  // automatic compilation
    "build": "electron-builder"         // same as now
  }
}
```

### user experience (identical)
```bash
# users just run:
npm install  # native module compiles automatically
npm start    # app runs normally
```

## realistic timeline

### week 1: core implementation
- day 1-2: i write core audio capture module
- day 3: you test basic audio capture
- day 4: i add stereo file creation
- day 5: you test with real scenarios

### week 2: integration & polish
- day 1-2: integrate with existing transcription
- day 3: test quality improvements
- day 4-5: fix edge cases and optimize

**total: 7-10 days for file-based approach**

## risk assessment

### technical risks
1. **native module complexity** ⚠️ medium
   - mitigation: i handle all c++ code
   - fallback: keep current system

2. **audio device compatibility** ⚠️ low
   - mitigation: test with various devices
   - fallback: use current system for unsupported devices

3. **compilation issues** ✅ low
   - mitigation: pre-built binaries for distribution
   - fallback: compile on user's machine

### business risks
1. **development time** ✅ low
   - 7-10 days is manageable
   - can ship improvements incrementally

2. **streaming costs** (only if option b)
   - 28x increase needs user acceptance
   - mitigation: offer as premium feature

## comparison with 3.3(a)

### when to choose 3.3(a) (improvements):
- can achieve 85%+ accuracy
- need quick results (2-3 days)
- want to minimize risk
- cost sensitive

### when to choose 3.3(b) (architectural pivot):
- 3.3(a) achieves <80% accuracy
- need professional audio quality
- want streaming capability option
- willing to invest 7-10 days

## immediate next steps

### if choosing 3.3(b):
1. **today**: prototype basic core audio capture
2. **tomorrow**: test audio quality improvement
3. **day 3**: decide on file vs streaming
4. **day 4-10**: implement chosen approach

### recommended approach:
1. **try 3.3(a) first** (2-3 days)
2. **measure accuracy improvement**
3. **if <85% accuracy, start 3.3(b)**
4. **begin with file-based, add streaming later if needed**

## conclusion

core audio pivot offers:
- **pristine audio quality** at source
- **true stream separation** before mixing
- **flexibility** for file-based or streaming
- **collaborative development** - we build together

investment required:
- **7-10 days** for file-based (not months)
- **no new skills** for you to learn
- **same packaging** and distribution
- **optional streaming** can be added later

**recommendation**: implement 3.3(a) improvements first, keep 3.3(b) as proven backup plan if needed.