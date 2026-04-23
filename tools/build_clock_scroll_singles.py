#!/usr/bin/env python3

from __future__ import annotations

import wave
from array import array
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_PATH = ROOT_DIR / "clock_scroll_sources" / "freesound_community-analog-stopwatch-winding-72055.wav"
OUTPUT_DIR = ROOT_DIR / "clock_scroll_candidates" / "freesound_community-analog-stopwatch-winding-72055"

CLIPS = [
    ("single_default_01.wav", 3.065, 0.010, 0.074),
    ("single_default_02.wav", 11.853, 0.010, 0.074),
    ("single_default_03.wav", 12.982, 0.010, 0.070),
    ("single_default_04.wav", 15.609, 0.010, 0.074),
    ("single_space_01.wav", 13.270, 0.010, 0.088),
    ("single_return_01.wav", 15.792, 0.010, 0.094),
    ("single_delete_01.wav", 15.916, 0.008, 0.078),
    ("single_modifier_01.wav", 13.382, 0.010, 0.082),
]


def write_wave(path: Path, samples: list[int], channels: int, sample_rate: int) -> None:
    pcm = array("h", samples)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm.tobytes())


def apply_fades(samples: list[int], channels: int, sample_rate: int, fade_in_ms: float = 1.0, fade_out_ms: float = 8.0) -> list[int]:
    output = samples[:]
    frame_count = len(output) // channels
    fade_in_frames = min(frame_count, round(sample_rate * fade_in_ms / 1000.0))
    fade_out_frames = min(frame_count, round(sample_rate * fade_out_ms / 1000.0))

    for frame_index in range(frame_count):
        gain = 1.0
        if fade_in_frames > 0 and frame_index < fade_in_frames:
            gain *= frame_index / fade_in_frames
        if fade_out_frames > 0 and frame_index >= frame_count - fade_out_frames:
            remaining = frame_count - frame_index - 1
            gain *= max(0.0, remaining / fade_out_frames)

        if gain == 1.0:
            continue

        start = frame_index * channels
        for channel_offset in range(channels):
            output[start + channel_offset] = int(output[start + channel_offset] * gain)

    return output


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with wave.open(str(SOURCE_PATH), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()
        raw = wav_file.readframes(frame_count)

    if sample_width != 2:
        raise ValueError("Only 16-bit PCM WAV is supported")

    source_samples = array("h")
    source_samples.frombytes(raw)

    for file_name, peak_time, pre_roll_seconds, duration_seconds in CLIPS:
        start_frame = max(0, round((peak_time - pre_roll_seconds) * sample_rate))
        frame_length = max(1, round(duration_seconds * sample_rate))
        start = start_frame * channels
        end = min(len(source_samples), start + frame_length * channels)
        clip_samples = source_samples[start:end].tolist()
        clip_samples = apply_fades(clip_samples, channels, sample_rate)
        write_wave(OUTPUT_DIR / file_name, clip_samples, channels, sample_rate)

    print(f"Wrote {len(CLIPS)} single-click clips to {OUTPUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
