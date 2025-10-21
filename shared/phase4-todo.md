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

## handoff summary
- ✅ v0.2 (audio stability) completed 2025-10-20 – dual pipelines, fallback, telemetry, validation script in place
- ➡️ Remaining backlog redistributed to the version roadmap:
  - v0.3 `transcription & summaries` (ffmpeg gating, canonical storage, prompts, confidence, statuses)
  - v0.4 `interface rebuild` (layout, palette, control wiring, lowercase, loading states)
  - v0.5 `everyday workflow` (share/export, search, folders, onboarding, settings, notifications)
  - v0.6 `backend & reliability` (secrets, logging, regression checklist, setup scripts, journal discipline)

Refer to `shared/NATIVE_APP_IMPLEMENTATION_PLAN.md` for the authoritative per-version backlog.
