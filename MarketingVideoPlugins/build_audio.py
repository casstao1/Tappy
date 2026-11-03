#!/usr/bin/env python3

from __future__ import annotations

import math
import random
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(__file__).resolve().parent / "remotion/public/tappy-audio.wav"
SAMPLE_RATE = 48_000
DURATION = 31.0
FRAME_COUNT = int(SAMPLE_RATE * DURATION)


def read_wave(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        sample_width = handle.getsampwidth()
        source_rate = handle.getframerate()
        raw = handle.readframes(handle.getnframes())
    if sample_width != 2:
        raise ValueError(f"Expected 16-bit PCM audio: {path}")
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    samples = samples.reshape(-1, channels)
    if channels == 1:
        samples = np.repeat(samples, 2, axis=1)
    elif channels > 2:
        samples = samples[:, :2]
    if source_rate != SAMPLE_RATE:
        old_x = np.linspace(0.0, 1.0, len(samples), endpoint=False)
        new_length = int(round(len(samples) * SAMPLE_RATE / source_rate))
        new_x = np.linspace(0.0, 1.0, new_length, endpoint=False)
        samples = np.column_stack(
            [np.interp(new_x, old_x, samples[:, channel]) for channel in range(2)]
        ).astype(np.float32)
    return samples


def add_clip(
    mix: np.ndarray,
    path: Path,
    start: float,
    gain: float = 1.0,
    duration: float | None = None,
    pan: float = 0.0,
) -> None:
    clip = read_wave(path)
    if duration is not None:
        clip = clip[: int(duration * SAMPLE_RATE)]
    left_gain = gain * math.sqrt((1.0 - pan) / 2.0) * math.sqrt(2.0)
    right_gain = gain * math.sqrt((1.0 + pan) / 2.0) * math.sqrt(2.0)
    clip *= np.array([left_gain, right_gain], dtype=np.float32)
    offset = int(start * SAMPLE_RATE)
    available = min(len(clip), len(mix) - offset)
    if available > 0:
        mix[offset : offset + available] += clip[:available]


def add_transition_hit(mix: np.ndarray, start: float, frequency: float) -> None:
    length = int(0.7 * SAMPLE_RATE)
    local_time = np.arange(length, dtype=np.float32) / SAMPLE_RATE
    envelope = np.exp(-local_time * 7.2)
    signal = (
        np.sin(2 * np.pi * frequency * local_time)
        + 0.32 * np.sin(2 * np.pi * frequency * 2.01 * local_time)
    ) * envelope * 0.10
    offset = int(start * SAMPLE_RATE)
    available = min(length, len(mix) - offset)
    if available > 0:
        mix[offset : offset + available, 0] += signal[:available] * 0.92
        mix[offset : offset + available, 1] += signal[:available]


def build_pad() -> np.ndarray:
    time = np.arange(FRAME_COUNT, dtype=np.float32) / SAMPLE_RATE
    pad = np.zeros((FRAME_COUNT, 2), dtype=np.float32)
    progression = [
        (0.0, 4.2, [65.41, 98.00, 155.56]),
        (4.2, 9.4, [73.42, 110.00, 174.61]),
        (9.4, 14.8, [58.27, 87.31, 146.83]),
        (14.8, 21.0, [65.41, 103.83, 155.56]),
        (21.0, 25.7, [55.00, 82.41, 130.81]),
        (25.7, DURATION, [65.41, 98.00, 196.00]),
    ]
    for start, end, frequencies in progression:
        first = int(start * SAMPLE_RATE)
        last = min(FRAME_COUNT, int(end * SAMPLE_RATE))
        local_time = time[first:last] - start
        count = max(1, last - first)
        fade = np.minimum(np.linspace(0, 1, count), np.linspace(1, 0, count))
        fade = np.clip(fade * 6.0, 0.0, 1.0)
        chord = np.zeros(count, dtype=np.float32)
        for index, frequency in enumerate(frequencies):
            chord += np.sin(2 * np.pi * frequency * local_time + index * 0.66) / (index + 1)
        chord *= (0.021 + 0.004 * np.sin(2 * np.pi * 0.2 * local_time)) * fade
        stereo_drift = 0.11 * np.sin(2 * np.pi * 0.055 * local_time)
        pad[first:last, 0] += chord * (1.0 - stereo_drift)
        pad[first:last, 1] += chord * (1.0 + stereo_drift)
    return pad


def main() -> None:
    random.seed(27)
    mix = build_pad()
    sounds = ROOT / "Tappy/Resources/BundledSounds"

    plastic = sorted((sounds / "default").glob("*.wav"))
    wood_sand = sorted((sounds / "farming/default").glob("*.wav"))
    squishy = sorted((sounds / "studio-mix/default").glob("*.wav"))
    wax = sorted((sounds / "wax-cracking/default").glob("*.wav"))
    bubbles = sorted((sounds / "bubble/default").glob("*.wav"))
    ticks = sorted((sounds / "analog-stopwatch/default").glob("*.wav"))
    stars = sorted((sounds / "stars/default").glob("*.wav"))
    brush = sorted((sounds / "wood-brush/default").glob("*.wav"))

    for start in [0.72, 1.18, 1.64]:
        add_clip(mix, random.choice(plastic), start, gain=0.84, pan=random.uniform(-0.26, 0.26))

    for start, source, gain in [
        (5.35, plastic, 0.72),
        (6.15, wood_sand, 0.64),
        (7.38, squishy, 0.55),
    ]:
        for beat in range(4):
            add_clip(mix, random.choice(source), start + beat * 0.14, gain=gain, pan=random.uniform(-0.36, 0.36))

    typed = "Typing should feel as good as it looks"
    for index, character in enumerate(typed):
        if character != " ":
            add_clip(
                mix,
                random.choice(plastic),
                10.56 + index * 0.082,
                gain=0.70,
                pan=random.uniform(-0.34, 0.34),
            )

    showcases = [
        (15.52, plastic, 0.72),
        (16.78, wood_sand, 0.62),
        (18.06, squishy, 0.54),
        (19.34, wax, 0.54),
    ]
    for base, source, gain in showcases:
        for beat in range(5):
            add_clip(mix, random.choice(source), base + beat * 0.145, gain=gain, pan=random.uniform(-0.43, 0.43))

    library_sources = [plastic, wood_sand, squishy, wax, bubbles, ticks, stars, brush]
    for index, source in enumerate(library_sources):
        base = 21.62 + index * 0.43
        for beat in range(2):
            add_clip(mix, random.choice(source), base + beat * 0.13, gain=0.43, pan=random.uniform(-0.38, 0.38))

    for start in [4.2, 9.4, 14.8, 21.0, 25.7]:
        add_transition_hit(mix, start, 88.0 if start < 15 else 104.0)

    add_clip(mix, sounds / "stars/demo/demo.wav", 26.32, gain=0.27, duration=1.8)
    add_clip(mix, sounds / "studio-mix/demo/demo.wav", 28.4, gain=0.16, duration=1.2)

    fade_in = np.clip(np.arange(FRAME_COUNT) / (0.2 * SAMPLE_RATE), 0.0, 1.0)
    fade_out = np.clip((FRAME_COUNT - np.arange(FRAME_COUNT)) / (0.75 * SAMPLE_RATE), 0.0, 1.0)
    mix *= (fade_in * fade_out)[:, None]
    mix = np.tanh(mix * 1.08)
    peak = float(np.max(np.abs(mix)))
    if peak > 0:
        mix *= 0.91 / peak

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(mix * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(str(OUTPUT), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())
    print(OUTPUT)


if __name__ == "__main__":
    main()
