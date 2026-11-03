#!/usr/bin/env python3
from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path("/Users/castao/Desktop/Tappy")
SOUNDS = ROOT / "Tappy/Resources/BundledSounds"
OUTPUT = ROOT / "MarketingVideoPlugins/soothing-15s/audio/tappy-soothing-audio.wav"
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


def add_clip(master: np.ndarray, audio: np.ndarray, at: float, gain: float, pan: float = 0.0) -> None:
    start = round(at * SAMPLE_RATE)
    if start >= len(master):
        return

    end = min(len(master), start + len(audio))
    clip = audio[: end - start].copy()
    pan = max(-1.0, min(1.0, pan))
    clip[:, 0] *= math.cos((pan + 1.0) * math.pi / 4.0) * math.sqrt(2.0)
    clip[:, 1] *= math.sin((pan + 1.0) * math.pi / 4.0) * math.sqrt(2.0)
    master[start:end] += clip * gain


def add_asmr_hit(
    master: np.ndarray,
    audio: np.ndarray,
    at: float,
    gain: float,
    pan: float,
    tail: float = 0.1,
) -> None:
    add_clip(master, audio, at, gain, pan)
    add_clip(master, audio, at + 0.034, gain * tail, -pan * 0.45)
    add_clip(master, audio, at + 0.072, gain * tail * 0.34, pan * 0.2)


def make_breath(duration: float = 0.62) -> np.ndarray:
    count = round(duration * SAMPLE_RATE)
    rng = np.random.default_rng(20260716)
    noise = rng.normal(0.0, 1.0, count)
    kernel = np.ones(120, dtype=np.float64) / 120
    soft = np.convolve(noise, kernel, mode="same")
    time = np.arange(count) / SAMPLE_RATE
    envelope = np.sin(np.pi * np.clip(time / duration, 0, 1)) ** 2
    mono = normalize(soft * envelope, 0.7)
    delay = round(0.009 * SAMPLE_RATE)
    right = np.pad(mono, (delay, 0))[:count]
    return np.column_stack([mono, right])


def make_ambient_bed() -> np.ndarray:
    count = round(DURATION * SAMPLE_RATE)
    time = np.arange(count) / SAMPLE_RATE
    chord = (
        np.sin(2 * math.pi * 110.0 * time)
        + 0.38 * np.sin(2 * math.pi * 164.81 * time)
        + 0.22 * np.sin(2 * math.pi * 220.0 * time)
    )
    slow = 0.65 + 0.35 * np.sin(2 * math.pi * 0.08 * time - math.pi / 2)
    left = chord * slow
    right = np.roll(chord, round(0.006 * SAMPLE_RATE)) * slow
    bed = normalize(np.column_stack([left, right]), 0.3)
    fade = np.ones(count)
    fade_length = round(0.8 * SAMPLE_RATE)
    fade[:fade_length] = np.linspace(0, 1, fade_length)
    fade[-fade_length:] = np.linspace(1, 0, fade_length)
    return bed * fade[:, None]


def main() -> None:
    master = np.zeros((round(DURATION * SAMPLE_RATE), 2), dtype=np.float64)

    wet_paths = [
        SOUNDS / "studio-mix/default/jackson-ave-06_t0024.210_score4311.wav",
        SOUNDS / "studio-mix/default/new-recording-08_t0033.715_score5606.wav",
        SOUNDS / "studio-mix/default/jackson-ave-13_t0059.185_score6210.wav",
        SOUNDS / "studio-mix/default/new-recording-21_t0066.810_score5106.wav",
    ]
    wax_paths = [
        SOUNDS / "wax-cracking/default/08_t0008.600_score11730.wav",
        SOUNDS / "wax-cracking/default/16_t0025.820_score12872.wav",
        SOUNDS / "wax-cracking/default/24_t0037.345_score10528.wav",
        SOUNDS / "wax-cracking/default/35_t0055.965_score10466.wav",
    ]

    wet = [normalize(read_wav(path)) for path in wet_paths]
    wax = [normalize(read_wav(path)) for path in wax_paths]
    toggle = normalize(read_wav(SOUNDS / "default/default-03.wav"))
    breath = make_breath()

    add_clip(master, make_ambient_bed(), 0, 0.055)

    add_asmr_hit(master, wet[0], 0.9, 0.34, -0.18)
    add_asmr_hit(master, wet[1], 1.7, 0.36, 0.2)
    add_asmr_hit(master, wax[0], 2.45, 0.3, -0.08, tail=0.07)

    add_clip(master, breath, 2.72, 0.1, -0.2)
    add_clip(master, toggle, 3.24, 0.22)
    for index, at in enumerate([3.8, 4.55, 5.35, 6.15]):
        add_asmr_hit(master, wet[index % len(wet)], at, 0.58, -0.24 + index * 0.16)

    add_clip(master, breath, 6.72, 0.09, 0.2)
    for index, at in enumerate([7.45, 8.15, 8.85]):
        add_asmr_hit(master, wet[(index + 1) % len(wet)], at, 0.64, 0.2 - index * 0.2)

    add_clip(master, toggle, 9.42, 0.16)
    for index, at in enumerate([9.75, 10.4, 11.05, 11.7]):
        add_asmr_hit(master, wax[index % len(wax)], at, 0.7, -0.24 + index * 0.16, tail=0.065)

    add_clip(master, breath, 11.72, 0.085, -0.16)
    add_asmr_hit(master, wet[3], 12.65, 0.34, -0.14)
    add_asmr_hit(master, wax[2], 13.42, 0.36, 0.14, tail=0.06)
    add_asmr_hit(master, wet[2], 14.38, 0.52, 0.0, tail=0.14)

    master = np.tanh(master * 1.08)
    master = normalize(master, 0.88)
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
