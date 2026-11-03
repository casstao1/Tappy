#!/usr/bin/env python3
"""Build the Wax Cracking premium demo from every bundled crack clip."""

from pathlib import Path
import wave


ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = ROOT / "Tappy" / "Resources" / "BundledSounds" / "wax-cracking"
SOURCE_DIR = PACK_ROOT / "default"
OUTPUT_PATH = PACK_ROOT / "demo" / "demo.wav"
TARGET_DURATION_SECONDS = 3.683492


def main() -> None:
    source_paths = sorted(SOURCE_DIR.glob("*.wav"))
    if not source_paths:
        raise RuntimeError(f"No source clips found in {SOURCE_DIR}")

    clip_frames: list[bytes] = []
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
            clip_frames.append(source.readframes(frame_count))
            total_clip_frames += frame_count

    assert audio_format is not None
    channels, sample_width, sample_rate, compression_type, compression_name = audio_format
    target_frames = round(TARGET_DURATION_SECONDS * sample_rate)
    remaining_frames = target_frames - total_clip_frames
    gap_count = max(len(clip_frames) - 1, 1)
    if remaining_frames < 0:
        raise RuntimeError("Source clips are longer than the target demo duration")

    gap_frames, trailing_frames = divmod(remaining_frames, gap_count)
    silence_frame = b"\x00" * channels * sample_width
    gap = silence_frame * gap_frames
    trailing_silence = silence_frame * trailing_frames

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT_PATH), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(sample_width)
        output.setframerate(sample_rate)
        output.setcomptype(compression_type, compression_name)

        for index, frames in enumerate(clip_frames):
            output.writeframesraw(frames)
            if index < len(clip_frames) - 1:
                output.writeframesraw(gap)
        output.writeframes(trailing_silence)

    duration = target_frames / sample_rate
    print(
        f"Built {OUTPUT_PATH} from {len(source_paths)} clips "
        f"at {duration:.6f}s with {gap_frames / sample_rate:.5f}s gaps."
    )


if __name__ == "__main__":
    main()
