# programmatic aggregate devices implementation plan

**milestone**: 3.3.5 - native mixed audio capture  
**goal**: hardware-level mixed audio (microphone + system) using macos core audio apis  
**approach**: thorough, incremental development with validation at each step  
**timeline**: 10-12 days total

## implementation philosophy

**thorough over fast**: validate every assumption, test each integration point  
**incremental building**: simple proof-of-concept → full feature → electron integration  
**failure planning**: handle edge cases and provide fallback strategies  
**reference code awareness**: use provided swift examples as guides, not gospel  

---

## phase 3.3.5(a): core audio foundation (4-5 days)

**objective**: validate core audio apis work as expected, build reliable device management

### step 1: research & validate apis (1 day)
**what we're doing**: understanding the actual capabilities and limitations

**tasks**:
- research `AudioHardwareCreateAggregateDevice()` official documentation
- find apple developer examples of aggregate device creation
- understand required parameters, data structures, error codes
- research device discovery apis (`AudioObjectGetPropertyData`, device enumeration)
- identify potential permission/security restrictions

**validation questions**:
- does `AudioHardwareCreateAggregateDevice()` actually exist and work on current macos?
- what are the minimum required parameters?
- what permissions does aggregate device creation require?
- are there restrictions on temporary/private devices?

**success criteria**:
- comprehensive understanding of core audio device management apis
- list of required frameworks and headers
- understanding of error scenarios and recovery strategies

### step 2: minimal proof-of-concept (1-2 days)
**what we're doing**: create simplest possible working example

**implementation approach**:
```swift
// minimal-device-test.swift - just create and destroy
import CoreAudio
import AudioToolbox

// Step 1: Just enumerate existing devices
print("=== existing audio devices ===")
// implement device discovery

// Step 2: Create minimal aggregate device
print("=== creating aggregate device ===")  
let result = AudioHardwareCreateAggregateDevice(/* minimal config */)

// Step 3: Verify device exists
print("=== verifying device creation ===")
// check if device appears in system

// Step 4: Clean destroy
print("=== destroying device ===")
AudioHardwareDestroyAggregateDevice(deviceID)
```

**testing approach**:
- compile and run swift program manually
- open audio midi setup → verify device appears/disappears
- test multiple create/destroy cycles for memory leaks
- test failure scenarios (invalid parameters, insufficient permissions)

**success criteria**:
- swift program compiles without errors
- device creation succeeds and appears in audio midi setup
- device destruction removes device cleanly
- no memory leaks or system pollution after multiple cycles

### step 3: incremental feature building (2 days)  
**what we're doing**: add each required feature and test individually

**feature 1: device discovery (0.5 days)**
```swift
// find current default output device (speakers/headphones)
func getCurrentDefaultOutput() -> AudioDeviceID
// find built-in microphone  
func getBuiltInMicrophone() -> AudioDeviceID
```

**feature 2: proper aggregate creation (0.5 days)**
```swift  
// create aggregate with specific source devices
func createAggregateFromDevices(speaker: AudioDeviceID, mic: AudioDeviceID) -> AudioDeviceID
```

**feature 3: system integration (0.5 days)**
```swift
// temporarily set aggregate as system default
func setSystemDefault(deviceID: AudioDeviceID)
// restore original default  
func restoreOriginalDefault()
```

**feature 4: comprehensive error handling (0.5 days)**
- handle each possible failure mode
- provide meaningful error messages
- ensure partial failures don't leave system in bad state

**testing for each feature**:
- test in isolation before combining
- test edge cases (no microphone, bluetooth devices, etc.)
- verify cleanup works even after failures

**success criteria**:
- can discover current audio devices reliably
- can create aggregate device from discovered devices
- can switch system default temporarily and restore
- all failure modes handled gracefully

---

## phase 3.3.5(b): electron bridge architecture (3-4 days)

**objective**: reliable communication between electron and swift, handle all failure modes

### step 1: command line interface (1 day)
**what we're doing**: make swift code callable from electron via spawn

**implementation approach**:
```swift
// main.swift - command line interface
switch CommandLine.arguments[1] {
case "create":
    // create device, return json with device info
case "destroy":  
    // destroy device, return success/failure
case "list":
    // list available devices for debugging
default:
    // help text
}
```

**json response format**:
```json
{
    "success": true|false,
    "deviceID": 123,
    "deviceUID": "com.aiandi.device.uuid", 
    "originalDevice": 456,
    "error": "error message if failed"
}
```

**testing approach**:
- build swift binary: `swiftc -o AudioManager *.swift -framework CoreAudio`
- test command line: `./AudioManager create`
- verify json output parses correctly
- test all command variations and error scenarios

**success criteria**:
- swift binary builds successfully
- all commands work from terminal
- json output is valid and parseable
- error scenarios return proper error messages

### step 2: electron integration (1-2 days)
**what we're doing**: ipc handlers in main process, spawn management

**implementation approach**:
```javascript
// main-process-audio.js
class AudioManager {
    async createDevice() {
        return new Promise((resolve, reject) => {
            const process = spawn('./path/to/AudioManager', ['create']);
            // handle stdout, stderr, exit codes
        });
    }
}

// ipc handlers
ipcMain.handle('audio:create-device', async () => {
    // call AudioManager.createDevice()
});
```

**testing approach**:
- test ipc communication: renderer → main → swift → main → renderer
- test process lifecycle: spawn, communicate, cleanup  
- test error propagation at each step
- test concurrent requests and cleanup

**success criteria**:
- electron can spawn swift binary reliably
- ipc communication works bidirectionally  
- process cleanup happens on all exit scenarios
- error messages propagate to ui correctly

### step 3: error recovery & fallback (1 day)
**what we're doing**: handle swift binary failures gracefully

**failure scenarios to handle**:
- swift binary not found or won't start
- device creation fails (permissions, conflicts)
- swift binary crashes during operation
- electron app force quit during device creation

**fallback strategies**:
- detect failure and fall back to current dual-stream approach
- provide clear user messaging about what went wrong
- automatic retry with exponential backoff for transient failures

**success criteria**:
- app continues working even if swift integration fails
- users get helpful error messages, not technical crashes
- no orphaned devices left behind after failures

---

## phase 3.3.5(c): audio capture integration (2-3 days)

**objective**: replace existing mixed audio capture with aggregate device approach

### step 1: device targeting validation (1 day)
**what we're doing**: verify electron can capture from our aggregate device

**testing approach**:
```javascript
// test-device-capture.js
const deviceInfo = await createAggregateDevice();

// can getUserMedia target our device?
const stream = await navigator.mediaDevices.getUserMedia({
    audio: { deviceId: { exact: deviceInfo.deviceUID } }
});

// does stream actually contain mixed audio?
// record short test, analyze with audio software
```

**validation questions**:
- can `getUserMedia()` target programmatically created devices?
- does aggregate device actually mix microphone + system audio?
- is audio quality acceptable compared to current approach?
- are there latency or performance implications?

**success criteria**:
- can reliably capture from aggregate device
- captured audio contains both microphone and system sources
- audio quality meets or exceeds current implementation
- no significant latency or performance issues

### step 2: incremental integration (1 day)
**what we're doing**: replace `mixedAudioCapture.js` piece by piece

**approach**:
```javascript
// new-mixed-capture.js  
class AggregateAudioCapture {
    async startRecording(sessionId) {
        // Step 1: create aggregate device
        // Step 2: start capture from device
        // Step 3: handle mediarecorder setup
    }
    
    async stopRecording() {
        // Step 1: stop capture
        // Step 2: cleanup aggregate device  
    }
}
```

**testing at each step**:
- compare memory usage with current implementation
- verify recording start/stop cycles work
- test session management and file output
- ensure ui synchronization still works

**success criteria**:
- recording workflow works end-to-end
- single mixed audio file output
- memory usage comparable to current implementation
- ui shows proper recording states

### step 3: edge case testing (1 day)
**what we're doing**: test scenarios that could break the system

**edge cases to test**:
- no microphone connected
- no speakers/headphones connected  
- user changes audio devices during recording
- bluetooth devices connecting/disconnecting
- multiple simultaneous recordings
- app force quit during recording
- permission denied scenarios

**success criteria**:
- graceful handling of all edge cases
- clear error messages for user-fixable issues
- automatic fallback to dual-stream when aggregate fails
- no system instability or orphaned devices

---

## phase 3.3.5(d): user experience polish (2-3 days)

**objective**: seamless user experience with proper error handling and feedback

### key user experience requirements

**recording startup flow**:
```
user clicks record → 
"setting up audio..." (2-3 seconds) → 
recording starts seamlessly →
single clean recording interface
```

**error handling**:
- clear, actionable error messages
- automatic fallback without user intervention when possible
- recovery suggestions for user-fixable issues

**device management**:
- invisible to user - no devices appear in sound preferences
- automatic cleanup - no leftover devices after app close
- proper restoration of original audio settings

### implementation tasks

1. **loading states and progress feedback** (0.5 days)
2. **error message design and fallback logic** (1 day)  
3. **permission handling and user guidance** (0.5 days)
4. **performance optimization** (minimize device creation time) (0.5 days)
5. **comprehensive cleanup testing** (0.5 days)

---

## phase 3.3.5(e): testing and validation (2-3 days)

**objective**: comprehensive testing across scenarios, performance validation

### testing scenarios

**basic functionality**:
- microphone + system audio recording
- device switching during recording
- long recordings (30+ minutes)
- multiple recording sessions

**edge cases**:
- various audio device configurations  
- permission denied scenarios
- swift binary failures
- network issues during recording
- app crashes and recovery

**performance testing**:
- memory usage comparison with current system
- cpu usage during device creation and recording
- audio quality analysis and comparison
- recording startup time measurement

### validation criteria

**content completeness**: 100% of audio captured (no loss like ffmpeg had)  
**temporal alignment**: perfect sync between mic and system audio  
**audio quality**: clear, intelligible mixed audio output  
**system stability**: no crashes, memory leaks, or orphaned devices  
**user experience**: smooth workflow, clear error messages  

---

## success metrics

**technical success**:
- ✅ single mixed audio file contains both sources perfectly synchronized  
- ✅ zero temporal alignment issues (eliminate the core problem)
- ✅ hardware-level mixing quality (better than software mixing)
- ✅ seamless user experience (no manual setup required)
- ✅ reliable cleanup (no system pollution)

**strategic success**:
- ✅ foundation for advanced speaker diarization with mixed audio
- ✅ competitive advantage through superior audio capture
- ✅ eliminated dual-file complexity from codebase (~500 lines removed)
- ✅ scalable architecture for future audio features

## risk mitigation

**technical risks**:
- **core audio apis don't work as expected**: extensive research and testing in phase a
- **electron integration issues**: incremental testing and fallback strategies  
- **macos permission restrictions**: research and user guidance

**timeline risks**:
- **swift learning curve**: focus on working solution first, optimize later
- **unexpected api limitations**: build fallback to current dual-stream approach

**user experience risks**:
- **device creation takes too long**: async ui with proper loading states
- **failures are confusing**: clear error messages and automatic fallback

## commitment and confidence

**can we guarantee this will work?**  
yes, with appropriate caveats:

**high confidence**:
- core audio aggregate devices are proven technology used by professional apps
- the fundamental approach (hardware-level mixing) is sound
- macos provides the apis we need

**medium confidence**:  
- electron integration complexity manageable with thorough testing
- swift development timeline realistic with incremental approach

**mitigation for unknowns**:
- fallback to current dual-stream approach if aggregate devices fail
- incremental development reveals issues early when they're easier to fix
- comprehensive testing prevents surprises in production

this approach gives us the native mixed audio capture we need while maintaining engineering rigor and user experience quality.