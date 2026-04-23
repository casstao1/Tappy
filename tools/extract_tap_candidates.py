#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import math
import os
import sys
import wave
from array import array
from dataclasses import dataclass
from pathlib import Path


@dataclass
class EnvelopePoint:
    index: int
    time_seconds: float
    average_abs: float
    peak_abs: int


@dataclass
class Candidate:
    envelope_index: int
    time_seconds: float
    score: float
    average_abs: float
    peak_abs: int
    start_frame: int
    frame_count: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract short tap/transient candidates from a PCM WAV file."
    )
    parser.add_argument("source", type=Path, help="Path to the input WAV file")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("snippet_candidates"),
        help="Directory to write exported clips into",
    )
    parser.add_argument("--max-clips", type=int, default=24, help="How many clips to export")
    parser.add_argument(
        "--analysis-window-ms",
        type=float,
        default=5.0,
        help="Envelope analysis window size in milliseconds",
    )
    parser.add_argument(
        "--min-gap-ms",
        type=float,
        default=85.0,
        help="Minimum spacing between accepted transient peaks in milliseconds",
    )
    parser.add_argument(
        "--pre-roll-ms",
        type=float,
        default=16.0,
        help="Audio to keep before the detected transient peak",
    )
    parser.add_argument(
        "--min-length-ms",
        type=float,
        default=70.0,
        help="Minimum exported clip duration",
    )
    parser.add_argument(
        "--max-length-ms",
        type=float,
        default=170.0,
        help="Maximum exported clip duration",
    )
    parser.add_argument(
        "--tail-quiet-windows",
        type=int,
        default=3,
        help="How many quiet analysis windows in a row end a clip after the minimum length",
    )
    return parser.parse_args()


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def load_envelope(
    source: Path, analysis_window_ms: float
) -> tuple[list[EnvelopePoint], int, int, int, int]:
    with wave.open(str(source), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()

        if sample_width != 2:
            raise ValueError("Only 16-bit PCM WAV files are supported by this script.")

        window_frames = max(1, round(sample_rate * analysis_window_ms / 1000.0))
        points: list[EnvelopePoint] = []
        point_index = 0

        while True:
            raw = wav_file.readframes(window_frames)
            if not raw:
                break

            samples = array("h")
            samples.frombytes(raw)
            if sys.byteorder != "little":
                samples.byteswap()

            if not samples:
                continue

            total_abs = 0
            peak_abs = 0
            for sample in samples:
                value = abs(sample)
                total_abs += value
                if value > peak_abs:
                    peak_abs = value

            average_abs = total_abs / len(samples)
            time_seconds = (point_index * window_frames) / sample_rate
            points.append(
                EnvelopePoint(
                    index=point_index,
                    time_seconds=time_seconds,
                    average_abs=average_abs,
                    peak_abs=peak_abs,
                )
            )
            point_index += 1

    return points, channels, sample_width, sample_rate, frame_count


def percentile(values: list[float], ratio: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(ratio * (len(ordered) - 1))))
    return ordered[index]


def moving_average(values: list[float], start: int, end: int) -> float:
    if end <= start:
        return 0.0
    return sum(values[start:end]) / float(end - start)


def find_sound_start_index(
    points: list[EnvelopePoint],
    peak_index: int,
    active_threshold: float,
    quiet_windows_needed: int = 2,
) -> int:
    start_index = peak_index
    quiet_run = 0

    for index in range(peak_index, -1, -1):
        if points[index].average_abs <= active_threshold:
            quiet_run += 1
            if quiet_run >= quiet_windows_needed and start_index < peak_index:
                break
        else:
            quiet_run = 0
            start_index = index

    return start_index


def find_sound_end_frame(
    points: list[EnvelopePoint],
    peak_index: int,
    active_threshold: float,
    minimum_end_frame: int,
    maximum_end_frame: int,
    sample_rate: int,
    analysis_window_ms: float,
    tail_quiet_windows: int,
) -> int:
    window_frames = max(1, round(sample_rate * analysis_window_ms / 1000.0))
    tail_padding_frames = round(sample_rate * 0.008)
    quiet_run = 0
    last_loud_end_frame = round(points[peak_index].time_seconds * sample_rate) + window_frames

    for index in range(peak_index, len(points)):
        point = points[index]
        point_end_frame = round(point.time_seconds * sample_rate) + window_frames

        if point.average_abs <= active_threshold:
            quiet_run += 1
        else:
            quiet_run = 0
            last_loud_end_frame = point_end_frame

        if point_end_frame >= minimum_end_frame and quiet_run >= tail_quiet_windows:
            return min(maximum_end_frame, last_loud_end_frame + tail_padding_frames)

        if point_end_frame >= maximum_end_frame:
            return maximum_end_frame

    return min(maximum_end_frame, last_loud_end_frame + tail_padding_frames)


def score_candidates(
    points: list[EnvelopePoint],
    sample_rate: int,
    analysis_window_ms: float,
    min_gap_ms: float,
    pre_roll_ms: float,
    min_length_ms: float,
    max_length_ms: float,
    tail_quiet_windows: int,
    max_clips: int,
) -> list[Candidate]:
    if not points:
        return []

    averages = [point.average_abs for point in points]
    peaks = [point.peak_abs for point in points]
    positive_scores: list[float] = []
    raw_scored: list[tuple[int, float]] = []

    for index, point in enumerate(points):
        history_start = max(0, index - 10)
        history_end = max(history_start, index - 1)
        history_average = moving_average(averages, history_start, history_end) if history_end > history_start else 0.0
        local_delta = max(0.0, point.average_abs - history_average)
        score = (local_delta * 0.75) + (point.peak_abs * 0.25)
        raw_scored.append((index, score))
        if score > 0:
            positive_scores.append(score)

    score_threshold = percentile(positive_scores, 0.96)
    level_threshold = percentile(averages, 0.86)
    peak_threshold = percentile(peaks, 0.88)
    quiet_threshold = max(300.0, percentile(averages, 0.28))

    min_gap_windows = max(1, round(min_gap_ms / analysis_window_ms))
    pre_roll_frames = round(sample_rate * pre_roll_ms / 1000.0)
    min_length_frames = round(sample_rate * min_length_ms / 1000.0)
    max_length_frames = round(sample_rate * max_length_ms / 1000.0)

    peak_like: list[tuple[int, float]] = []
    for index, score in raw_scored:
        if score < score_threshold:
            continue
        if averages[index] < level_threshold:
            continue
        if peaks[index] < peak_threshold:
            continue

        left = max(0, index - 2)
        right = min(len(points), index + 3)
        neighborhood = raw_scored[left:right]
        local_max_index, local_max_score = max(neighborhood, key=lambda item: item[1])
        if local_max_index != index:
            continue
        peak_like.append((index, local_max_score))

    peak_like.sort(key=lambda item: item[1], reverse=True)

    accepted: list[Candidate] = []
    used_indices: list[int] = []

    for envelope_index, score in peak_like:
        if any(abs(envelope_index - other_index) < min_gap_windows for other_index in used_indices):
            continue

        peak_point = points[envelope_index]
        active_threshold = max(
            quiet_threshold * 1.6,
            min(level_threshold * 0.42, peak_point.average_abs * 0.24)
        )
        sound_start_index = find_sound_start_index(points, envelope_index, active_threshold)
        start_frame = max(0, round(points[sound_start_index].time_seconds * sample_rate) - pre_roll_frames)

        clip_end_frame = start_frame + max_length_frames
        minimum_end_frame = start_frame + min_length_frames

        clip_end_frame = find_sound_end_frame(
            points=points,
            peak_index=envelope_index,
            active_threshold=active_threshold,
            minimum_end_frame=minimum_end_frame,
            maximum_end_frame=start_frame + max_length_frames,
            sample_rate=sample_rate,
            analysis_window_ms=analysis_window_ms,
            tail_quiet_windows=tail_quiet_windows,
        )

        frame_count = max(min_length_frames, clip_end_frame - start_frame)
        accepted.append(
            Candidate(
                envelope_index=envelope_index,
                time_seconds=peak_point.time_seconds,
                score=score,
                average_abs=peak_point.average_abs,
                peak_abs=peak_point.peak_abs,
                start_frame=start_frame,
                frame_count=min(frame_count, max_length_frames),
            )
        )
        used_indices.append(envelope_index)

        if len(accepted) >= max_clips:
            break

    accepted.sort(key=lambda candidate: candidate.time_seconds)
    return accepted


def export_candidates(
    source: Path,
    output_dir: Path,
    candidates: list[Candidate],
    channels: int,
    sample_width: int,
    sample_rate: int,
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "manifest.csv"

    with wave.open(str(source), "rb") as source_wav, manifest_path.open("w", newline="") as manifest_file:
        writer = csv.writer(manifest_file)
        writer.writerow(
            [
                "clip_name",
                "source_time_seconds",
                "duration_ms",
                "score",
                "average_abs",
                "peak_abs",
                "file_path",
            ]
        )

        for clip_number, candidate in enumerate(candidates, start=1):
            clip_name = (
                f"{clip_number:02d}_t{candidate.time_seconds:08.3f}"
                f"_score{int(round(candidate.score))}.wav"
            )
            clip_path = output_dir / clip_name

            source_wav.setpos(candidate.start_frame)
            frames = source_wav.readframes(candidate.frame_count)

            with wave.open(str(clip_path), "wb") as clip_wav:
                clip_wav.setnchannels(channels)
                clip_wav.setsampwidth(sample_width)
                clip_wav.setframerate(sample_rate)
                clip_wav.writeframes(frames)

            writer.writerow(
                [
                    clip_name,
                    f"{candidate.time_seconds:.3f}",
                    f"{candidate.frame_count * 1000.0 / sample_rate:.1f}",
                    f"{candidate.score:.2f}",
                    f"{candidate.average_abs:.2f}",
                    candidate.peak_abs,
                    str(clip_path),
                ]
            )

    return manifest_path


def write_summary(
    output_dir: Path,
    source: Path,
    candidates: list[Candidate],
    sample_rate: int,
    analysis_window_ms: float,
) -> Path:
    summary_path = output_dir / "summary.txt"
    best = sorted(candidates, key=lambda item: item.score, reverse=True)[:8]

    lines = [
        f"Source: {source}",
        f"Exported clips: {len(candidates)}",
        f"Sample rate: {sample_rate} Hz",
        f"Analysis window: {analysis_window_ms:.2f} ms",
        "",
        "Top-scoring clips:",
    ]

    for item in best:
        duration_ms = item.frame_count * 1000.0 / sample_rate
        lines.append(
            f"- t={item.time_seconds:.3f}s score={item.score:.2f} "
            f"peak={item.peak_abs} duration={duration_ms:.1f}ms"
        )

    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary_path


def main() -> int:
    args = parse_args()

    if not args.source.exists():
        return fail(f"Source file does not exist: {args.source}")

    try:
        points, channels, sample_width, sample_rate, _ = load_envelope(
            args.source, args.analysis_window_ms
        )
    except (wave.Error, ValueError) as error:
        return fail(str(error))

    candidates = score_candidates(
        points=points,
        sample_rate=sample_rate,
        analysis_window_ms=args.analysis_window_ms,
        min_gap_ms=args.min_gap_ms,
        pre_roll_ms=args.pre_roll_ms,
        min_length_ms=args.min_length_ms,
        max_length_ms=args.max_length_ms,
        tail_quiet_windows=args.tail_quiet_windows,
        max_clips=args.max_clips,
    )

    if not candidates:
        return fail("No transient candidates were detected with the current settings.")

    manifest_path = export_candidates(
        source=args.source,
        output_dir=args.output_dir,
        candidates=candidates,
        channels=channels,
        sample_width=sample_width,
        sample_rate=sample_rate,
    )
    summary_path = write_summary(
        output_dir=args.output_dir,
        source=args.source,
        candidates=candidates,
        sample_rate=sample_rate,
        analysis_window_ms=args.analysis_window_ms,
    )

    print(f"Exported {len(candidates)} clips to {args.output_dir}")
    print(f"Manifest: {manifest_path}")
    print(f"Summary: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
