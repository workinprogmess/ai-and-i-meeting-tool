# architecture understanding: services vs microservices vs apis

*captured: 2025-09-15*

## key insight
services, microservices, and apis are fundamentally different architectural concepts that solve different problems at different scales. understanding the distinction is crucial for making appropriate architectural decisions.

## definitions and differences

### local service (what we're using)
a class or module within your application that encapsulates business logic.

```swift
class RecordingService {
    func startRecording() {
        // direct function call, runs in same process
        // microseconds to execute
        // no network, no serialization
        micRecorder.start()
    }
}
```

**characteristics:**
- lives inside your app
- same process, same memory space
- zero network latency
- crashes together, deploys together
- just organization of code
- instant communication

### microservice (separate application)
an independently deployable application that handles specific business capabilities.

```swift
// separate app running on a server
// deployed at recording.yourcompany.com

// your app calls it over network:
let url = URL(string: "https://recording.yourcompany.com/start")!
let response = try await URLSession.shared.data(from: url)
// network call, ~50-200ms latency
```

**characteristics:**
- separate application, separate deployment
- different server/container/process
- network communication required
- can scale independently
- can use different languages
- fault isolation (one service down, others work)
- requires serialization/deserialization
- adds complexity (service discovery, network failures, eventual consistency)

### api (communication contract)
the interface or contract that defines how different components communicate.

```swift
// rest api example
GET  /meetings
POST /meetings/start
PUT  /meetings/{id}/end

// could be implemented by:
// - a microservice (separate app)
// - a monolith endpoint (same app)
// - a local service with http wrapper
// - even a swift protocol
```

**characteristics:**
- just the interface definition
- agnostic to implementation
- defines the contract (inputs, outputs, errors)
- can be local (protocol/interface) or remote (rest/graphql)

## real-world analogy

**local service**: chef in your kitchen
- instant communication
- everything in one place
- no delivery time

**microservice**: ordering from different restaurants
- each restaurant specializes
- takes time for delivery (network)
- one closed doesn't affect others

**api**: the menu and ordering system
- defines how to order
- doesn't matter if kitchen or restaurant

## architecture evolution for ai&i

### current: local desktop app (0-100 users)
```
mac app (swift)
├── local services
│   ├── RecordingService (audio capture)
│   ├── MixingService (ffmpeg)
│   └── TranscriptionService (api calls)
└── ui views
```

everything runs on user's mac. no backend needed.

### next phase: with auth + database (100-1000 users)
```
mac app (swift)
├── local services (recording, mixing)
└── api client (auth, sync)
        ↓ internet
simple backend (monolith api)
├── /auth (login, signup)
├── /meetings (crud)
├── /sync (backup)
└── postgresql
```

one backend server, simple api, perfect for 100-1000 users.

### future: if scaling needed (10,000+ users)
only then consider extracting services:
```
mac app → api gateway
          ├── auth service
          ├── meeting service
          └── transcription service (high load)
```

## when to use what

### use local services when:
- code organization needed
- running on user's device
- need instant response
- no scaling requirements
- single deployment unit preferred

### use monolith api when:
- need authentication
- multiple clients (web, mobile)
- shared data between users
- backup/sync required
- 100-10,000 users

### use microservices when:
- multiple teams
- different scaling needs per component
- technology diversity needed
- fault isolation critical
- 10,000+ users
- can handle operational complexity

## common misconceptions

1. **"services" means microservices** - no, it's just code organization
2. **"modern apps need microservices"** - most successful apps are monoliths
3. **"apis require separate servers"** - apis are just interfaces
4. **"microservices are faster"** - actually slower due to network overhead

## successful monoliths
- **basecamp**: serves millions, still monolith
- **github**: monolith for years
- **stack overflow**: massive traffic, monolith
- **shopify**: monolith until huge scale
- **linear**: modern, fast, monolith

## storage strategy for ai&i

### the problem
- 1 hour meeting = 100-200mb wav
- 10 meetings/week = 5-10gb/month
- 6 months = 60gb

### recommended approach: local-first + cloud backup

**local processing:**
1. record → 200mb wav
2. mix locally → 100mb mixed wav
3. transcribe → 50kb text
4. compress to mp3 → 10mb
5. delete segments immediately

**cloud sync (optional):**
- upload mp3 + transcript
- delete local after 30 days
- stream from cloud when needed

**storage tiers:**
- last 7 days: full quality local
- last 30 days: mp3 local
- older: cloud only
- transcripts: keep forever (tiny)

### implementation strategy
```swift
struct StorageSettings {
    var keepAudioDays = 30
    var autoUpload = false
    var compressAudio = true
    var deleteSegments = true  // immediately after mixing
}
```

## key architectural principles

1. **don't solve problems you don't have** - complexity should match scale
2. **local-first for latency** - recording must be local
3. **simple until painful** - monolith until it hurts
4. **data locality matters** - keep data close to computation
5. **network is unreliable** - design for offline first

## recommendation for ai&i

**now → 1000 users:**
- local services for code organization
- simple monolith api for auth/sync
- cloud storage for backup
- focus on user experience, not architecture

**only consider microservices when:**
- team grows beyond 10 engineers
- specific components need 10x different scale
- operational expertise available
- monolith actually becoming painful

remember: **architecture should enable business, not constrain it**. the best architecture is the one that ships and serves users effectively.