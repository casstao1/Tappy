#!/usr/bin/env python3

from __future__ import annotations

import shutil
import sys
import wave
from array import array
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT_DIR / "stopwatch_candidates"
OUTPUT_DIR = ROOT_DIR / "stopwatch_pack_ready"
RESOURCE_DIR = ROOT_DIR / "Tappy" / "Resources" / "BundledSounds" / "analog-stopwatch"

PACK_SELECTION = {
    "default": [
        ("winding", "03_t0011.736_score6988.wav"),
        ("winding", "06_t0013.196_score7031.wav"),
        ("winding", "07_t0013.268_score7468.wav"),
        ("winding", "14_t0015.916_score7613.wav"),
        ("winding", "16_t0016.232_score6920.wav"),
    ],
    "space": [
        ("winding", "11_t0015.264_score6129.wav"),
        ("winding", "16_t0016.232_score6920.wav"),
    ],
    "return": [
        ("winding", "07_t0013.268_score7468.wav"),
        ("winding", "14_t0015.916_score7613.wav"),
    ],
    "delete": [
        ("winding", "02_t0011.264_score6393.wav"),
        ("winding", "08_t0013.380_score6441.wav"),
        ("winding", "13_t0015.792_score6437.wav"),
    ],
    "modifier": [
        ("winding", "01_t0011.012_score5929.wav"),
        ("winding", "05_t0012.984_score6265.wav"),
        ("winding", "12_t0015.608_score6111.wav"),
    ],
}

CATEGORY_SETTINGS = {
    "default": {"target_peak": 0.50, "output_ms": 52, "fade_in_ms": 2.5, "fade_out_ms": 16.0},
    "space": {"target_peak": 0.42, "output_ms": 78, "fade_in_ms": 2.5, "fade_out_ms": 22.0},
    "return": {"target_peak": 0.46, "output_ms": 68, "fade_in_ms": 2.5, "fade_out_ms": 20.0},
    "delete": {"target_peak": 0.38, "output_ms": 48, "fade_in_ms": 2.0, "fade_out_ms": 16.0},
    "modifier": {"target_peak": 0.34, "output_ms": 44, "fade_in_ms": 2.0, "fade_out_ms": 14.0},
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


def frame_average(samples: list[float], channels: int, frame_index: int) -> float:
    start = frame_index * channels
    frame = samples[start:start + channels]
    return sum(frame) / len(frame)


def detect_peak_frame(samples: list[float], channels: int) -> int:
    frame_count = len(samples) // channels
    best_index = 0
    best_value = -1.0
    for frame_index in range(frame_count):
        value = abs(frame_average(samples, channels, frame_index))
        if value > best_value:
            best_value = value
            best_index = frame_index
    return best_index


def trim_around_peak(samples: list[float], channels: int, sample_rate: int, peak_frame: int, output_ms: float) -> list[float]:
    total_frames = len(samples) // channels
    desired_frames = max(1, round(sample_rate * output_ms / 1000.0))
    pre_frames = max(1, round(sample_rate * 0.004))
    start_frame = max(0, peak_frame - pre_frames)
    end_frame = min(total_frames, start_frame + desired_frames)

    if end_frame - start_frame < desired_frames:
        start_frame = max(0, end_frame - desired_frames)

    return samples[start_frame * channels:end_frame * channels]


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

        for index, (group_name, file_name) in enumerate(selections, start=1):
            source_path = SOURCE_DIR / group_name / file_name
            samples, channels, sample_rate = read_wave(source_path)
            peak_frame = detect_peak_frame(samples, channels)
            shaped = trim_around_peak(samples, channels, sample_rate, peak_frame, settings["output_ms"])
            normalize(shaped, settings["target_peak"])
            apply_fades(shaped, channels, sample_rate, settings["fade_in_ms"], settings["fade_out_ms"])

            for destination_root in (OUTPUT_DIR, RESOURCE_DIR):
                output_path = destination_root / category / f"{category}-{index:02d}.wav"
                write_wave(output_path, shaped, channels, sample_rate)

    readme_contents = "\n".join(
        [
            "Tappy Analog Stopwatch tech pack",
            "",
            "Source vibe:",
            "- wound stopwatch ratchets and metallic click ticks",
            "- tight mechanical cuts for normal typing",
            "- heavier wind-up accents for larger keys",
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
    print(f"Built stopwatch pack at {OUTPUT_DIR}")
    print(f"Copied stopwatch resources to {RESOURCE_DIR}")
