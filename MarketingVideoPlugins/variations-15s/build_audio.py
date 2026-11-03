#!/usr/bin/env python3
from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path("/Users/castao/Desktop/Tappy")
SOUNDS = ROOT / "Tappy/Resources/BundledSounds"
OUTPUT = ROOT / "MarketingVideoPlugins/variations-15s/audio"
SAMPLE_RATE = 48_000
DURATION = 15.0

WET_PATHS = [
    SOUNDS / "studio-mix/default/jackson-ave-06_t0024.210_score4311.wav",
    SOUNDS / "studio-mix/default/new-recording-08_t0033.715_score5606.wav",
    SOUNDS / "studio-mix/default/jackson-ave-13_t0059.185_score6210.wav",
    SOUNDS / "studio-mix/default/new-recording-21_t0066.810_score5106.wav",
]

WAX_PATHS = [
    SOUNDS / "wax-cracking/default/08_t0008.600_score11730.wav",
    SOUNDS / "wax-cracking/default/16_t0025.820_score12872.wav",
    SOUNDS / "wax-cracking/default/24_t0037.345_score10528.wav",
    SOUNDS / "wax-cracking/default/35_t0055.965_score10466.wav",
]


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


def add_hit(
    master: np.ndarray,
    audio: np.ndarray,
    at: float,
    gain: float,
    pan: float,
    echo: float,
) -> None:
    add_clip(master, audio, at, gain, pan)
    add_clip(master, audio, at + 0.036, gain * echo, -pan * 0.42)
    add_clip(master, audio, at + 0.078, gain * echo * 0.28, pan * 0.18)


def make_air(seed: int) -> np.ndarray:
    count = round(DURATION * SAMPLE_RATE)
    rng = np.random.default_rng(seed)
    noise = rng.normal(0.0, 1.0, count)
    kernel = np.ones(180, dtype=np.float64) / 180
    air = np.convolve(noise, kernel, mode="same")
    time = np.arange(count) / SAMPLE_RATE
    sway = 0.52 + 0.48 * np.sin(2 * math.pi * 0.065 * time - math.pi / 2) ** 2
    mono = normalize(air * sway, 0.3)
    right = np.roll(mono, round(0.011 * SAMPLE_RATE))
    fade = np.ones(count)
    fade_length = round(0.9 * SAMPLE_RATE)
    fade[:fade_length] = np.linspace(0, 1, fade_length)
    fade[-fade_length:] = np.linspace(1, 0, fade_length)
    return np.column_stack([mono, right]) * fade[:, None]


def make_tone(frequencies: tuple[float, float, float]) -> np.ndarray:
    count = round(DURATION * SAMPLE_RATE)
    time = np.arange(count) / SAMPLE_RATE
    signal = sum(
        weight * np.sin(2 * math.pi * frequency * time)
        for frequency, weight in zip(frequencies, (1.0, 0.34, 0.16), strict=True)
    )
    sway = 0.6 + 0.4 * np.sin(2 * math.pi * 0.075 * time - math.pi / 2)
    mono = normalize(signal * sway, 0.22)
    right = np.roll(mono, round(0.006 * SAMPLE_RATE))
    fade = np.ones(count)
    fade_length = round(0.85 * SAMPLE_RATE)
    fade[:fade_length] = np.linspace(0, 1, fade_length)
    fade[-fade_length:] = np.linspace(1, 0, fade_length)
    return np.column_stack([mono, right]) * fade[:, None]


def render_track(
    name: str,
    events: list[tuple[str, int, float, float, float]],
    tone: tuple[float, float, float],
    seed: int,
) -> None:
    master = np.zeros((round(DURATION * SAMPLE_RATE), 2), dtype=np.float64)
    wet = [normalize(read_wav(path)) for path in WET_PATHS]
    wax = [normalize(read_wav(path)) for path in WAX_PATHS]
    toggle = normalize(read_wav(SOUNDS / "default/default-03.wav"))

    add_clip(master, make_air(seed), 0, 0.035)
    add_clip(master, make_tone(tone), 0, 0.022)

    for kind, index, at, gain, pan in events:
        if kind == "wet":
            add_hit(master, wet[index % len(wet)], at, gain, pan, echo=0.1)
        elif kind == "wax":
            add_hit(master, wax[index % len(wax)], at, gain, pan, echo=0.055)
        elif kind == "toggle":
            add_clip(master, toggle, at, gain, pan)
        else:
            raise ValueError(f"Unknown event kind: {kind}")

    master = np.tanh(master * 1.06)
    master = normalize(master, 0.88)
    encoded = np.round(np.clip(master, -1.0, 1.0) * 32767.0).astype("<i2")

    path = OUTPUT / f"tappy-{name}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.writeframes(encoded.tobytes())

    rms = math.sqrt(float(np.mean(master * master)))
    print(f"{name}: {DURATION:.2f}s peak={np.max(np.abs(master)):.4f} rms={rms:.4f} path={path}")


def main() -> None:
    editorial = [
        ("wet", 0, 0.8, 0.36, -0.18),
        ("wet", 1, 1.55, 0.38, 0.18),
        ("wax", 0, 2.35, 0.32, -0.06),
        ("toggle", 0, 3.15, 0.22, 0.0),
        ("wet", 2, 3.7, 0.58, -0.24),
        ("wet", 3, 4.35, 0.6, 0.14),
        ("wet", 0, 5.05, 0.58, -0.1),
        ("wet", 1, 5.8, 0.62, 0.22),
        ("toggle", 0, 6.72, 0.15, 0.0),
        ("wet", 3, 7.2, 0.62, -0.24),
        ("wax", 2, 8.0, 0.7, 0.18),
        ("wax", 3, 8.85, 0.66, -0.1),
        ("wax", 0, 9.7, 0.72, 0.2),
        ("wet", 2, 11.82, 0.42, -0.16),
        ("wax", 2, 12.58, 0.43, 0.14),
        ("wet", 3, 13.32, 0.46, -0.08),
        ("wax", 1, 14.12, 0.5, 0.08),
    ]

    texture = [
        ("wet", 0, 0.92, 0.42, -0.2),
        ("wet", 1, 1.92, 0.48, 0.18),
        ("wet", 2, 3.05, 0.6, -0.14),
        ("wet", 3, 4.15, 0.66, 0.2),
        ("wet", 0, 5.18, 0.62, -0.18),
        ("wet", 1, 6.08, 0.68, 0.14),
        ("toggle", 0, 6.72, 0.14, 0.0),
        ("wax", 0, 7.18, 0.68, -0.22),
        ("wax", 1, 7.98, 0.72, 0.2),
        ("wax", 2, 8.78, 0.68, -0.12),
        ("wax", 3, 9.58, 0.74, 0.18),
        ("wax", 0, 10.38, 0.7, -0.18),
        ("wax", 1, 11.18, 0.76, 0.12),
        ("wet", 2, 12.25, 0.45, -0.12),
        ("wax", 2, 13.05, 0.48, 0.12),
        ("wet", 3, 14.0, 0.52, 0.0),
    ]

    ritual = [
        ("wet", 0, 0.8, 0.38, -0.22),
        ("wet", 1, 1.38, 0.4, 0.18),
        ("wet", 2, 1.98, 0.42, -0.12),
        ("toggle", 0, 2.72, 0.24, 0.0),
        ("wet", 3, 3.32, 0.58, 0.2),
        ("wet", 0, 4.08, 0.62, -0.18),
        ("wax", 0, 5.0, 0.64, -0.2),
        ("wax", 1, 5.8, 0.68, 0.18),
        ("wax", 2, 6.62, 0.66, -0.08),
        ("wax", 3, 7.45, 0.7, 0.2),
        ("wet", 1, 8.2, 0.6, -0.18),
        ("wet", 2, 9.0, 0.62, 0.14),
        ("wax", 0, 9.82, 0.66, -0.12),
        ("wax", 1, 10.62, 0.7, 0.18),
        ("wet", 3, 12.0, 0.44, -0.16),
        ("wax", 2, 12.8, 0.46, 0.14),
        ("wet", 0, 13.58, 0.48, -0.08),
        ("wax", 3, 14.3, 0.52, 0.08),
    ]

    render_track("editorial", editorial, (110.0, 164.81, 220.0), 20260717)
    render_track("texture-study", texture, (82.41, 123.47, 196.0), 20260718)
    render_track("menu-ritual", ritual, (98.0, 146.83, 196.0), 20260719)


if __name__ == "__main__":
    main()
