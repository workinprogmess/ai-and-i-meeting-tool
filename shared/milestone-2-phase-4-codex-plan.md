# milestone 2 phase 4 – codex revised plan

## overview
focused on stabilizing audio capture, strengthening the transcription pipeline, polishing the ui, and tightening infrastructure before moving to milestone 3 summaries. this plan merges outstanding claude items with new codex findings.

## audio capture and mixing
- resolve airpods on/off behaviour that creates silent mic segments and duplicate files (ffmpeg -10877)
- restart `DeviceChangeMonitor` when new sessions begin so device changes keep flowing (`MeetingsListView.swift`)
- update `native/Scripts/mix-audio.swift` to accept a session id argument and constrain mixing to that recording
- remove absolute script paths; look up the mixer relative to the app bundle
- add retries and clearer logging when mixing fails, including non-zero ffmpeg exits
- run long-session tests with deliberate device switches to confirm the pipeline remains lossless

## transcription pipeline
- stabilize mp3 conversion by validating ffmpeg availability, surfacing conversion errors to the ui, and retrying once before failing
- align transcript storage and loading (one canonical filename, persist the chosen best service for display)
- improve prompts for gemini/deepgram/assembly using `shared/transcript-format-sample.md` and multilingual requirements
- parse and show confidence scores in the transcript ui once services return them
- enrich in-app status updates so each service reports start, success, or failure explicitly

## recording experience and performance
- eliminate the ui timer freeze at 00:00 by adjusting scheduling off the main run loop
- audit warm-start latency (<200ms target) and record findings for milestone 4 optimization
- ensure consecutive recordings automatically re-enable monitoring, clear timers, and keep device state healthy

## ui and product polish
- finish the japanese palette alignment for service tabs, action tray, and metadata strips
- make share/export/correction buttons functional or hide them until ready in `TranscriptDetailView`
- tighten layout spacing and reorganize project directories (views vs. services vs. scripts) for clarity
- enforce lowercase copy across the ui and supporting documentation

## infrastructure and quality
- keep secrets out of source control; rely on environment variables or keychain and rotate any exposed keys
- extend logging around mixing/transcription to speed up debugging
- define a regression checklist covering record → mix → transcribe → display before milestone sign-off
- document each completed improvement in `shared/project-state.md` to maintain the living journal

last updated: 2025-09-17
