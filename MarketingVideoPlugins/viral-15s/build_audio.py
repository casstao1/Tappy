#!/usr/bin/env python3
from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path("/Users/castao/Desktop/Tappy")
SOUNDS = ROOT / "Tappy/Resources/BundledSounds"
OUTPUT = ROOT / "MarketingVideoPlugins/viral-15s/audio/tappy-viral-audio.wav"
SAMPLE_RATE = 48_000
DURATION = 15.0


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        sample_width = source.getsampwidth()
        sample_rate = source.getframerate()
        frames = source.readframes(source.getnframes())

    if sample_width != 2:
        raise ValueError(f"Expected 16-bit PCM: {path}")

    audio = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    audio = audio.reshape(-1, channels)
    if channels == 1:
        audio = np.repeat(audio, 2, axis=1)
    elif channels > 2:
        audio = audio[:, :2]

    if sample_rate != SAMPLE_RATE:
        output_length = max(1, round(len(audio) * SAMPLE_RATE / sample_rate))
        source_positions = np.linspace(0, len(audio) - 1, output_length)
        original_positions = np.arange(len(audio))
        audio = np.column_stack(
            [np.interp(source_positions, original_positions, audio[:, channel]) for channel in range(2)]
        )

    return audio


def normalize(audio: np.ndarray, peak: float = 1.0) -> np.ndarray:
    current = float(np.max(np.abs(audio)))
    return audio if current == 0 else audio * (peak / current)


def low_pass(audio: np.ndarray, taps: int = 39) -> np.ndarray:
    kernel = np.ones(taps, dtype=np.float64) / taps
    return np.column_stack([np.convolve(audio[:, channel], kernel, mode="same") for channel in range(2)])


def add_clip(
    master: np.ndarray,
    audio: np.ndarray,
    at: float,
    gain: float,
    pan: float = 0.0,
) -> None:
    start = round(at * SAMPLE_RATE)
    if start >= len(master):
        return

    end = min(len(master), start + len(audio))
    clip = audio[: end - start].copy()
    pan = max(-1.0, min(1.0, pan))
    clip[:, 0] *= math.cos((pan + 1.0) * math.pi / 4.0) * math.sqrt(2.0)
    clip[:, 1] *= math.sin((pan + 1.0) * math.pi / 4.0) * math.sqrt(2.0)
    master[start:end] += clip * gain


def make_thump(frequency: float = 92.0, duration: float = 0.18) -> np.ndarray:
    count = round(duration * SAMPLE_RATE)
    time = np.arange(count) / SAMPLE_RATE
    envelope = np.exp(-time * 22.0) * np.minimum(1.0, time * 180.0)
    tone = np.sin(2.0 * math.pi * frequency * time) * envelope
    return np.column_stack([tone, tone])


def make_whoosh(duration: float = 0.52) -> np.ndarray:
    count = round(duration * SAMPLE_RATE)
    rng = np.random.default_rng(20260716)
    noise = rng.normal(0.0, 1.0, count)
    kernel = np.ones(61, dtype=np.float64) / 61
    softened = np.convolve(noise, kernel, mode="same")
    time = np.arange(count) / SAMPLE_RATE
    envelope = np.sin(np.pi * np.clip(time / duration, 0, 1)) ** 2
    shimmer = np.sin(2.0 * math.pi * (180.0 * time + 520.0 * time * time)) * 0.12
    mono = normalize((softened + shimmer) * envelope, 0.9)
    delay = round(0.012 * SAMPLE_RATE)
    right = np.pad(mono, (delay, 0))[:count]
    return np.column_stack([mono, right])


def make_pad(start: float, end: float) -> np.ndarray:
    count = round((end - start) * SAMPLE_RATE)
    time = np.arange(count) / SAMPLE_RATE
    chord = (
        np.sin(2.0 * math.pi * 110.0 * time)
        + 0.48 * np.sin(2.0 * math.pi * 164.81 * time)
        + 0.32 * np.sin(2.0 * math.pi * 220.0 * time)
    )
    fade = np.ones(count)
    fade_length = min(round(0.42 * SAMPLE_RATE), count // 2)
    fade[:fade_length] = np.linspace(0, 1, fade_length)
    fade[-fade_length:] = np.linspace(1, 0, fade_length)
    left = chord * fade
    right = np.roll(chord, round(0.004 * SAMPLE_RATE)) * fade
    return normalize(np.column_stack([left, right]), 0.45)


def main() -> None:
    master = np.zeros((round(DURATION * SAMPLE_RATE), 2), dtype=np.float64)

    plastic_files = [SOUNDS / f"default/default-{index:02d}.wav" for index in range(1, 7)]
    organic_files = [SOUNDS / f"farming/default/default-{index:02d}.wav" for index in range(1, 3)]
    mechanical_files = [SOUNDS / f"analog-stopwatch/default/default-{index:02d}.wav" for index in range(1, 6)]

    plastics = [normalize(read_wav(path)) for path in plastic_files]
    organics = [normalize(read_wav(path)) for path in organic_files]
    mechanical = [normalize(read_wav(path)) for path in mechanical_files]
    dull = [normalize(low_pass(clip, 45), 0.62) for clip in plastics[:3]]
    return_key = normalize(read_wav(SOUNDS / "farming/return/return-01.wav"))
    mechanical_return = normalize(read_wav(SOUNDS / "analog-stopwatch/return/return-01.wav"))
    whoosh = make_whoosh()
    thump = make_thump()

    for index, at in enumerate([0.78, 1.67, 2.54]):
        add_clip(master, dull[index], at, 0.18, pan=(-0.18 + index * 0.18))

    add_clip(master, whoosh, 2.78, 0.48, pan=-0.22)
    add_clip(master, mechanical[0], 3.24, 0.82)
    add_clip(master, thump, 3.23, 0.28)

    fast_hits = [
        3.36, 3.49, 3.62, 3.74, 3.87, 3.99, 4.13, 4.25, 4.38,
        4.51, 4.65, 4.79, 4.92, 5.04, 5.18, 5.31, 5.44, 5.58,
        5.71, 5.84, 5.98, 6.10, 6.24, 6.37, 6.50, 6.63,
    ]
    for index, at in enumerate(fast_hits):
        pan = -0.28 + (index % 5) * 0.14
        add_clip(master, organics[index % len(organics)], at, 0.28, pan=pan)
        add_clip(master, mechanical[index % len(mechanical)], at + 0.006, 0.20, pan=-pan * 0.55)

    add_clip(master, whoosh, 6.76, 0.34, pan=0.22)
    add_clip(master, mechanical[1], 7.12, 0.56)

    for index, at in enumerate([7.34, 7.61, 7.89, 8.17, 8.43]):
        add_clip(master, plastics[index % len(plastics)], at, 0.54, pan=-0.22 + index * 0.11)

    add_clip(master, mechanical[2], 8.68, 0.66)
    add_clip(master, thump, 8.68, 0.2)
    for index, at in enumerate([8.82, 9.10, 9.38, 9.67, 9.96]):
        add_clip(master, organics[index % len(organics)], at, 0.42, pan=0.2 - index * 0.1)

    add_clip(master, mechanical[3], 10.24, 0.72)
    add_clip(master, thump, 10.23, 0.28)
    for index, at in enumerate([10.38, 10.61, 10.84, 11.08, 11.31, 11.55]):
        add_clip(master, mechanical[index % len(mechanical)], at, 0.7, pan=-0.2 + index * 0.08)
        add_clip(master, thump, at, 0.18)

    add_clip(master, whoosh, 11.76, 0.42, pan=-0.2)
    add_clip(master, make_pad(12.0, 15.0), 12.0, 0.11)

    add_clip(master, return_key, 14.44, 0.92)
    add_clip(master, mechanical_return, 14.447, 0.62)
    add_clip(master, make_thump(76.0, 0.32), 14.43, 0.54)
    add_clip(master, return_key, 14.63, 0.24, pan=0.2)
    add_clip(master, return_key, 14.81, 0.1, pan=-0.2)

    master = np.tanh(master * 1.18)
    master = normalize(master, 0.92)
    encoded = np.round(np.clip(master, -1.0, 1.0) * 32767.0).astype("<i2")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.writeframes(encoded.tobytes())

    rms = math.sqrt(float(np.mean(master * master)))
    print(f"wrote={OUTPUT}")
    print(f"duration={DURATION:.2f}s sample_rate={SAMPLE_RATE} peak={np.max(np.abs(master)):.4f} rms={rms:.4f}")


if __name__ == "__main__":
    main()
