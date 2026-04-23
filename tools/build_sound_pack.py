#!/usr/bin/env python3

from __future__ import annotations

import math
import shutil
import sys
import wave
from array import array
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT_DIR / "snippet_candidates"
OUTPUT_DIR = ROOT_DIR / "sound_pack_ready"

PACK_SELECTION = {
    "default": [
        "01_t0005.275_score4470.wav",
        "04_t0012.615_score4711.wav",
        "08_t0037.125_score4302.wav",
        "13_t0213.765_score3926.wav",
        "15_t0242.125_score6177.wav",
        "23_t0475.905_score4348.wav",
    ],
    "space": [
        "12_t0078.635_score3401.wav",
    ],
    "return": [
        "11_t0064.645_score5058.wav",
    ],
    "delete": [
        "03_t0011.075_score3915.wav",
    ],
    "modifier": [
        "02_t0010.895_score3479.wav",
    ],
}

CATEGORY_SETTINGS = {
    "default": {"target_peak": 0.64, "output_ms": 64, "fade_in_ms": 3.0, "fade_out_ms": 18.0},
    "space": {"target_peak": 0.48, "output_ms": 72, "fade_in_ms": 3.0, "fade_out_ms": 20.0},
    "return": {"target_peak": 0.52, "output_ms": 68, "fade_in_ms": 3.0, "fade_out_ms": 22.0},
    "delete": {"target_peak": 0.46, "output_ms": 60, "fade_in_ms": 2.5, "fade_out_ms": 18.0},
    "modifier": {"target_peak": 0.42, "output_ms": 56, "fade_in_ms": 2.5, "fade_out_ms": 16.0},
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


def trim_around_peak(
    samples: list[float],
    channels: int,
    sample_rate: int,
    peak_frame: int,
    output_ms: float,
) -> list[float]:
    total_frames = len(samples) // channels
    desired_frames = max(1, round(sample_rate * output_ms / 1000.0))
    pre_frames = max(1, round(sample_rate * 0.004))
    start_frame = max(0, peak_frame - pre_frames)
    end_frame = min(total_frames, start_frame + desired_frames)

    if end_frame - start_frame < desired_frames:
        start_frame = max(0, end_frame - desired_frames)

    start = start_frame * channels
    end = end_frame * channels
    return samples[start:end]


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

    for category, file_names in PACK_SELECTION.items():
        category_dir = OUTPUT_DIR / category
        category_dir.mkdir(parents=True, exist_ok=True)
        settings = CATEGORY_SETTINGS[category]

        for index, file_name in enumerate(file_names, start=1):
            source_path = SOURCE_DIR / file_name
            samples, channels, sample_rate = read_wave(source_path)
            peak_frame = detect_peak_frame(samples, channels)
            shaped = trim_around_peak(
                samples=samples,
                channels=channels,
                sample_rate=sample_rate,
                peak_frame=peak_frame,
                output_ms=settings["output_ms"],
            )
            normalize(shaped, settings["target_peak"])
            apply_fades(
                shaped,
                channels=channels,
                sample_rate=sample_rate,
                fade_in_ms=settings["fade_in_ms"],
                fade_out_ms=settings["fade_out_ms"],
            )

            output_path = category_dir / f"{category}-{index:02d}.wav"
            write_wave(output_path, shaped, channels, sample_rate)

    readme = OUTPUT_DIR / "README.txt"
    readme.write_text(
        "\n".join(
            [
                "Keyboard Sound App starter pack",
                "",
                "This pack is already laid out in the folder structure the app expects:",
                "- default",
                "- space",
                "- return",
                "- delete",
                "- modifier",
                "",
                "You can import these directly into the app, or copy the WAV files into the app's Sounds folders.",
                "",
                "Current curated choices:",
                "- default: 6 variations",
                "- space: 1 variation",
                "- return: 1 variation",
                "- delete: 1 variation",
                "- modifier: 1 variation",
            ]
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    build_pack()
    print(f"Built polished sound pack at {OUTPUT_DIR}")
