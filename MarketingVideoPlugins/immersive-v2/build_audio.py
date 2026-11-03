#!/usr/bin/env python3
from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path("/Users/castao/Desktop/Tappy")
SOUNDS = ROOT / "Tappy/Resources/BundledSounds"
OUTPUT = ROOT / "MarketingVideoPlugins/immersive-v2/audio/tappy-immersive-v2.wav"
SAMPLE_RATE = 48_000
DURATION = 16.0


PACKS = {
    "bubble": [
        SOUNDS / "bubble/default/default-01.wav",
        SOUNDS / "bubble/default/default-02.wav",
        SOUNDS / "bubble/default/default-03.wav",
        SOUNDS / "bubble/default/default-04.wav",
    ],
    "wet": [
        SOUNDS / "studio-mix/default/jackson-ave-06_t0024.210_score4311.wav",
        SOUNDS / "studio-mix/default/new-recording-08_t0033.715_score5606.wav",
        SOUNDS / "studio-mix/default/jackson-ave-13_t0059.185_score6210.wav",
        SOUNDS / "studio-mix/default/new-recording-21_t0066.810_score5106.wav",
    ],
    "wax": [
        SOUNDS / "wax-cracking/default/08_t0008.600_score11730.wav",
        SOUNDS / "wax-cracking/default/16_t0025.820_score12872.wav",
        SOUNDS / "wax-cracking/default/24_t0037.345_score10528.wav",
        SOUNDS / "wax-cracking/default/35_t0055.965_score10466.wav",
    ],
    "mechanical": [
        SOUNDS / "analog-stopwatch/default/default-01.wav",
        SOUNDS / "analog-stopwatch/default/default-02.wav",
        SOUNDS / "analog-stopwatch/default/default-04.wav",
        SOUNDS / "analog-stopwatch/default/default-05.wav",
    ],
}


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        rate = source.getframerate()
        frames = source.readframes(source.getnframes())

    if width != 2:
        raise ValueError(f"Expected 16-bit PCM: {path}")

    audio = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    audio = audio.reshape(-1, channels)
    if channels == 1:
        audio = np.repeat(audio, 2, axis=1)
    elif channels > 2:
        audio = audio[:, :2]

    if rate != SAMPLE_RATE:
        output_length = max(1, round(len(audio) * SAMPLE_RATE / rate))
        source_positions = np.linspace(0, len(audio) - 1, output_length)
        original_positions = np.arange(len(audio))
        audio = np.column_stack(
            [
                np.interp(source_positions, original_positions, audio[:, channel])
                for channel in range(2)
            ]
        )

    return audio


def normalize(audio: np.ndarray, peak: float = 1.0) -> np.ndarray:
    current = float(np.max(np.abs(audio)))
    return audio if current == 0 else audio * (peak / current)


def fade_clip(audio: np.ndarray, fade_out: float = 0.025) -> np.ndarray:
    result = audio.copy()
    fade_in_samples = min(len(result), max(1, round(0.002 * SAMPLE_RATE)))
    fade_out_samples = min(len(result), max(1, round(fade_out * SAMPLE_RATE)))
    result[:fade_in_samples] *= np.linspace(0.0, 1.0, fade_in_samples)[:, None]
    result[-fade_out_samples:] *= np.linspace(1.0, 0.0, fade_out_samples)[:, None]
    return result


def add_clip(
    master: np.ndarray,
    audio: np.ndarray,
    at: float,
    gain: float,
    pan: float = 0.0,
) -> None:
    start = round(at * SAMPLE_RATE)
    if start < 0 or start >= len(master):
        return

    end = min(len(master), start + len(audio))
    clip = audio[: end - start].copy()
    pan = max(-1.0, min(1.0, pan))
    clip[:, 0] *= math.cos((pan + 1.0) * math.pi / 4.0) * math.sqrt(2.0)
    clip[:, 1] *= math.sin((pan + 1.0) * math.pi / 4.0) * math.sqrt(2.0)
    master[start:end] += clip * gain


def make_ambient() -> np.ndarray:
    count = round(DURATION * SAMPLE_RATE)
    time = np.arange(count) / SAMPLE_RATE
    chord = (
        np.sin(2 * math.pi * 73.42 * time)
        + 0.32 * np.sin(2 * math.pi * 110.0 * time)
        + 0.17 * np.sin(2 * math.pi * 146.83 * time)
    )
    sway = 0.74 + 0.26 * np.sin(2 * math.pi * 0.06 * time - math.pi / 2)
    mono = normalize(chord * sway, 0.13)
    right = np.roll(mono, round(0.01 * SAMPLE_RATE))
    stereo = np.column_stack([mono, right])
    fade = np.ones(count)
    edge = round(0.8 * SAMPLE_RATE)
    fade[:edge] = np.linspace(0.0, 1.0, edge)
    fade[-edge:] = np.linspace(1.0, 0.0, edge)
    return stereo * fade[:, None]


def make_whoosh(duration: float, seed: int, direction: int) -> np.ndarray:
    count = max(1, round(duration * SAMPLE_RATE))
    rng = np.random.default_rng(seed)
    noise = rng.normal(0.0, 1.0, count)
    smooth = np.convolve(noise, np.ones(48) / 48, mode="same")
    envelope = np.sin(np.linspace(0.0, math.pi, count)) ** 2
    sweep = np.linspace(0.35, 1.0, count) if direction > 0 else np.linspace(1.0, 0.35, count)
    mono = normalize(smooth * envelope * sweep, 0.45)
    right = np.roll(mono, round(0.008 * SAMPLE_RATE))
    return np.column_stack([mono, right])


def make_neutral_tap(frequency: float, duration: float = 0.13) -> np.ndarray:
    count = max(1, round(duration * SAMPLE_RATE))
    time = np.arange(count) / SAMPLE_RATE
    pitch = frequency * (1.0 + 0.9 * np.exp(-time * 36.0))
    phase = 2 * math.pi * np.cumsum(pitch) / SAMPLE_RATE
    envelope = np.exp(-time * 28.0) * np.sin(np.minimum(1.0, time / 0.014) * math.pi / 2)
    mono = normalize(np.sin(phase) * envelope, 0.55)
    right = np.roll(mono, round(0.004 * SAMPLE_RATE))
    return np.column_stack([mono, right])


def add_neutral_tail(master: np.ndarray, at: float, frequency: float, gain: float) -> None:
    tap = make_neutral_tap(frequency)
    add_clip(master, tap, at, gain, 0.0)
    add_clip(master, tap, at + 0.11, gain * 0.16, -0.18)
    add_clip(master, tap, at + 0.25, gain * 0.07, 0.16)


def rapid_word(
    master: np.ndarray,
    library: list[np.ndarray],
    start: float,
    count: int,
    spacing: float,
    gain: float,
    offset: int,
) -> None:
    pan_pattern = (-0.18, 0.1, -0.05, 0.2, -0.12, 0.04, 0.16, -0.08)
    for index in range(count):
        clip = library[(index + offset) % len(library)]
        pan = pan_pattern[(index + offset) % len(pan_pattern)]
        add_clip(master, clip, start + index * spacing, gain, pan)


def main() -> None:
    master = np.zeros((round(DURATION * SAMPLE_RATE), 2), dtype=np.float64)
    libraries = {
        name: [fade_clip(normalize(read_wav(path))) for path in paths]
        for name, paths in PACKS.items()
    }

    add_clip(master, make_ambient(), 0.0, 0.048)

    # The original restrained logo click, synthesized so no keyboard pack repeats.
    add_neutral_tail(master, 0.34, 176.0, 0.2)
    add_clip(master, make_neutral_tap(126.0, 0.19), 0.56, 0.055)

    # Bubbles: three natural, uninterrupted message bursts.
    add_clip(master, make_whoosh(0.22, 801, 1), 0.98, 0.038)
    rapid_word(master, libraries["bubble"], 1.15, 7, 0.1, 0.31, 0)
    rapid_word(master, libraries["bubble"], 1.95, 8, 0.095, 0.31, 1)
    rapid_word(master, libraries["bubble"], 2.85, 7, 0.105, 0.31, 2)

    # Wet Squishy Pop appears once and gets a complete 2.5-second passage.
    add_clip(master, make_whoosh(0.28, 802, -1), 3.64, 0.045)
    rapid_word(master, libraries["wet"], 3.9, 7, 0.105, 0.49, 0)
    rapid_word(master, libraries["wet"], 4.72, 7, 0.1, 0.5, 1)
    rapid_word(master, libraries["wet"], 5.55, 7, 0.105, 0.49, 2)

    # Wax Cracking enters with a blended air transition, then stays uninterrupted.
    add_clip(master, make_whoosh(0.3, 803, 1), 6.38, 0.044)
    rapid_word(master, libraries["wax"], 6.65, 7, 0.105, 0.56, 0)
    rapid_word(master, libraries["wax"], 7.47, 7, 0.1, 0.56, 1)
    rapid_word(master, libraries["wax"], 8.3, 7, 0.105, 0.55, 2)

    # Mechanical Ticks is the final keyboard and does not reappear after it stops.
    add_clip(master, make_whoosh(0.28, 804, -1), 9.16, 0.04)
    rapid_word(master, libraries["mechanical"], 9.4, 8, 0.095, 0.45, 0)
    rapid_word(master, libraries["mechanical"], 10.22, 8, 0.095, 0.45, 1)
    rapid_word(master, libraries["mechanical"], 11.04, 7, 0.1, 0.46, 2)

    # Neutral UI sounds carry the logo and App Store ending without repeating a pack.
    add_neutral_tail(master, 11.8, 152.0, 0.22)
    add_clip(master, make_whoosh(0.3, 805, 1), 12.55, 0.027)
    add_neutral_tail(master, 13.72, 118.0, 0.13)
    add_neutral_tail(master, 14.62, 202.0, 0.11)

    master = np.tanh(master * 1.24)
    peak = float(np.max(np.abs(master)))
    if peak > 0.76:
        master *= 0.76 / peak
    encoded = np.round(np.clip(master, -1.0, 1.0) * 32767.0).astype("<i2")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.writeframes(encoded.tobytes())

    rms = math.sqrt(float(np.mean(master * master)))
    print(
        f"immersive-v2: {DURATION:.2f}s peak={np.max(np.abs(master)):.4f} "
        f"rms={rms:.4f} path={OUTPUT}"
    )


if __name__ == "__main__":
    main()
