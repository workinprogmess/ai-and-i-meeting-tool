# phase 4 reliability todo tracker (temp)

## status snapshot
- ✅ item 1: shared session clock + monitor restart groundwork (contexts injected, watchers reset)
- ✅ item 2: device monitor restarts per session
- ✅ item 3: mic/system pipelines moved off main actor (background queues, cached state)
- ✅ item 4: instrumentation helper + transcription env loader script
- ✅ **item 5/6: telephony processing improvements + reliable fallback (2025-10-09)**

## ✅ **intelligent fallback system working**: built-in mic backup reliable
**situation**: airpods silent detection and automatic fallback to built-in mic functioning well
**solution**: intelligent telephony fallback system with signal monitoring

**current status**:
- ✅ **fallback system reliable**: automatic switch to built-in mic when airpods go silent
- ✅ telephony processing improvements implemented (AGC bypass, adaptive leveling, signal monitoring)
- ✅ telephony audio quality verified across 5–6 minute AirPods sessions with live fallback/recovery
- ✅ comprehensive 4-commit systematic approach for telephony handling

**technical approach**: accept telephony compression, apply minimal enhancement, fall back when needed
**working well**: built-in mic fallback provides reliable capture when airpods fail

**status**: fallback system proven reliable; AirPods segments stay wideband after route churn and transcription now runs automatically

**trail**:
- 2025-10-09: initial fallback stability, AGC bypass, and telephony leveler in place
- 2025-10-10: resolved verification stalls, added speech freshness + telephony timeout safeguards
- 2025-10-11: tuned route pinning for AirPods removal, confirmed 5m+ sessions with seamless transcription

## item 5/6 breakdown
- [x] warm prep inside `MicRecorder` using reusable engine
  - ✅ coalesce route changes with ~2s debounce, mark "unstable" when we see ≥2 switches, and only act on the last desired device
  - ✅ add 300–500ms settle delay plus readiness loop (up to 10 `inputFormat` probes) and surface "holding mic" when the hardware never reports a sane format
  - ✅ support pinned mode when we see ≥3 switches in 10s so we hold the current mic for ~60s before trying again
- [x] mic pipeline reliability overhaul: adopt single state machine with guarded switching
  - ✅ enforce minimum segment duration (~20s) unless we hit a hard failure or explicit stop to prevent micro-segmentation
  - ✅ add writer drain barrier on switch (`recordingEnabled=false` → remove tap → `writerQueue.sync` → nil engine → settle delay → open new file) so no writes are in flight
  - ✅ **telephony processing improvements**: bypass AGC, intelligent leveling, automatic activation + reliable fallback to built-in mic
  - ✅ ensure stall suppression and segment stitching behave with telephony segments (no silent gaps; converter verified with real AirPods capture)
  - ✅ keep all mic segments at 48kHz mono PCM and stitch with silence insertion or 20ms crossfade when timelines overlap
  - [x] verify long-session stability with new telephony handling (real-world 5–6 minute AirPods sessions, transcription enabled)
- [x] warm prep inside `SystemAudioRecorder` with retries and cached SCContentFilter
  - ✅ restart SCStream cleanly on output device changes (AirPods on/off) so system segments match mic segments when routes shift
  - ✅ validate route change rebuilds eliminate `_SCStream … Dropping frame` / `-10877` spam in long sessions
- [x] recording session coordinator orchestrating warm prep, lifecycle, retry, and device-change sequencing (initial skeleton exists; needs lifecycle observers, debug toggles, proper warm shutdown, and independent mic/system switching)
- [x] replace temporary airpods output reroute with stable output pipeline (preserve user output device)
- [x] lifecycle hooks (foreground/background) to pause + rewarm pipelines (treat wake like a route change)
- [x] debug hooks for simulated device changes/telephony mode
- [x] telemetry wiring into `PerformanceMonitor` once pipelines are stable (log route changes, executed switches, pinned activations, readiness attempts, segment counts, mic vs system duration, warm-up discards, writer drops, lossiness flag)
- [x] end-to-end tests: long session with repeated airpods toggles, playback verification, transcription pass

## remaining plan (copied from milestone 2 phase 4 codex plan)

### audio capture and mixing
1. fix launch hang by moving hot-standby prep and monitor startup off the main actor; profile with instruments and capture metrics in `PerformanceMonitor`
2. ensure `DeviceChangeMonitor` restarts for every recording session and resumes callbacks after `stopMonitoring()`
3. inject a single session clock into mic/system recorders so both pipelines share the same timestamp (current split timestamps break mixing)
4. move mic/system buffer processing and file writes off the main actor queues to prevent ui stalls
5. updates to `native/Scripts/mix-audio.swift`:
   - resolve files using absolute paths (no `URL(string:)`), accept explicit session id param, and respect session-specific folders when introduced
   - add retry/backoff + clearer stderr logging when mixing fails, including non-zero ffmpeg exits; surface errors back to the app
   - make mix volume decisions deterministic (airpods vs built-in) and log actual files mixed
   - ✅ ensure `amix` uses the longest input and pass literal file paths so system audio can cover mic dropouts (2025-09-26)
6. rewarm the two pipelines on app launch (mic + system) and verify airpods on/off transitions no longer create silent segments or duplicates (cover -10877 scenario)
7. run long-session tests with deliberate device switches + external monitor changes and capture results in project journal
8. build dual warm pipelines with coordinated lifecycle:
   - add warm-prep with retries inside each recorder; if all retries fail, surface a blocking error instead of falling back silently
   - introduce a `RecordingSessionCoordinator` that manages shared context creation, warm prep, start/stop, and device-change sequencing
   - replace the temporary airpods reroute with a dedicated output pipeline that preserves the user’s chosen device while we capture and restores on stop
     (mid-session reroutes removed; snapshot + restore only on stop – verify across long sessions)
   - pause/release warmed resources when the app backgrounds and rewarm on return to foreground
   - expose debug hooks to simulate device changes/telephony mode so we can regression-test race conditions

### transcription pipeline
9. gate mp3 conversion behind explicit ffmpeg checks, add one retry with backoff, and surface conversion failures prominently in the ui
10. standardize transcript storage (one canonical `session_<id>_transcripts.json`) and persist the chosen "best" service for list display
11. upgrade prompts/settings using `shared/transcript-format-sample.md`, multilingual + speaker hints, and AirPods/system context
12. parse and render confidence scores in the transcript ui once services return them (opacity/icons)
13. enrich status updates so each service reports queued, running, success, failure; include missing-key details and log ids
14. audit JSON writing to ensure concurrent sessions cannot clobber metadata (use atomic writes or per-session dirs)

### recording experience and performance
15. keep the recording timer entirely off the main run loop (no freezes) and verify sub-second start latency
16. after each session, re-enable monitoring, clear timers, and reset state so consecutive recordings stay stable
17. measure launch/start/stop latency with `PerformanceMonitor` and document results for milestone 4
18. document and automate regression steps that cover record → switch devices → mix → transcribe → display

### ui and product polish
19. finish japanese palette alignment for service tabs, action tray, metadata strips (audit vs design tokens)
20. hide or fully wire share/export/correction controls so the ui only shows available actions
21. tighten layout spacing, de-duplicate unused views, and reorganize directories (views vs services vs scripts)
22. enforce lowercase copy across the ui and docs (spot check `TranscriptDetailView`, modals, alerts)
23. add loading + error states for transcription actions per service (spinner, inline errors)

### infrastructure and quality
24. keep secrets out of source and rotate any demo/testing keys
25. expand logging around mixing/transcription/device switching with context-rich entries (session id, device id, file paths)
26. maintain a living regression checklist and record every run in `shared/project-state.md`
27. add automated sanity scripts (e.g., `verify_setup.sh`) to cover ffmpeg, permissions, and key env vars
28. once fixes land, update the journal with factual status (no premature ✅)
