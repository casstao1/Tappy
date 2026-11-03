#!/usr/bin/env python3
"""Build the Wet Squishy Pop demo from every bundled studio-mix clip."""

from pathlib import Path
import random
import wave


ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = ROOT / "Tappy" / "Resources" / "BundledSounds" / "studio-mix"
SOURCE_DIR = PACK_ROOT / "default"
OUTPUT_DIR = PACK_ROOT / "demo"
TARGET_DURATION_SECONDS = 3.683492
VARIANT_COUNT = 4


def variant_output_path(index: int) -> Path:
    if index == 0:
        return OUTPUT_DIR / "demo.wav"
    return OUTPUT_DIR / f"demo-{index + 1:02d}.wav"


def randomized_gaps(total_frames: int, count: int, rng: random.Random) -> list[int]:
    weights = [rng.uniform(0.55, 1.45) for _ in range(count)]
    weight_total = sum(weights)
    gaps = [round(total_frames * weight / weight_total) for weight in weights]
    gaps[-1] += total_frames - sum(gaps)
    return gaps


def main() -> None:
    source_paths = sorted(SOURCE_DIR.glob("*.wav"))
    if not source_paths:
        raise RuntimeError(f"No source clips found in {SOURCE_DIR}")

    clip_frames: list[tuple[Path, bytes]] = []
    audio_format: tuple[int, int, int, str, str] | None = None
    total_clip_frames = 0

    for path in source_paths:
        with wave.open(str(path), "rb") as source:
            current_format = (
                source.getnchannels(),
                source.getsampwidth(),
                source.getframerate(),
                source.getcomptype(),
                source.getcompname(),
            )
            if audio_format is None:
                audio_format = current_format
            elif current_format != audio_format:
                raise RuntimeError(f"Audio format mismatch: {path}")

            frame_count = source.getnframes()
            clip_frames.append((path, source.readframes(frame_count)))
            total_clip_frames += frame_count

    assert audio_format is not None
    channels, sample_width, sample_rate, compression_type, compression_name = audio_format
    target_frames = round(TARGET_DURATION_SECONDS * sample_rate)
    remaining_frames = target_frames - total_clip_frames
    gap_count = max(len(clip_frames) - 1, 1)
    if remaining_frames < 0:
        raise RuntimeError("Source clips are longer than the target demo duration")

    silence_frame = b"\x00" * channels * sample_width

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for stale_demo in OUTPUT_DIR.glob("*.wav"):
        stale_demo.unlink()

    duration = target_frames / sample_rate
    for variant_index in range(VARIANT_COUNT):
        rng = random.Random(f"studio-mix-demo-{variant_index + 1}")
        shuffled_frames = clip_frames.copy()
        rng.shuffle(shuffled_frames)
        gap_lengths = randomized_gaps(remaining_frames, gap_count, rng)
        output_path = variant_output_path(variant_index)

        with wave.open(str(output_path), "wb") as output:
            output.setnchannels(channels)
            output.setsampwidth(sample_width)
            output.setframerate(sample_rate)
            output.setcomptype(compression_type, compression_name)

            for clip_index, (_, frames) in enumerate(shuffled_frames):
                output.writeframesraw(frames)
                if clip_index < len(shuffled_frames) - 1:
                    output.writeframesraw(silence_frame * gap_lengths[clip_index])

        gap_seconds = [frames / sample_rate for frames in gap_lengths]
        print(
            f"Built {output_path} from {len(source_paths)} shuffled clips "
            f"at {duration:.6f}s with {min(gap_seconds):.3f}-{max(gap_seconds):.3f}s gaps."
        )


if __name__ == "__main__":
    main()
