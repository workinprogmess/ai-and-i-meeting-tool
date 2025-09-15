# milestone 2 phase 4 (revised) - polish & transcription quality

*updated: 2025-09-15*

## overview
focusing on essential polish and transcription improvements to reach mvp quality before moving to milestone 3 (summaries).

## phase 4 tasks (1-2 days)

### 1. ui polish (4 hours)
- [ ] fix airpods double segment bug (-10877 errors)
- [ ] service tabs with proper japanese colors and separation
- [ ] action tray with consistent design system colors
- [ ] fix metadata duration if still showing 0
- [ ] ensure all text is lowercase consistently

### 2. transcription quality improvements (4 hours)

#### gemini improvements
```swift
// better speaker prompting
let prompt = """
transcribe this meeting audio with multiple speakers.

speakers present:
- speaker 1: primary participant (male voice from microphone)
- speaker 2: secondary participant (female voice from microphone)
- system: any youtube, video, or system audio

important:
- maintain consistent speaker labels throughout the entire transcript
- if unsure about a speaker, use the most likely based on voice characteristics
- include all languages spoken (english, hindi, hinglish)
- preserve code-switching and mixed language naturally
- mark overlapping speech with [overlapping] tag

format each segment as:
speaker: text
"""
```

#### deepgram improvements
```swift
// enable multilingual support
URLQueryItem(name: "language", value: "multi"),  // or "en-IN" for india english
URLQueryItem(name: "detect_language", value: "true"),
URLQueryItem(name: "multichannel", value: "true"),  // if we have separate channels
URLQueryItem(name: "paragraphs", value: "true"),
URLQueryItem(name: "utterances", value: "true")
```

#### assembly ai improvements
```swift
// better language support
"language_code": "en",  // let it auto-detect variants
"auto_highlights": true,  // detect important phrases
"speaker_labels": true,
"speakers_expected": 3,  // hint about speaker count
"language_detection": true,
"punctuate": true,
"format_text": true
```

### 3. confidence score implementation (2 hours)

#### data model update
```swift
struct TranscriptSegment {
    let speaker: Speaker
    let text: String
    let timestamp: TimeInterval?
    let confidence: Double?  // add this (0.0 to 1.0)
}
```

#### ui visualization
```swift
// show confidence as opacity or underline
Text(segment.text)
    .opacity(segment.confidence ?? 1.0)  // fade uncertain text
    
// or show warning for low confidence
if let confidence = segment.confidence, confidence < 0.7 {
    Image(systemName: "exclamationmark.triangle")
        .foregroundColor(.orange)
        .help("low confidence transcription")
}
```

#### service integration
- gemini: extract from response if available
- deepgram: parse from `confidence` field in response
- assembly: use `confidence` field from words array

### 4. quick fixes (2 hours)
- [ ] only copy button in action tray (defer rest)
- [ ] improve meeting title extraction (use ai if time)
- [ ] add loading states for transcription progress
- [ ] better error messages for failed transcriptions

## deferred to milestone 5
- user corrections system
- sharing features (link generation)
- export to pdf/markdown
- team workspaces

## deferred to milestone 6
- admin dashboard
- analytics
- compliance features

## success criteria
- [ ] airpods switching works without double segments
- [ ] all three services handle mixed language better
- [ ] ui consistently uses japanese design system
- [ ] confidence scores visible where available
- [ ] app feels polished enough for alpha users

## next: milestone 3 - human-like summaries

### reuse from electron implementation
we already built sally rooney-style summaries in electron! we can port:
- prompt framework from `sally_rooney_prompt_framework.md`
- summary generation logic
- gpt-4/gemini integration code

### native implementation plan (2-3 days)
1. **port summary service** (1 day)
   - create `SummaryService.swift`
   - integrate openai/gemini apis
   - reuse prompts from electron

2. **ui integration** (1 day)
   - add summary tab to transcript view
   - show summary with sections:
     - key points
     - action items
     - emotional dynamics
     - decisions made

3. **polish** (0.5 day)
   - loading states
   - error handling
   - cost tracking

### why summaries matter
this is our **core differentiation**:
- granola: just transcripts
- otter: basic summaries
- **ai&i**: human-like summaries with emotional intelligence

with summaries, we have a complete mvp:
1. perfect mixed audio recording ✅
2. multi-service transcription ✅
3. human-like summaries (next)

## timeline
- **today-tomorrow**: complete phase 4 polish
- **next 2-3 days**: implement summaries (milestone 3)
- **end of week**: mvp ready for alpha users
- **while testing**: start auth/backend (milestone 4)