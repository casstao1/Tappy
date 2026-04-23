#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import sys
import wave
from array import array
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT_DIR / "bubble_candidates_v2"
OUTPUT_DIR = ROOT_DIR / "bubble_pack_ready"
RESOURCE_DIR = ROOT_DIR / "Tappy" / "Resources" / "BundledSounds" / "bubble"
SELECTION_FILE = ROOT_DIR / "bubble_pack_selection.json"

DEFAULT_PACK_SELECTION = {
    "default": [
        ("dragon-studio-bubble-pop-406640", "01b_t0000.024_split.wav"),
        ("dragon-studio-bubble-pop-406640", "03_t0000.152_score17396.wav"),
        ("universfield-bubble-pop-02-293341", "01_t0000.103_manual.wav"),
        ("dragon-studio-pop-402323", "00_full_trimmed.wav"),
    ],
    "space": [
        ("soundreality-pop-423717", "01_t0000.156_score26024.wav"),
    ],
    "return": [
        ("dragon-studio-pop-402323", "01_t0000.116_score12999.wav"),
    ],
    "delete": [
        ("freesound_community-sci-fi-bubble-pop-89059", "01_t0000.104_score4795.wav"),
    ],
    "modifier": [
        ("universfield-bubble-pop-06-351337", "01_t0000.115_manual.wav"),
    ],
}

CATEGORY_SETTINGS = {
    "default": {"target_peak": 0.54, "output_ms": 72, "fade_in_ms": 3.0, "fade_out_ms": 24.0},
    "space": {"target_peak": 0.40, "output_ms": 96, "fade_in_ms": 3.0, "fade_out_ms": 28.0},
    "return": {"target_peak": 0.48, "output_ms": 86, "fade_in_ms": 3.0, "fade_out_ms": 28.0},
    "delete": {"target_peak": 0.42, "output_ms": 62, "fade_in_ms": 2.5, "fade_out_ms": 20.0},
    "modifier": {"target_peak": 0.36, "output_ms": 60, "fade_in_ms": 2.5, "fade_out_ms": 22.0},
}


def load_pack_selection() -> dict[str, list[tuple[str, str]]]:
    if not SELECTION_FILE.exists():
        return DEFAULT_PACK_SELECTION

    data = json.loads(SELECTION_FILE.read_text(encoding="utf-8"))
    selection: dict[str, list[tuple[str, str]]] = {}
    for category, entries in data.items():
        selection[category] = [(entry["group"], entry["file"]) for entry in entries]
    return selection


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


def shape_samples(samples: list[float], channels: int, sample_rate: int, file_name: str, settings: dict[str, float]) -> list[float]:
    if file_name == "00_full_trimmed.wav":
        return samples.copy()

    peak_frame = detect_peak_frame(samples, channels)
    return trim_around_peak(
        samples=samples,
        channels=channels,
        sample_rate=sample_rate,
        peak_frame=peak_frame,
        output_ms=settings["output_ms"],
    )


def build_pack() -> None:
    pack_selection = load_pack_selection()
    ensure_empty_dir(OUTPUT_DIR)
    ensure_empty_dir(RESOURCE_DIR)

    for category, selections in pack_selection.items():
        settings = CATEGORY_SETTINGS[category]

        for destination_root in (OUTPUT_DIR, RESOURCE_DIR):
            category_dir = destination_root / category
            category_dir.mkdir(parents=True, exist_ok=True)

        for index, (group_name, file_name) in enumerate(selections, start=1):
            source_path = SOURCE_DIR / group_name / file_name
            samples, channels, sample_rate = read_wave(source_path)
            shaped = shape_samples(samples, channels, sample_rate, file_name, settings)
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
            "Tappy Bubble tech pack",
            "",
            "Source vibe:",
            "- glossy bubble pops and airy sci-fi blips",
            "- bigger glossy pop on space and a tighter return hit",
            "- short, shaped clips for immediate playback",
            "",
            "Categories:",
            f"- default: {len(pack_selection['default'])} variation{'s' if len(pack_selection['default']) != 1 else ''}",
            f"- space: {len(pack_selection['space'])} variation{'s' if len(pack_selection['space']) != 1 else ''}",
            f"- return: {len(pack_selection['return'])} variation{'s' if len(pack_selection['return']) != 1 else ''}",
            f"- delete: {len(pack_selection['delete'])} variation{'s' if len(pack_selection['delete']) != 1 else ''}",
            f"- modifier: {len(pack_selection['modifier'])} variation{'s' if len(pack_selection['modifier']) != 1 else ''}",
        ]
    ) + "\n"

    (OUTPUT_DIR / "README.txt").write_text(readme_contents, encoding="utf-8")
    (RESOURCE_DIR / "README.txt").write_text(readme_contents, encoding="utf-8")


if __name__ == "__main__":
    build_pack()
    print(f"Built bubble pack at {OUTPUT_DIR}")
    print(f"Copied bubble resources to {RESOURCE_DIR}")
