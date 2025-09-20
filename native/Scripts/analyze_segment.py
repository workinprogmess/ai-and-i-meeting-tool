#!/usr/bin/env python3
"""quick waveform diagnostics for ai&i recordings."""

import sys
import wave
import struct
import pathlib
import statistics


def describe_segment(path: pathlib.Path, window_seconds: int = 5) -> None:
    with wave.open(str(path), "rb") as wav_file:
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()
        channels = wav_file.getnchannels()
        frames = wav_file.readframes(frame_count)

    samples = struct.unpack(f"<{frame_count * channels}h", frames)
    duration = frame_count / sample_rate
    print(f"file: {path.name}")
    print(f"  duration: {duration:.2f}s  sample_rate: {sample_rate}hz  channels: {channels}")

    window = sample_rate * window_seconds
    rms_values = []
    for i in range(0, len(samples), window):
        chunk = samples[i : i + window]
        if not chunk:
            break
        rms = statistics.mean(abs(s) for s in chunk)
        rms_values.append(rms)

    if rms_values:
        preview = [round(v) for v in rms_values[:10]]
        print(f"  avg rms over {window_seconds}s windows (first 10): {preview}")
        print(f"  global max amplitude: {max(abs(s) for s in samples)}")
    else:
        print("  no samples found")


if __name__ == "__main__":
    recordings_dir = pathlib.Path.home() / "Documents" / "ai&i-recordings"

    if len(sys.argv) > 1:
        candidate = recordings_dir / sys.argv[1]
        if not candidate.exists():
            raise SystemExit(f"file not found: {candidate}")
        describe_segment(candidate)
    else:
        latest = sorted(recordings_dir.glob("mic_*.wav"))[-1]
        describe_segment(latest)
