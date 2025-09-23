# milestone 2 phase 4 – codex revised plan

## overview
focused on eliminating launch hangs, fully hardening the dual-pipeline audio workflow (airpods included), tightening the transcription chain, and aligning the ui with actual capabilities before moving to milestone 3 summaries. incorporates codex review findings from 2025-09-18.

## audio capture and mixing
- fix launch hang by moving hot-standby prep and monitor startup off the main actor; profile with instruments and capture metrics in `PerformanceMonitor`
- ensure `DeviceChangeMonitor` restarts for every recording session and resumes callbacks after `stopMonitoring()`
- inject a single session clock into mic/system recorders so both pipelines share the same timestamp (current split timestamps break mixing)
- move mic/system buffer processing and file writes off the main actor queues to prevent ui stalls
- updates to `native/Scripts/mix-audio.swift`:
  - resolve files using absolute paths (no `URL(string:)`), accept explicit session id param, and respect session-specific folders when introduced
  - add retry/backoff + clearer stderr logging on non-zero ffmpeg exits; surface errors back to the app
  - make mix volume decisions deterministic (airpods vs built-in) and log actual files mixed
- rewarm the two pipelines on app launch (mic + system) and verify airpods on/off transitions no longer create silent segments or duplicates (cover -10877 scenario)
- run long-session tests with deliberate device switches + external monitor changes and capture results in project journal

## transcription pipeline
- gate mp3 conversion behind explicit ffmpeg checks, add one retry with backoff, and surface conversion failures prominently in the ui
- standardize transcript storage (one canonical `session_<id>_transcripts.json`) and persist the chosen "best" service for list display
- upgrade prompts/settings using `shared/transcript-format-sample.md`, multilingual + speaker hints, and AirPods/system context
- parse and render confidence scores in the transcript ui once services return them (opacity/icons)
- enrich status updates so each service reports queued, running, success, failure; include missing-key details and log ids
- audit JSON writing to ensure concurrent sessions cannot clobber metadata (use atomic writes or per-session dirs)

## recording experience and performance
- keep the recording timer entirely off the main run loop (no freezes) and verify sub-second start latency
- after each session, re-enable monitoring, clear timers, and reset state so consecutive recordings stay stable
- measure launch/start/stop latency with `PerformanceMonitor` and document results for milestone 4
- document and automate regression steps that cover record → switch devices → mix → transcribe → display

## ui and product polish
- finish japanese palette alignment for service tabs, action tray, metadata strips (audit vs design tokens)
- hide or fully wire share/export/correction controls so the ui only shows available actions
- tighten layout spacing, de-duplicate unused views, and reorganize directories (views vs services vs scripts)
- enforce lowercase copy across the ui and docs (spot check `TranscriptDetailView`, modals, alerts)
- add loading + error states for transcription actions per service (spinner, inline errors)

## infrastructure and quality
- keep secrets out of source and rotate any demo/testing keys
- expand logging around mixing/transcription/device switching with context-rich entries (session id, device id, file paths)
- maintain a living regression checklist and record every run in `shared/project-state.md`
- add automated sanity scripts (e.g., `verify_setup.sh`) to cover ffmpeg, permissions, and key env vars
- once fixes land, update the journal with factual status (no premature ✅)

last updated: 2025-09-18 (codex phase 4 review refresh)
