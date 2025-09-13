# milestone 2: transcription integration (0.2.0)

## overview
integrate multiple transcription services (gemini, deepgram, assembly ai) with comparison capabilities in admin mode. focus on reliable transcription with speaker attribution, beautiful minimal ui, and learning from user corrections.

## timeline
**estimated**: 7-8 days
**target completion**: 2025-09-19

## success criteria
- [ ] three transcription services working in parallel
- [ ] admin mode comparing all three with metrics
- [ ] regular users see best/fastest transcript
- [ ] user corrections improve future transcriptions
- [ ] beautiful minimal ui with san francisco font
- [ ] automatic mp3 conversion for file size optimization

## technical architecture

### audio pipeline
```
segmented recordings → mix-audio.swift → mixed wav → mp3 conversion → parallel transcription
                                                                      ├── gemini
                                                                      ├── deepgram
                                                                      └── assembly ai
```

### key design decisions
- **mp3 conversion**: reduce file size by 10x (wav ~10mb/min → mp3 ~1mb/min)
- **parallel processing**: all three services transcribe simultaneously
- **admin vs regular**: admin sees all three, regular users see best result
- **correction learning**: track what was wrong + what's correct
- **fallback strategy**: if mixing fails, transcribe separately and stitch

## implementation phases (revised 2025-09-13)

### ✅ phase 1: multi-service integration (COMPLETE)
**goal**: integrate gemini, deepgram, and assembly ai in parallel

#### completed
- ✅ all three services integrated and working
- ✅ parallel processing with quality metrics
- ✅ mp3 conversion working (10x size reduction)
- ✅ automatic mixing integration
- ✅ api limits verified (gemini 20mb inline, 2gb files api)
- ✅ discovered gemini best quality + cheapest ($0.002/min)

#### service abstraction
```swift
protocol TranscriptionService {
    func transcribe(audioURL: URL) async throws -> Transcript
    func calculateCost(duration: TimeInterval) -> Double
    var serviceName: String { get }
}

class TranscriptionCoordinator {
    func transcribeWithAllServices(audioURL: URL) async -> [ServiceResult]
    func selectBestTranscript(_ results: [ServiceResult]) -> Transcript
}
```

#### mp3 conversion
```swift
func convertToMP3(wavURL: URL) async throws -> URL {
    // ffmpeg -i input.wav -b:a 128k output.mp3
    // returns mp3 file url
}
```

### phase 2: processing pipeline with fallback (1.5 days)
**goal**: robust pipeline with mixing fallback

#### primary flow
1. recording stops → segments saved
2. mix-audio.swift → mixed wav file
3. convert to mp3 (10x smaller)
4. parallel transcription (all 3 services)
5. results saved and displayed

#### fallback flow (if mixing fails)
1. transcribe mic and system separately
2. use segment timestamps to stitch
3. mark as "reconstructed transcript"
4. still use all 3 services

#### error handling
- service timeout: show results from completed services
- network failure: queue for retry
- file too large: chunk into smaller segments

### phase 3: data model with corrections (1 day)
**goal**: smart data structure that learns from user

#### transcript model
```swift
struct Transcript: Codable {
    let id: UUID
    let sessionID: String
    let service: TranscriptionService.Type
    let segments: [TranscriptSegment]
    let metadata: TranscriptMetadata
    let cost: Double
    let processingTime: TimeInterval
    let createdAt: Date
}

struct TranscriptSegment: Codable {
    let speaker: Speaker
    let text: String
    let confidence: Float?
}

enum Speaker: Codable {
    case me
    case other(String) // "speaker1", "speaker2"
}
```

#### user corrections system
```swift
struct UserDictionary: Codable {
    var corrections: [UserCorrection]
    var names: Set<String>
    var companies: Set<String>
    var phrases: Set<String>
}

struct UserCorrection: Codable {
    let wrong: String      // "wikus"
    let correct: String    // "vikas"
    let context: String?   // "hi wikus" → "hi vikas"
    let addedAt: Date
}
```

#### injection into prompts
```
"note: user vocabulary includes:
- names: vikas, anthropic, granola
- common phrases: theek hai, c'est la vie
- corrections: 'wikus' should be 'vikas', 'antropic' should be 'anthropic'"
```

### phase 4: beautiful minimal ui (2 days)
**goal**: clean, minimal interface with admin capabilities

#### design system
- **font**: san francisco (system font)
- **colors**: 
  - background: #fafafa (off-white)
  - primary text: #1a1a1a (near black)
  - secondary: #6a6a6a (grey)
  - speakers: subtle colors (#2563eb for @me, #059669 for others)
- **all lowercase** everywhere
- **smooth animations**: 200ms ease-in-out

#### regular user view
```swift
struct TranscriptView: View {
    var body: some View {
        VStack {
            // clean header
            HStack {
                Text("team standup").font(.title3)
                Spacer()
                Button("share") { }
            }
            
            // single transcript (best/fastest)
            ScrollView {
                ForEach(segments) { segment in
                    TranscriptRow(segment: segment)
                }
            }
        }
    }
}
```

#### admin mode additions
```swift
struct AdminTranscriptView: View {
    var body: some View {
        VStack {
            // service selector
            Picker("service", selection: $selectedService) {
                Text("gemini").tag(0)
                Text("deepgram").tag(1)
                Text("assembly").tag(2)
            }
            .pickerStyle(.segmented)
            
            // comparison metrics
            HStack {
                MetricView(title: "time", value: processingTime)
                MetricView(title: "cost", value: cost)
                MetricView(title: "words", value: wordCount)
            }
            
            // transcript for selected service
            TranscriptContent(service: selectedService)
        }
    }
}
```

#### visual hierarchy
- recording title: weight(.medium), size(17)
- timestamps: weight(.regular), size(13), color(#6a6a6a)
- speaker labels: weight(.medium), size(14)
- transcript text: weight(.regular), size(15)
- all lowercase, no uppercase anywhere

### phase 5: testing & optimization (1.5 days)
**goal**: comprehensive testing and performance tuning

#### test scenarios
- [ ] 2-minute recording → all 3 services complete
- [ ] airpods switching → speaker attribution maintained
- [ ] 30+ minute recording → no memory issues
- [ ] mixing failure → fallback works correctly
- [ ] user corrections → improves next transcription
- [ ] network interruption → graceful handling

#### comparison metrics
- transcription speed (seconds)
- cost per minute
- word count accuracy
- speaker attribution accuracy
- confidence scores

#### performance optimization
- lazy loading for long transcripts
- virtualized scrolling
- background processing
- efficient diff algorithms for corrections

### phase 6: admin dashboard (1 day)
**goal**: comprehensive comparison view for testing

#### features
- side-by-side transcript comparison
- word-level diff highlighting
- cost breakdown per service
- processing time graphs
- accuracy metrics (once we can measure)
- export comparison report

## cost analysis

### service pricing comparison
| service | audio input | per hour | 1h meeting |
|---------|------------|----------|------------|
| gemini 2.5 flash | $0.002/min | $0.12 | ~$0.14 |
| deepgram nova-2 | $0.0043/min | $0.26 | ~$0.28 |
| assembly ai | $0.01/min | $0.60 | ~$0.65 |

### testing phase costs (all 3 services)
- per meeting: $0.14 + $0.28 + $0.65 = ~$1.07
- 10 meetings: ~$10.70
- acceptable for testing to find best service

### production (single service)
- likely gemini (cheapest + good quality)
- fallback to deepgram if gemini fails
- assembly ai for specific high-accuracy needs

## revised phase structure (2025-09-13)

### completed
- ✅ **phase 1-2**: core transcription pipeline with quality metrics

### remaining phases

#### phase 3: ui basics (1.5 days)
- meetings list landing page
- recording flow with animations
- clean transcript view
- japanese color palette
- san francisco typography
- floating action tray

#### phase 4: ui advanced + corrections (2 days)
- corrections ui (click to correct)
- user dictionary persistence
- learning from corrections
- prompt injection to services
- share/export functionality
- performance optimizations

#### phase 5: testing & optimization (1.5 days)
- long recording tests
- memory optimization
- edge case handling
- performance tuning

#### phase 6: admin dashboard (deferred)
- may not be needed if current comparison view works well

**total remaining**: ~5 days

## implementation notes

### file size optimization
```swift
// wav: ~10mb per minute (too large)
// mp3: ~1mb per minute (perfect)

func prepareAudioForTranscription(wavURL: URL) async throws -> URL {
    let mp3URL = wavURL.deletingPathExtension().appendingPathExtension("mp3")
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
    process.arguments = [
        "-i", wavURL.path,
        "-b:a", "128k",  // 128kbps bitrate
        "-ar", "16000",  // 16khz sample rate (optimal for speech)
        mp3URL.path
    ]
    
    try process.run()
    process.waitUntilExit()
    
    return mp3URL
}
```

### parallel service execution
```swift
func transcribeAllServices(audioURL: URL) async -> [ServiceResult] {
    await withTaskGroup(of: ServiceResult.self) { group in
        group.addTask { await self.geminiService.transcribe(audioURL) }
        group.addTask { await self.deepgramService.transcribe(audioURL) }
        group.addTask { await self.assemblyService.transcribe(audioURL) }
        
        var results: [ServiceResult] = []
        for await result in group {
            results.append(result)
        }
        return results
    }
}
```

## ui/ux principles

### typography
- single font family: sf pro (san francisco)
- weights: regular (400), medium (500) only
- sizes: 13, 14, 15, 17 only
- all lowercase everywhere

### spacing
- consistent 8pt grid
- padding: 16pt standard, 8pt compact
- line height: 1.4x font size

### colors
```swift
extension Color {
    static let aiBackground = Color(hex: "fafafa")
    static let aiPrimary = Color(hex: "1a1a1a")
    static let aiSecondary = Color(hex: "6a6a6a")
    static let aiMe = Color(hex: "2563eb")      // blue
    static let aiOther = Color(hex: "059669")   // green
}
```

### animations
- duration: 200ms standard
- easing: ease-in-out
- no bouncy or playful animations
- subtle fade and slide only

## success metrics
- transcription available within 10s of recording stop
- 90%+ accuracy on standard english
- proper noun recognition improves with corrections
- ui feels instant (<100ms response)
- memory usage <200mb for hour-long transcripts

## future enhancements (post-milestone 2)
- real-time transcription (streaming)
- custom vocabulary per user
- team shared corrections
- transcript confidence highlighting
- smart summary generation (milestone 3)

---

*last updated: 2025-09-11*
*comprehensive plan based on brainstorming session*
*focus on comparison testing with beautiful minimal ui*