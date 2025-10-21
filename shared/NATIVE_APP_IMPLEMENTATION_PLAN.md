# ai&i native mac app implementation plan

**vision**: professional-grade mixed audio transcription app with magical user experience  
**timeline**: 7-10 days for complete rebuild from electron to native  
**approach**: leverage all accumulated knowledge, build incrementally with validation  
**target**: superior foundation for 1000+ users with unlimited future flexibility

---

## project overview

### what we're building
native mac app using swiftui + core audio that captures perfectly mixed audio (microphone + system) and provides intelligent transcription with human-like summaries.

### why native approach wins
- **hardware-level mixed audio**: direct core audio access, no bridge complexity
- **native permissions**: one-time setup vs electron's weekly prompts  
- **superior performance**: no electron overhead, true mac app responsiveness
- **unlimited flexibility**: foundation for advanced features (real-time, ai processing)
- **professional reliability**: proven scaling characteristics for serious audio software

### leveraging our accumulated knowledge
- ✅ **transcription expertise**: gemini 2.5 flash integration patterns proven
- ✅ **ui/ux insights**: sidebar → main → tabbed content flow works well
- ✅ **edge case handling**: device switching, permission errors, network failures
- ✅ **user needs understanding**: recording workflow, transcript display, meeting management
- ✅ **performance optimization**: memory efficiency, stream-to-disk approaches

---

## version roadmap

### v0.1: core foundation (complete)
**goal**: performance-first foundation with real-time mixed audio capture

**critical architectural insight — electron dual-stream vs native real-time mixing**:
- **electron dual-stream failure**: two separate files (mic.webm, system.webm) with temporal alignment issues, 33-50% content loss in transcription
- **native real-time mixing**: single synchronized stream mixed during recording, perfect temporal alignment, transcription-ready output
- **key difference**: mixing happens *during* recording (not post-processing), exactly what Zoom/Teams produce

**what shipped**:
- ✅ SwiftUI shell with admin performance dashboard (cmd+shift+i)
- ✅ One-click permission flow (no surprise dialogs)
- ✅ Hot-standby audio architecture with warm engine preparation
- ✅ Baseline telemetry for launch, start, and stop timings
- ✅ Initial mic/system capture with metadata journaling

**validation**:
- [x] App startup < 1 second on release builds
- [x] Mixed audio file contains synchronized mic + system audio
- [x] No temporal drift across 30-minute recordings

### v0.2: audio stability & pipeline reliability (in progress)
**goal**: bulletproof dual-pipeline capture that survives AirPods churn, telephony fallback, and long sessions without user intervention.

**scope**:
- Dual warm pipelines with recording session coordinator, shared switch lock, and lifecycle observers
- Stable output routing pipeline that preserves the user's preferred device while fallback engages
- Telemetry wiring for mic/system switches, pinned windows, readiness retries, and segment diagnostics
- Automated end-to-end validation (device-toggle simulation + mixing/transcription trace)
- Launch/start/stop latency measurement and post-session diagnostics capture

**success criteria**:
- Zero audio gaps during repeated AirPods connect/disconnect cycles (>5 switches in 10 minutes)
- Built-in mic fallback engages without muting user playback or resetting speaker choice
- PerformanceMonitor surfaces route changes, executed switches, warm prep attempts, and lossiness flags per session
- End-to-end validation script passes (timeline coverage, segment stitching, transcription trigger)

**test cases**:
- [ ] 6-minute session with AirPods toggled every 45 seconds → no lost transcription
- [ ] Telephony fallback + recovery restores original output route within 1s
- [ ] Warm pipeline resume after app background/foreground without manual restart
- [ ] Performance dashboard shows accurate route/switch counters after each run

### v0.3: transcription & summaries (next)
**goal**: rock-solid transcription services with canonical storage plus differentiated Sally Rooney-style summaries.

**scope**:
- MP3 gating with `ffmpeg` availability check + retry/backoff
- Canonical transcript store (`session_<id>_transcripts.json`) with best-service selection
- Prompt upgrades (multilingual hints, AirPods/system context, speaker personas)
- Confidence scoring rendered in UI + warning badges for <0.7 segments
- Enriched per-service status (queued/running/success/failure + log IDs)
- Sally Rooney summary service ported from Electron with cost tracking and sectioned output

**success criteria**:
- All three services run in parallel and log success/failure states deterministically
- Transcript viewer persists best transcript choice and reloads instantly
- Summaries available within 90s of recording stop with key points/action items/emotional tone
- Confidence metadata drives UI affordances (opacity + warning icons)

**test cases**:
- [ ] Upload fallback triggers on missing `ffmpeg`, user sees actionable error
- [ ] Switching “best” transcript updates stored metadata and UI persistently
- [ ] Summary generation handles multilingual session with AirPods + system context hints
- [ ] Confidence overlay toggles when segments dip below threshold

### v0.4: interface rebuild & architecture separation
**goal**: redesign the app shell with clean separation between data/services and SwiftUI presentation so UI refactors never break capture logic.

**scope**:
- Module separation: `Audio`, `Transcription`, `Data`, `UI` packages with explicit dependencies
- New SwiftUI layout (sidebar → detail → tabs) with design-system tokens and Japanese palette alignment
- Fully wired controls only (share/export/correct hidden until functional)
- Keyboard shortcuts, accessibility, and multi-window readiness
- View models and services decoupled for preview-driven UI development

**success criteria**:
- UI follows Apple HIG; window + layout state persists between launches
- Logic/services compile without the UI module (command-line/automation use cases)
- SwiftUI previews run without touching CoreAudio/ScreenCaptureKit

**test cases**:
- [ ] Sidebar scroll + search fluid with 100+ recordings
- [ ] VoiceOver navigation covers recording controls + transcript cells
- [ ] Hot reload of views via previews requires no hardware stubs
- [ ] UI-only refactor leaves audio/transcription unit tests untouched

### v0.5: everyday workflow essentials
**goal**: add the productivity features that make daily use delightful.

**scope**:
- Share/export (Markdown, PDF, text, deep links)
- Global search + filters (date, participants, keywords)
- Foldering/collections and pinning important meetings
- Onboarding checklist, contextual tips, and settings surface (audio defaults, transcription preferences)
- Notifications / reminders for recording start + summary ready
- Polished micro-interactions (hover states, subtle animations, haptics where available)

**success criteria**:
- Users can export/share within two clicks from transcript view
- Search returns results <100ms with highlighted matches
- Settings persist and sync across launches; onboarding completion stored per user

**test cases**:
- [ ] Export formats match design templates across 60-minute session
- [ ] Notification fires when summary ready (and respects Do Not Disturb)
- [ ] Folder reordering + drag/drop stable over 200 recordings

### v0.6: backend, beta rollout, reliability hardening
**goal**: stand up service infrastructure, ship the beta, and lock in performance/reliability for large-scale usage.

**scope**:
- Backend services (auth, storage, sync) + secret management
- Beta distribution tooling, crash reporting, analytics
- Automated regression suite + nightly pipeline validation
- Performance profiling (memory, CPU, IO) over multi-hour sessions
- Reliability dashboards + alerting for device switching, transcription queue health

**success criteria**:
- Beta builds delivered via TestFlight/alternative with automatic update checks
- Backend handles concurrent sessions with secure storage + retention policies
- Regression suite covers record → switch devices → mix → transcribe → summarize → export
- Performance envelopes documented for multi-hour meetings on Intel + Apple Silicon

**test cases**:
- [ ] 60+ minute recordings with backend sync complete without gaps or crashes
- [ ] Simulated backend outage surfaces graceful retry UI within 5s
- [ ] Analytics + crash reporting capture 100% of beta incidents with actionable context

---

## technical architecture

### project structure
```
AI-and-I/
├── AI-and-I.xcodeproj
├── Sources/
│   ├── AI_and_IApp.swift                # Main app entry point
│   ├── Views/
│   │   ├── ContentView.swift            # Root container view
│   │   ├── SidebarView.swift            # Recordings list
│   │   ├── MainView.swift               # Recording interface  
│   │   ├── TranscriptView.swift         # Tabbed content display
│   │   └── SettingsView.swift           # Preferences pane
│   ├── Audio/
│   │   ├── CoreAudioManager.swift       # Mixed audio capture
│   │   ├── AudioDevice.swift            # Device enumeration/selection
│   │   └── AudioProcessor.swift         # Stream processing
│   ├── Transcription/
│   │   ├── GeminiService.swift          # API integration
│   │   ├── TranscriptionModels.swift    # Data structures
│   │   └── CostTracker.swift            # Usage monitoring
│   ├── Data/
│   │   ├── Recording.swift              # Core data model
│   │   ├── DataManager.swift            # Persistence layer
│   │   └── FileManager+Extensions.swift # File operations
│   └── Utilities/
│       ├── Extensions.swift             # Swift extensions
│       ├── Constants.swift              # App constants
│       └── Logger.swift                 # Logging system
├── Resources/
│   ├── Assets.xcassets                  # Images, icons, colors
│   ├── Info.plist                       # App configuration
│   └── Localizable.strings              # Internationalization
└── Tests/
    ├── AudioTests/                      # Core audio testing
    ├── TranscriptionTests/              # API integration testing
    └── UITests/                         # User interface testing
```

### core audio implementation approach (phase 2)
```swift
// AudioManager.swift - Real-time mixed audio with AVAudioEngine + ScreenCaptureKit
class AudioManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    
    private var audioEngine: AVAudioEngine?  // Lazy init after permissions
    private var audioFile: AVAudioFile?
    private var systemAudioStream: SCStream?
    
    // Phase 2: Proper initialization order
    func startRecording() async throws -> URL {
        // 1. Ensure permissions first (critical - never touch inputNode before this)
        guard await requestMicrophonePermission() else {
            throw AudioError.microphonePermissionDenied
        }
        
        // 2. Now safe to create and configure engine
        audioEngine = AVAudioEngine()
        let mixerNode = audioEngine!.mainMixerNode
        
        // 3. Connect microphone (safe after permission)
        let micInput = audioEngine!.inputNode
        audioEngine!.connect(micInput, to: mixerNode, format: nil)
        
        // 4. Setup ScreenCaptureKit for system audio
        let systemAudioNode = AVAudioPlayerNode()
        audioEngine!.attach(systemAudioNode)
        audioEngine!.connect(systemAudioNode, to: mixerNode, format: nil)
        
        // Start system audio capture
        systemAudioStream = try await startSystemAudioCapture { sampleBuffer in
            // Convert CMSampleBuffer to PCM and schedule on systemAudioNode
            if let pcmBuffer = self.convertToPCM(sampleBuffer) {
                systemAudioNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
            }
        }
        
        // 5. Record mixed output to single file
        let fileURL = getRecordingURL()
        audioFile = try AVAudioFile(forWriting: fileURL, 
                                   settings: micInput.outputFormat(forBus: 0).settings)
        
        // Install tap on mixer for recording
        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, time in
            try? self.audioFile?.write(from: buffer)
        }
        
        // Start everything
        systemAudioNode.play()
        try audioEngine!.start()
        isRecording = true
        
        return fileURL
    }
    
    // Critical: Handle format conversion
    private func convertToPCM(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Convert ScreenCaptureKit's CMSampleBuffer to AVAudioPCMBuffer
        // This is the key technical challenge in Phase 2
    }
}
```

### swiftui architecture patterns
```swift
// ContentView.swift - MVVM with Combine
struct ContentView: View {
    @StateObject private var audioManager = CoreAudioManager()
    @StateObject private var dataManager = DataManager()
    @State private var selectedRecording: Recording?
    
    var body: some View {
        NavigationSplitView {
            SidebarView(recordings: dataManager.recordings,
                       selection: $selectedRecording)
        } detail: {
            if let recording = selectedRecording {
                TranscriptView(recording: recording)
            } else {
                MainView(audioManager: audioManager)
            }
        }
        .onAppear {
            dataManager.loadRecordings()
        }
    }
}
```

### transcription service integration
```swift
// GeminiService.swift - Reuse proven patterns from electron
class GeminiService: ObservableObject {
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    
    private let costTracker = CostTracker()
    
    func transcribeAudio(_ audioURL: URL) async throws -> TranscriptionResult {
        isProcessing = true
        defer { isProcessing = false }
        
        // Convert audio to format expected by Gemini
        let audioData = try await convertAudioForAPI(audioURL)
        
        // Use exact same API patterns from electron version
        let request = GeminiRequest(
            model: "gemini-2.5-flash",
            prompt: mixedAudioTranscriptionPrompt,
            audioData: audioData
        )
        
        let response = try await apiClient.send(request)
        
        // Track costs exactly like electron version
        costTracker.recordUsage(
            inputTokens: response.usage.inputTokens,
            outputTokens: response.usage.outputTokens,
            cost: response.cost
        )
        
        return TranscriptionResult(
            transcript: response.transcript,
            summary: response.summary,
            cost: response.cost,
            processingTime: response.processingTime
        )
    }
}
```

---

## user experience design principles

### native mac app excellence
- **follow human interface guidelines**: consistent with system apps
- **instant responsiveness**: all ui interactions feel immediate
- **intuitive navigation**: obvious how to accomplish tasks
- **beautiful typography**: proper font hierarchy and spacing
- **subtle animations**: enhance understanding without distraction

### recording workflow optimization
```
user opens app → 
sees clean interface with large record button →
clicks record → 
immediate visual feedback (recording dot, timer) →
system audio + mic captured seamlessly →
clicks stop → 
"processing..." with progress indicator →
transcript appears automatically →
summary available in adjacent tab
```

### information architecture
```
sidebar: chronological list of recordings
├── today
│   ├── "meeting with sarah" (3:45pm)
│   └── "brainstorming call" (10:30am)  
├── yesterday
│   └── "client presentation" (2:15pm)
└── this week
    ├── "team standup" (monday)
    └── "project review" (wednesday)

main area: 
├── recording interface (when no selection)
│   ├── large record/stop button
│   ├── recording timer and status
│   └── quick settings (quality, etc)
└── transcript display (when recording selected)
    ├── transcript tab: clean text with speaker labels
    ├── summary tab: key points and insights
    └── export options: copy, save, share
```

### visual design principles
- **minimal chrome**: focus on content, not interface
- **generous whitespace**: comfortable reading experience
- **subtle depth**: appropriate use of shadows and layers
- **consistent iconography**: system icons where possible
- **accessible colors**: proper contrast ratios throughout

---

## testing strategy

### unit testing approach
- **audio functionality**: mock core audio apis for reliable testing
- **transcription service**: test with known audio samples and expected outputs
- **data management**: validate persistence, migration, and recovery
- **cost tracking**: ensure accurate calculations across all scenarios

### integration testing scenarios
- **end-to-end workflow**: record → transcribe → display → export
- **error recovery**: network failures, api errors, permission denials
- **performance testing**: long recordings, many simultaneous operations
- **device compatibility**: different audio setups, bluetooth devices

### user experience validation
- **usability testing**: can new users complete core tasks intuitively?
- **accessibility testing**: voiceover navigation, keyboard shortcuts, high contrast
- **performance perception**: does app feel fast even during heavy processing?
- **edge case handling**: graceful degradation when things go wrong

### automated testing pipeline
```swift
// Example test structure
class AudioManagerTests: XCTestCase {
    func testMixedAudioRecording() async throws {
        let audioManager = CoreAudioManager()
        
        // Test recording starts successfully
        let audioURL = try await audioManager.startMixedRecording()
        XCTAssertTrue(audioManager.isRecording)
        
        // Test recording produces valid audio file
        let audioFile = try AVAudioFile(forReading: audioURL)
        XCTAssertGreaterThan(audioFile.length, 0)
        
        // Test recording stops cleanly
        await audioManager.stopRecording()
        XCTAssertFalse(audioManager.isRecording)
    }
}
```

---

## risk mitigation & contingency plans

### technical risks
**core audio complexity**: 
- mitigation: start with simplest working implementation, iterate complexity
- fallback: use system's built-in aggregate device creation temporarily

**swiftui learning curve**:
- mitigation: focus on standard patterns, avoid custom complex layouts initially  
- fallback: use uikit components for complex ui if needed

**transcription api reliability**:
- mitigation: implement robust retry logic and offline queue
- fallback: support multiple transcription services (gemini, deepgram, assemblyai)

### timeline risks
**feature creep temptation**:
- mitigation: strict milestone scope, defer nice-to-haves until post-mvp
- measurement: only features essential for core workflow

**unknown platform quirks**:
- mitigation: research common gotchas, budget 20% extra time
- recovery: daily progress reviews to catch issues early

### user experience risks
**migration from electron version**:
- mitigation: export/import functionality for user data
- support: clear migration guide and transition period

**performance expectations**:  
- mitigation: establish performance benchmarks early
- validation: continuous profiling during development

---

## success metrics & validation

### technical excellence benchmarks
- **app startup**: < 3 seconds from dock click to usable interface
- **recording start**: < 2 seconds from button click to active recording
- **memory efficiency**: < 50mb during 60+ minute recordings
- **transcription speed**: < 30 seconds processing for 5-minute audio
- **ui responsiveness**: all interactions complete within 100ms

### user experience quality gates
- **intuitive workflow**: new users complete first recording without help
- **professional feel**: indistinguishable from high-end mac apps
- **reliability**: zero crashes during normal usage patterns
- **accessibility**: full voiceover and keyboard navigation support
- **error recovery**: graceful handling of all failure scenarios

### competitive positioning validation
- **audio quality**: superior to zoom/teams built-in transcription
- **user experience**: simpler workflow than otter.ai or granola
- **performance**: faster processing than file-upload based competitors
- **reliability**: more dependable than electron-based audio tools
- **cost efficiency**: transparent pricing vs hidden usage-based models

---

## development workflow & collaboration

### daily development rhythm
1. **morning planning**: review previous day progress, plan day's work
2. **focused implementation**: 3-4 hour deep work blocks  
3. **afternoon testing**: validate new functionality, run test suites
4. **evening documentation**: update project state, commit with clear messages
5. **user feedback integration**: incorporate testing insights into next day

### milestone completion checklist
- [ ] all planned features implemented and working
- [ ] comprehensive test suite passing
- [ ] user experience validation completed  
- [ ] performance benchmarks met
- [ ] documentation updated
- [ ] git tagged with version number
- [ ] release notes prepared

### quality assurance process
- **code review**: claude explains all implementation decisions
- **user testing**: hands-on validation of new functionality
- **performance profiling**: memory and cpu usage monitoring
- **accessibility audit**: keyboard and voiceover navigation testing
- **error scenario testing**: network failures, permission issues, device changes

---

## long-term vision & extensibility

### advanced features enabled by native foundation
- **real-time transcription**: live processing during recording
- **ai-powered insights**: meeting analysis, action item extraction
- **advanced audio processing**: noise reduction, voice enhancement  
- **team collaboration**: shared transcripts, commenting system
- **integrations**: calendar sync, crm connections, export apis

### platform expansion opportunities
- **ios companion app**: mobile recording with desktop sync
- **watch app**: quick recording triggers and status monitoring  
- **safari extension**: web meeting transcription integration
- **shortcuts app**: automation and workflow integration

### business model implications
- **freemium pricing**: free tier with usage limits, pro tier unlimited
- **api platform**: developer access to transcription capabilities
- **enterprise features**: team management, compliance, custom deployment
- **marketplace ecosystem**: third-party plugins and integrations

this native foundation positions us perfectly for any future direction we want to pursue - from simple transcription tool to comprehensive meeting intelligence platform.

---

**implementation readiness**: all domain knowledge acquired, architecture decisions made, clear milestone progression defined. ready to begin milestone 1 development immediately.

**confidence level**: high - building on proven patterns with superior technical foundation

**next step**: create xcode project and begin milestone 1 core foundation implementation
