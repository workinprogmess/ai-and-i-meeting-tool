# key decisions - ai&i audio capture reliability

## decision date: 2025-09-30

## the oscillation problem

**q:** what are we observing in our 3:01 test?
**a:** we're back to earlier issues. fixing one problem resurfaces another - classic oscillation pattern. 3 mic segments (2:38 total) vs 2 system segments (3:01 total), airpods file corrupted/glitchy, system audio robotic/ghostly.

**q:** what's the core issue causing this oscillation?
**a:** we solve one thing and another resurfaces. it's not individual bugs - it's systemic interaction issues. we're fighting the system instead of working with it.

## root cause analysis

**q:** what exactly happens when airpods connect?
**a:** airpods connect at 24khz (telephony mode) → we detect and complain "⚠️ input sample rate below 44khz" → but then try to use them anyway → triggers device switching during bluetooth negotiation → core audio resource conflicts → corrupted audio pipeline.

**q:** why does this create the cascade of `-10877` errors?
**a:** we're forcing engine restarts while bluetooth is still negotiating profiles and core audio hasn't cleaned up resources. it's like demanding someone switch phone calls instantly while both are still connecting.

**q:** is the corruption from 24khz quality or our switching process?
**a:** from our switching process. 24khz is fine for transcription (phone calls work, ai models handle compressed audio). corruption comes from forcing transitions at wrong time.

## telephony circuit breaker evaluation

**q:** would rejecting telephony mode (circuit breaker) solve this?
**a:** no, because airpods frequently connect in 24khz initially. circuit breaker would mean rarely using airpods at all - defeats the purpose.

**q:** how often do we actually get high-quality airpods connection?
**a:** based on our tests, airpods seem to always start in 24khz mode initially. fighting this is fighting the natural bluetooth process.

**q:** if we accept telephony mode, what about audio quality for transcription?
**a:** 24khz is perfectly fine. phone calls work at 8khz. whisper trained on phone audio. zoom/teams use telephony quality all the time. users care about transcripts, not audio quality.

## mixing and technical questions

**q:** if we have 24khz airpods segments and 48khz built-in segments, can we mix them?
**a:** yes, ffmpeg `aresample=48000` automatically converts any sample rate to 48khz. our mixing script already handles this perfectly.

**q:** with "late device churn" approach, how much audio would we lose?
**a:** 2-3 seconds during airpods stabilization (not minutes). but we'd get clean audio afterward instead of corrupted audio throughout.

**q:** why can't this be simpler? recording shouldn't be this complex, right?
**a:** exactly. other apps like granola/otter handle this seamlessly. they don't fight bluetooth profiles - they accept what the system provides when it's stable.

## the breakthrough insight

**q:** what are successful apps doing differently?
**a:** they're not fighting bluetooth profile negotiations. they prioritize "works reliably" over "perfect specifications." they wait for actual signal stability, not just connection events.

**q:** so what's our fundamental problem?
**a:** we're working against the system instead of with it. we detect issues but then proceed anyway, creating chaos. we should either reject cleanly or accept gracefully.

## our solution: "gentle stability" approach

**q:** what's the core philosophy shift?
**a:** from "make the system give us perfect audio" to "get the cleanest audio the system can reliably provide."

**q:** how does this solve the oscillation?
**a:** by eliminating the indecision. instead of "24khz is bad but let's use it anyway," we say "24khz is fine, let's wait for it to be stable, then use it cleanly."

**q:** what are the key technical changes?
**a:**
1. stop fighting sample rates - accept any rate, focus on stability
2. signal stability detection - wait for real readiness (rms levels, buffer consistency)
3. graceful transition timing - 2-3s settlement instead of immediate switching
4. resource settlement periods - 400ms delays between teardown/restart
5. asymmetric routing - built-in mic input, airpods output when needed

## expected outcome

**q:** how confident are we this will work?
**a:** 85/100. we're addressing root causes (resource conflicts, timing) not symptoms. our infrastructure is mature - we're just changing strategy from fighting to working with the system.

**q:** what will this give us?
**a:** consistent mixed audio regardless of device switching, clean files for transcription services, foundation to focus on transcript quality and summaries instead of fighting core audio.

## implementation approach

**q:** where do we start?
**a:** telephony acceptance first (biggest impact), then stability detection, test incrementally. start gentle, build confidence.

---

*key insight: treat device switching like a careful dance, not a forced march. work with core audio's timing instead of fighting it.*