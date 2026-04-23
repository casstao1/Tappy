#!/usr/bin/env python3

from __future__ import annotations

import shutil
import sys
import wave
from array import array
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT_DIR / "wood_brush_candidates"
OUTPUT_DIR = ROOT_DIR / "wood_brush_pack_ready"
RESOURCE_DIR = ROOT_DIR / "Tappy" / "Resources" / "BundledSounds" / "wood-brush"
GROUP = "masirez-wooden-whoosh-sound-effect-swiping-on-wood-298724"

PACK_SELECTION = {
    "default": [
        "02_t0001.945_manual.wav",
        "03_t0003.247_manual.wav",
        "04_t0004.445_manual.wav",
        "05_t0005.629_manual.wav",
        "06_t0006.983_manual.wav",
    ],
    "space": [
        "08_t0009.054_manual.wav",
        "09_t0010.689_manual.wav",
    ],
    "return": [
        "07_t0007.832_manual.wav",
        "08_t0009.054_manual.wav",
    ],
    "delete": [
        "02_t0001.945_manual.wav",
        "03_t0003.247_manual.wav",
        "04_t0004.445_manual.wav",
    ],
    "modifier": [
        "01_t0000.706_manual.wav",
        "05_t0005.629_manual.wav",
        "06_t0006.983_manual.wav",
    ],
}

CATEGORY_SETTINGS = {
    "default": {"target_peak": 0.16, "output_ms": 94, "fade_in_ms": 5.0, "fade_out_ms": 40.0, "high_cut_hz": 1700.0},
    "space": {"target_peak": 0.15, "output_ms": 136, "fade_in_ms": 6.0, "fade_out_ms": 46.0, "high_cut_hz": 1800.0},
    "return": {"target_peak": 0.18, "output_ms": 124, "fade_in_ms": 6.0, "fade_out_ms": 44.0, "high_cut_hz": 1850.0},
    "delete": {"target_peak": 0.12, "output_ms": 78, "fade_in_ms": 4.0, "fade_out_ms": 34.0, "high_cut_hz": 1650.0},
    "modifier": {"target_peak": 0.11, "output_ms": 86, "fade_in_ms": 4.0, "fade_out_ms": 36.0, "high_cut_hz": 1700.0},
}


def read_wave(path: Path) -> tuple[list[float], int, int]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()
        raw = wav_file.readframes(frame_count)

    if sample_width != 2:
        raise ValueError(f"{path.name} is not a 16-bit PCM WAV file")

    samples = array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()

    normalized = [sample / 32768.0 for sample in samples]
    return normalized, channels, sample_rate


def write_wave(path: Path, samples: list[float], channels: int, sample_rate: int) -> None:
    pcm = array("h")
    for sample in samples:
        clipped = max(-1.0, min(0.999969482421875, sample))
        pcm.append(int(round(clipped * 32767.0)))

    if sys.byteorder != "little":
        pcm.byteswap()

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm.tobytes())


def trim_leading_silence(samples: list[float], channels: int, sample_rate: int, threshold: float = 0.012, preroll_ms: float = 1.5) -> list[float]:
    frame_count = len(samples) // channels
    start_frame = 0
    for frame_index in range(frame_count):
        frame_start = frame_index * channels
        peak = max(abs(samples[frame_start + channel_offset]) for channel_offset in range(channels))
        if peak >= threshold:
            start_frame = frame_index
            break

    preroll_frames = round(sample_rate * preroll_ms / 1000.0)
    start_frame = max(0, start_frame - preroll_frames)
    return samples[start_frame * channels:]


def trim_from_start(samples: list[float], channels: int, sample_rate: int, output_ms: float) -> list[float]:
    desired_frames = max(1, round(sample_rate * output_ms / 1000.0))
    end = min(len(samples), desired_frames * channels)
    return samples[:end]


def apply_fades(samples: list[float], channels: int, sample_rate: int, fade_in_ms: float, fade_out_ms: float) -> None:
    frame_count = len(samples) // channels
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
            samples[start + channel_offset] *= gain


def normalize(samples: list[float], target_peak: float) -> None:
    peak = max((abs(sample) for sample in samples), default=0.0)
    if peak <= 0.0:
        return
    gain = target_peak / peak
    for index in range(len(samples)):
        samples[index] *= gain


def apply_low_pass(samples: list[float], channels: int, sample_rate: int, cutoff_hz: float) -> None:
    if cutoff_hz <= 0.0 or not samples:
        return

    dt = 1.0 / sample_rate
    rc = 1.0 / (2.0 * 3.141592653589793 * cutoff_hz)
    alpha = dt / (rc + dt)

    history = [0.0] * channels
    for frame_start in range(0, len(samples), channels):
        for channel_offset in range(channels):
            sample = samples[frame_start + channel_offset]
            filtered = history[channel_offset] + alpha * (sample - history[channel_offset])
            history[channel_offset] = filtered
            samples[frame_start + channel_offset] = filtered


def ensure_empty_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def build_pack() -> None:
    ensure_empty_dir(OUTPUT_DIR)
    ensure_empty_dir(RESOURCE_DIR)

    for category, selections in PACK_SELECTION.items():
        settings = CATEGORY_SETTINGS[category]

        for destination_root in (OUTPUT_DIR, RESOURCE_DIR):
            (destination_root / category).mkdir(parents=True, exist_ok=True)

        for index, file_name in enumerate(selections, start=1):
            source_path = SOURCE_DIR / GROUP / file_name
            samples, channels, sample_rate = read_wave(source_path)
            trimmed = trim_leading_silence(samples, channels, sample_rate)
            shaped = trim_from_start(trimmed, channels, sample_rate, settings["output_ms"])
            apply_low_pass(shaped, channels, sample_rate, settings["high_cut_hz"])
            normalize(shaped, settings["target_peak"])
            apply_fades(
                shaped,
                channels=channels,
                sample_rate=sample_rate,
                fade_in_ms=settings["fade_in_ms"],
                fade_out_ms=settings["fade_out_ms"],
            )

            for destination_root in (OUTPUT_DIR, RESOURCE_DIR):
                output_path = destination_root / category / f"{category}-{index:02d}.wav"
                write_wave(output_path, shaped, channels, sample_rate)

    readme_contents = "\n".join(
        [
            "Tappy Wood Brush tech pack",
            "",
            "Source vibe:",
            "- dry wood swipes and brushy desk passes",
            "- shorter brush hits for normal typing",
            "- fuller woody sweeps for space and return",
            "",
            "Categories:",
            "- default: 5 variations",
            "- space: 2 variations",
            "- return: 2 variations",
            "- delete: 3 variations",
            "- modifier: 3 variations",
        ]
    ) + "\n"

    (OUTPUT_DIR / "README.txt").write_text(readme_contents, encoding="utf-8")
    (RESOURCE_DIR / "README.txt").write_text(readme_contents, encoding="utf-8")


if __name__ == "__main__":
    build_pack()
    print(f"Built wood brush pack at {OUTPUT_DIR}")
    print(f"Copied wood brush resources to {RESOURCE_DIR}")
