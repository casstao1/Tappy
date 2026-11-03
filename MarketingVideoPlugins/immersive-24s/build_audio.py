#!/usr/bin/env python3
from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path("/Users/castao/Desktop/Tappy")
SOUNDS = ROOT / "Tappy/Resources/BundledSounds"
OUTPUT = ROOT / "MarketingVideoPlugins/immersive-24s/audio/tappy-immersive-24s.wav"
SAMPLE_RATE = 48_000
DURATION = 24.0


PACKS = {
    "plastic": [
        SOUNDS / "default/default-01.wav",
        SOUNDS / "default/default-02.wav",
        SOUNDS / "default/default-04.wav",
        SOUNDS / "default/default-06.wav",
    ],
    "bubble": [
        SOUNDS / "bubble/default/default-01.wav",
        SOUNDS / "bubble/default/default-02.wav",
        SOUNDS / "bubble/default/default-03.wav",
        SOUNDS / "bubble/default/default-04.wav",
    ],
    "wood": [
        SOUNDS / "farming/default/default-01.wav",
        SOUNDS / "farming/default/default-02.wav",
        SOUNDS / "wood-brush/default/default-02.wav",
    ],
    "mechanical": [
        SOUNDS / "analog-stopwatch/default/default-01.wav",
        SOUNDS / "analog-stopwatch/default/default-02.wav",
        SOUNDS / "analog-stopwatch/default/default-04.wav",
        SOUNDS / "analog-stopwatch/default/default-05.wav",
    ],
    "star": [
        SOUNDS / "stars/default/default-01.wav",
        SOUNDS / "stars/default/default-02.wav",
        SOUNDS / "stars/modifier/modifier-01.wav",
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


def fade_clip(audio: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.035) -> np.ndarray:
    result = audio.copy()
    fade_in_samples = min(len(result), max(1, round(fade_in * SAMPLE_RATE)))
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
        + 0.38 * np.sin(2 * math.pi * 110.0 * time)
        + 0.2 * np.sin(2 * math.pi * 146.83 * time)
        + 0.1 * np.sin(2 * math.pi * 220.0 * time)
    )
    sway = 0.72 + 0.28 * np.sin(2 * math.pi * 0.055 * time - math.pi / 2)
    mono = normalize(chord * sway, 0.16)
    right = np.roll(mono, round(0.009 * SAMPLE_RATE))
    stereo = np.column_stack([mono, right])
    fade = np.ones(count)
    edge = round(1.0 * SAMPLE_RATE)
    fade[:edge] = np.linspace(0.0, 1.0, edge)
    fade[-edge:] = np.linspace(1.0, 0.0, edge)
    return stereo * fade[:, None]


def make_whoosh(duration: float = 0.24, seed: int = 0, direction: int = 1) -> np.ndarray:
    count = max(1, round(duration * SAMPLE_RATE))
    rng = np.random.default_rng(seed)
    noise = rng.normal(0.0, 1.0, count)
    kernel = np.ones(36, dtype=np.float64) / 36
    smooth = np.convolve(noise, kernel, mode="same")
    envelope = np.sin(np.linspace(0.0, math.pi, count)) ** 2
    sweep = np.linspace(0.22, 1.0, count) if direction > 0 else np.linspace(1.0, 0.22, count)
    mono = normalize(smooth * envelope * sweep, 0.55)
    delayed = np.roll(mono, round(0.008 * SAMPLE_RATE))
    return np.column_stack([mono, delayed])


def make_air_pop(frequency: float = 180.0, duration: float = 0.16) -> np.ndarray:
    count = max(1, round(duration * SAMPLE_RATE))
    time = np.arange(count) / SAMPLE_RATE
    pitch = frequency * (1.0 + 1.6 * np.exp(-time * 40.0))
    phase = 2 * math.pi * np.cumsum(pitch) / SAMPLE_RATE
    envelope = np.exp(-time * 25.0) * np.sin(np.minimum(1.0, time / 0.018) * math.pi / 2)
    mono = normalize(np.sin(phase) * envelope, 0.72)
    right = np.roll(mono, round(0.004 * SAMPLE_RATE))
    return np.column_stack([mono, right])


def add_reverb_tail(master: np.ndarray, clip: np.ndarray, at: float, gain: float) -> None:
    add_clip(master, clip, at, gain, 0.0)
    for delay, level, pan in (
        (0.09, 0.2, -0.2),
        (0.19, 0.12, 0.24),
        (0.34, 0.07, -0.12),
        (0.55, 0.035, 0.14),
    ):
        add_clip(master, clip, at + delay, gain * level, pan)


def rapid_word(
    master: np.ndarray,
    library: list[np.ndarray],
    start: float,
    count: int,
    spacing: float,
    gain: float,
    seed: int,
) -> None:
    rng = np.random.default_rng(seed)
    for index in range(count):
        jitter = float(rng.uniform(-0.009, 0.009))
        pan = float(rng.uniform(-0.24, 0.24))
        clip = library[(index + seed) % len(library)]
        add_clip(master, clip, start + index * spacing + jitter, gain, pan)


def main() -> None:
    master = np.zeros((round(DURATION * SAMPLE_RATE), 2), dtype=np.float64)
    libraries = {
        name: [fade_clip(normalize(read_wav(path))) for path in paths]
        for name, paths in PACKS.items()
    }

    add_clip(master, make_ambient(), 0.0, 0.055)

    # Logo reveal and the first human typing sequence.
    add_reverb_tail(master, libraries["mechanical"][0], 0.34, 0.42)
    add_clip(master, make_air_pop(132.0), 0.56, 0.1)
    rapid_word(master, libraries["plastic"], 1.28, 7, 0.105, 0.37, 11)
    rapid_word(master, libraries["plastic"], 2.18, 6, 0.098, 0.39, 21)
    rapid_word(master, libraries["plastic"], 3.02, 8, 0.094, 0.4, 31)

    # Six sound worlds. Each transition and key press has its own tactile event.
    worlds = [
        ("bubble", 4.20, 5, 0.135, 0.39),
        ("wet", 5.10, 5, 0.14, 0.48),
        ("wax", 6.00, 5, 0.14, 0.5),
        ("wood", 6.90, 5, 0.132, 0.3),
        ("mechanical", 7.80, 6, 0.115, 0.38),
        ("star", 8.70, 5, 0.13, 0.35),
    ]
    for index, (name, start, count, spacing, gain) in enumerate(worlds):
        add_clip(master, make_whoosh(0.18, 100 + index, 1 if index % 2 == 0 else -1), start - 0.06, 0.06)
        rapid_word(master, libraries[name], start, count, spacing, gain, 50 + index)

    # Macro keycap, return key, and fingertip shots.
    macro_events = [
        ("mechanical", 9.63, 0, 0.5),
        ("plastic", 9.92, 1, 0.48),
        ("wet", 10.25, 2, 0.54),
        ("wax", 10.62, 0, 0.52),
        ("mechanical", 11.03, 2, 0.48),
        ("wood", 11.42, 1, 0.48),
        ("bubble", 11.82, 3, 0.44),
        ("plastic", 12.18, 2, 0.46),
    ]
    for index, (name, at, clip_index, gain) in enumerate(macro_events):
        add_clip(master, libraries[name][clip_index % len(libraries[name])], at, gain, -0.18 + (index % 3) * 0.18)

    # Menu-bar customization: open, pack, color, volume, toggle.
    add_clip(master, make_whoosh(0.26, 401, 1), 12.52, 0.085)
    add_clip(master, libraries["wet"][3], 13.05, 0.36, -0.12)
    add_clip(master, libraries["wax"][1], 13.68, 0.32, 0.14)
    add_clip(master, make_air_pop(220.0), 14.05, 0.08)
    add_clip(master, make_whoosh(0.3, 402, -1), 14.37, 0.055)
    add_clip(master, libraries["mechanical"][3], 15.03, 0.36, 0.0)

    # A quick conversation montage, changing sound profile on each phrase.
    montage = [
        ("bubble", 15.62, 7, 0.09, 0.34),
        ("wet", 16.42, 6, 0.1, 0.45),
        ("wood", 17.22, 7, 0.092, 0.27),
        ("mechanical", 18.02, 7, 0.088, 0.34),
        ("wax", 18.82, 6, 0.1, 0.46),
        ("plastic", 19.62, 6, 0.096, 0.38),
    ]
    for index, (name, start, count, spacing, gain) in enumerate(montage):
        add_clip(master, make_whoosh(0.14, 500 + index, 1 if index % 2 else -1), start - 0.045, 0.035)
        rapid_word(master, libraries[name], start, count, spacing, gain, 70 + index)

    # Stop, one final click, and a quiet reverberant CTA.
    final_click = libraries["mechanical"][1]
    add_reverb_tail(master, final_click, 20.48, 0.56)
    add_clip(master, make_air_pop(118.0, 0.24), 20.78, 0.095)
    add_clip(master, make_whoosh(0.32, 601, 1), 21.32, 0.045)
    add_clip(master, libraries["bubble"][1], 22.28, 0.27, 0.0)
    add_reverb_tail(master, libraries["wax"][2], 22.94, 0.31)

    master = np.tanh(master * 1.25)
    peak = float(np.max(np.abs(master)))
    if peak > 0.9:
        master *= 0.9 / peak
    encoded = np.round(np.clip(master, -1.0, 1.0) * 32767.0).astype("<i2")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.writeframes(encoded.tobytes())

    rms = math.sqrt(float(np.mean(master * master)))
    print(
        f"immersive: {DURATION:.2f}s peak={np.max(np.abs(master)):.4f} "
        f"rms={rms:.4f} path={OUTPUT}"
    )


if __name__ == "__main__":
    main()
