#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import sys
import wave
from array import array
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT_DIR / "farming_candidates_v2"
OUTPUT_DIR = ROOT_DIR / "farming_pack_ready"
RESOURCE_DIR = ROOT_DIR / "Tappy" / "Resources" / "BundledSounds" / "farming"
SELECTION_FILE = ROOT_DIR / "farming_pack_selection.json"

DEFAULT_PACK_SELECTION = {
    "default": [
        ("stone", "00_full_trimmed.wav"),
        ("wood", "02_t0000.738_score4235.wav"),
    ],
    "space": [
        ("villager", "00_full_trimmed.wav"),
    ],
    "return": [
        ("eating", "00_full_trimmed.wav"),
    ],
    "delete": [
        ("sand", "00_full_trimmed.wav"),
    ],
    "modifier": [
        ("eating", "01_t0000.485_score3646_wide.wav"),
    ],
}

CATEGORY_SETTINGS = {
    "default": {"target_peak": 0.72, "output_ms": 58, "fade_in_ms": 1.0, "fade_out_ms": 18.0, "high_cut_hz": 3300.0, "preserve_exact": False},
    "space": {"target_peak": 0.54, "output_ms": 140, "fade_in_ms": 3.0, "fade_out_ms": 42.0, "high_cut_hz": 3000.0, "preserve_exact": True},
    "return": {"target_peak": 0.58, "output_ms": 70, "fade_in_ms": 1.0, "fade_out_ms": 56.0, "high_cut_hz": 3200.0, "preserve_exact": True},
    "delete": {"target_peak": 0.52, "output_ms": 64, "fade_in_ms": 1.0, "fade_out_ms": 48.0, "high_cut_hz": 2900.0, "preserve_exact": True},
    "modifier": {"target_peak": 0.46, "output_ms": 54, "fade_in_ms": 1.0, "fade_out_ms": 20.0, "high_cut_hz": 3100.0, "preserve_exact": True},
}

FILE_OVERRIDES: dict[tuple[str, str, str], dict[str, float | bool]] = {
    ("default", "stone", "00_full_trimmed_clean.wav"): {
        "high_cut_hz": 2200.0,
        "target_peak": 0.64,
        "fade_in_ms": 2.0,
        "fade_out_ms": 22.0,
        "preserve_exact": True,
    },
    ("default", "wood", "02_t0000.738_score4235_clean.wav"): {
        "high_cut_hz": 1000.0,
        "target_peak": 0.60,
        "fade_in_ms": 2.0,
        "fade_out_ms": 18.0,
    },
    ("space", "wood", "00_full_trimmed_clean.wav"): {
        "high_cut_hz": 900.0,
        "target_peak": 0.30,
        "fade_in_ms": 2.0,
        "fade_out_ms": 18.0,
        "preserve_exact": True,
    },
    ("return", "water", "00_full_trimmed.wav"): {
        "target_peak": 0.32,
        "fade_in_ms": 24.0,
        "fade_out_ms": 180.0,
        "trim_start_ms": 30.0,
        "trim_end_ms": 826.0,
        "high_cut_hz": 2100.0,
        "preserve_exact": True,
    },
    ("delete", "eating", "00_full_trimmed.wav"): {
        "target_peak": 0.28,
        "fade_in_ms": 16.0,
        "fade_out_ms": 150.0,
        "trim_start_ms": 0.0,
        "trim_end_ms": 692.0,
        "high_cut_hz": 2400.0,
        "preserve_exact": True,
    },
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


def trim_to_duration(
    samples: list[float],
    channels: int,
    sample_rate: int,
    max_duration_ms: float,
) -> list[float]:
    if max_duration_ms <= 0.0:
        return samples

    max_frames = max(1, round(sample_rate * max_duration_ms / 1000.0))
    max_samples = max_frames * channels
    if len(samples) <= max_samples:
        return samples
    return samples[:max_samples]


def trim_to_range(
    samples: list[float],
    channels: int,
    sample_rate: int,
    start_ms: float,
    end_ms: float,
) -> list[float]:
    if end_ms <= 0.0:
        return samples

    total_frames = len(samples) // channels
    start_frame = max(0, min(total_frames, round(sample_rate * start_ms / 1000.0)))
    end_frame = max(start_frame + 1, min(total_frames, round(sample_rate * end_ms / 1000.0)))
    start_sample = start_frame * channels
    end_sample = end_frame * channels
    return samples[start_sample:end_sample]


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


def shape_samples(
    samples: list[float],
    channels: int,
    sample_rate: int,
    category: str,
    file_name: str,
    settings: dict[str, float],
) -> list[float]:
    if settings.get("preserve_exact"):
        exact = trim_to_range(
            samples.copy(),
            channels=channels,
            sample_rate=sample_rate,
            start_ms=float(settings.get("trim_start_ms", 0.0)),
            end_ms=float(settings.get("trim_end_ms", 0.0)),
        )
        return trim_to_duration(
            exact,
            channels=channels,
            sample_rate=sample_rate,
            max_duration_ms=float(settings.get("max_duration_ms", 0.0)),
        )

    if file_name == "00_full_trimmed.wav" and category != "delete":
        return samples.copy()

    peak_frame = detect_peak_frame(samples, channels)
    return trim_around_peak(
        samples=samples,
        channels=channels,
        sample_rate=sample_rate,
        peak_frame=peak_frame,
        output_ms=settings["output_ms"],
    )


def resolve_settings(category: str, group_name: str, file_name: str) -> dict[str, float | bool]:
    settings = dict(CATEGORY_SETTINGS[category])
    settings.update(FILE_OVERRIDES.get((category, group_name, file_name), {}))
    return settings


def build_pack() -> None:
    pack_selection = load_pack_selection()
    ensure_empty_dir(OUTPUT_DIR)
    ensure_empty_dir(RESOURCE_DIR)

    for category, selections in pack_selection.items():
        for destination_root in (OUTPUT_DIR, RESOURCE_DIR):
            category_dir = destination_root / category
            category_dir.mkdir(parents=True, exist_ok=True)

        for index, (group_name, file_name) in enumerate(selections, start=1):
            settings = resolve_settings(category, group_name, file_name)
            source_path = SOURCE_DIR / group_name / file_name
            samples, channels, sample_rate = read_wave(source_path)
            shaped = shape_samples(samples, channels, sample_rate, category, file_name, settings)
            if settings.get("high_cut_hz", 0.0) > 0.0:
                apply_low_pass(
                    shaped,
                    channels=channels,
                    sample_rate=sample_rate,
                    cutoff_hz=settings["high_cut_hz"],
                )
            if not settings.get("preserve_exact"):
                normalize(shaped, settings["target_peak"])
                apply_fades(
                    shaped,
                    channels=channels,
                    sample_rate=sample_rate,
                    fade_in_ms=settings["fade_in_ms"],
                    fade_out_ms=settings["fade_out_ms"],
                )
            elif (category, group_name, file_name) in FILE_OVERRIDES:
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
            "Tappy Farming tech pack",
            "",
            "Source vibe:",
            "- wood / stone / sand block-style typing",
            "- villager voice on space",
            "- eating-style special-key accents",
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
    print(f"Built farming pack at {OUTPUT_DIR}")
    print(f"Copied farming resources to {RESOURCE_DIR}")
