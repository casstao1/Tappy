#!/usr/bin/env python3

from __future__ import annotations

import math
import random
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(__file__).resolve().parent / "Tappy-Promo-Audio.wav"
SAMPLE_RATE = 48_000
DURATION = 31.5
FRAME_COUNT = int(SAMPLE_RATE * DURATION)


def read_wave(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        sample_width = handle.getsampwidth()
        source_rate = handle.getframerate()
        frame_count = handle.getnframes()
        raw = handle.readframes(frame_count)
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
        samples = np.column_stack([np.interp(new_x, old_x, samples[:, channel]) for channel in range(2)]).astype(np.float32)
    return samples


def add_clip(mix: np.ndarray, path: Path, start: float, gain=1.0, duration: float | None = None, pan=0.0) -> None:
    clip = read_wave(path)
    if duration is not None:
        clip = clip[: int(duration * SAMPLE_RATE)]
    left_gain = gain * math.sqrt((1.0 - pan) / 2.0) * math.sqrt(2.0)
    right_gain = gain * math.sqrt((1.0 + pan) / 2.0) * math.sqrt(2.0)
    clip = clip * np.array([left_gain, right_gain], dtype=np.float32)
    offset = int(start * SAMPLE_RATE)
    if offset >= len(mix):
        return
    available = min(len(clip), len(mix) - offset)
    mix[offset : offset + available] += clip[:available]


def add_soft_hit(mix: np.ndarray, start: float, frequency: float, gain=0.11) -> None:
    length = int(0.65 * SAMPLE_RATE)
    time = np.arange(length, dtype=np.float32) / SAMPLE_RATE
    envelope = np.exp(-time * 7.0)
    signal = (np.sin(2 * np.pi * frequency * time) + 0.35 * np.sin(2 * np.pi * frequency * 2.01 * time)) * envelope * gain
    offset = int(start * SAMPLE_RATE)
    available = min(length, len(mix) - offset)
    if available > 0:
        mix[offset : offset + available, 0] += signal[:available] * 0.94
        mix[offset : offset + available, 1] += signal[:available]


def build_pad() -> np.ndarray:
    time = np.arange(FRAME_COUNT, dtype=np.float32) / SAMPLE_RATE
    pad = np.zeros((FRAME_COUNT, 2), dtype=np.float32)
    progression = [
        (0.0, 6.2, [65.41, 98.00, 155.56]),
        (6.2, 12.2, [73.42, 110.00, 174.61]),
        (12.2, 18.0, [58.27, 87.31, 146.83]),
        (18.0, 24.0, [65.41, 103.83, 155.56]),
        (24.0, 28.0, [55.00, 82.41, 130.81]),
        (28.0, DURATION, [65.41, 98.00, 196.00]),
    ]
    for start, end, frequencies in progression:
        first = int(start * SAMPLE_RATE)
        last = min(FRAME_COUNT, int(end * SAMPLE_RATE))
        local_time = time[first:last] - start
        length = max(1, last - first)
        fade = np.minimum(np.linspace(0, 1, length), np.linspace(1, 0, length))
        fade = np.clip(fade * 7.0, 0.0, 1.0)
        chord = np.zeros(length, dtype=np.float32)
        for index, frequency in enumerate(frequencies):
            chord += np.sin(2 * np.pi * frequency * local_time + index * 0.7) / (index + 1)
        chord *= (0.020 + 0.004 * np.sin(2 * np.pi * 0.22 * local_time)) * fade
        pan = 0.10 * np.sin(2 * np.pi * 0.06 * local_time)
        pad[first:last, 0] += chord * (1.0 - pan)
        pad[first:last, 1] += chord * (1.0 + pan)
    return pad


def main() -> None:
    random.seed(17)
    mix = build_pad()
    sounds = ROOT / "Tappy/Resources/BundledSounds"

    plastic = sorted((sounds / "default").glob("*.wav"))
    wood = sorted((sounds / "farming/default").glob("*.wav"))
    squishy = sorted((sounds / "studio-mix/default").glob("*.wav"))
    wax = sorted((sounds / "wax-cracking/default").glob("*.wav"))
    bubble = sorted((sounds / "bubble/default").glob("*.wav"))
    ticks = sorted((sounds / "analog-stopwatch/default").glob("*.wav"))

    for start in [0.72, 1.22, 1.72]:
        add_clip(mix, random.choice(plastic), start, gain=0.82, pan=random.uniform(-0.25, 0.25))

    typed = "What if every key felt this satisfying?"
    for index, character in enumerate(typed):
        if character != " ":
            add_clip(mix, random.choice(plastic), 2.75 + index * 0.078, gain=0.70, pan=random.uniform(-0.32, 0.32))

    for start in [6.45, 9.55, 12.25, 16.35, 21.85, 25.0, 27.7]:
        add_soft_hit(mix, start, 92.0 if start < 20 else 110.0, gain=0.10)

    for index in range(30):
        source = plastic if index < 10 else wood if index < 20 else squishy
        add_clip(mix, random.choice(source), 12.75 + index * 0.105, gain=0.62, pan=random.uniform(-0.38, 0.38))

    for index, source in enumerate([plastic, wood, squishy, wax, bubble, ticks]):
        base = 16.8 + index * 0.82
        for beat in range(4):
            tactile_gain = 0.58 if source is wax or source is squishy else 0.72
            add_clip(mix, random.choice(source), base + beat * 0.16, gain=tactile_gain, pan=random.uniform(-0.45, 0.45))

    add_clip(mix, sounds / "studio-mix/demo/demo.wav", 19.35, gain=0.34, duration=1.55, pan=-0.12)
    add_clip(mix, sounds / "wax-cracking/demo/demo.wav", 21.0, gain=0.35, duration=1.55, pan=0.12)
    add_clip(mix, sounds / "stars/demo/demo.wav", 27.75, gain=0.28, duration=1.9)

    for index in range(12):
        add_clip(mix, random.choice(ticks), 24.0 + index * 0.18, gain=0.34, pan=random.uniform(-0.25, 0.25))

    fade_in = np.clip(np.arange(FRAME_COUNT) / (0.20 * SAMPLE_RATE), 0.0, 1.0)
    fade_out = np.clip((FRAME_COUNT - np.arange(FRAME_COUNT)) / (0.85 * SAMPLE_RATE), 0.0, 1.0)
    mix *= (fade_in * fade_out)[:, None]
    mix = np.tanh(mix * 1.08)
    peak = float(np.max(np.abs(mix)))
    if peak > 0:
        mix *= 0.91 / peak

    pcm = np.clip(mix * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(str(OUTPUT), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())
    print(OUTPUT)


if __name__ == "__main__":
    main()
