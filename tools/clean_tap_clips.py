#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import wave
from pathlib import Path

import numpy as np


FFT_SIZE = 512
HOP_SIZE = 128
NOISE_PERCENTILE = 22.0
SPECTRAL_FLOOR = 0.025
OVER_SUBTRACTION = 1.65


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Remove steady recording noise and isolate tap transients in PCM WAV clips."
    )
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--noise-source",
        action="append",
        default=[],
        metavar="PREFIX=PATH",
        help="Map an input filename prefix to its full-length source recording.",
    )
    return parser.parse_args()


def read_pcm16_mono(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as wav_file:
        if wav_file.getnchannels() != 1 or wav_file.getsampwidth() != 2:
            raise ValueError(f"Expected mono 16-bit PCM WAV: {path}")
        sample_rate = wav_file.getframerate()
        samples = np.frombuffer(wav_file.readframes(wav_file.getnframes()), dtype="<i2")
    return sample_rate, samples.astype(np.float64) / 32768.0


def write_pcm16_mono(path: Path, sample_rate: int, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = np.round(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(encoded.tobytes())


def parse_noise_sources(values: list[str]) -> dict[str, Path]:
    sources: dict[str, Path] = {}
    for value in values:
        prefix, separator, raw_path = value.partition("=")
        if not separator or not prefix or not raw_path:
            raise ValueError(f"Invalid --noise-source value: {value}")
        sources[prefix] = Path(raw_path)
    if not sources:
        raise ValueError("At least one --noise-source PREFIX=PATH mapping is required")
    return sources


def noise_profile(path: Path) -> tuple[int, np.ndarray, float]:
    sample_rate, samples = read_pcm16_mono(path)
    usable = len(samples) - (len(samples) % FFT_SIZE)
    frames = samples[:usable].reshape(-1, FFT_SIZE)
    frame_rms = np.sqrt(np.mean(frames * frames, axis=1))
    threshold = np.percentile(frame_rms, NOISE_PERCENTILE)
    quiet_frames = frames[frame_rms <= threshold]

    window = np.hanning(FFT_SIZE)
    spectra = np.fft.rfft(quiet_frames * window, axis=1)
    power = np.abs(spectra) ** 2
    profile = np.median(power, axis=0)
    quiet_rms = float(np.median(frame_rms[frame_rms <= threshold]))
    return sample_rate, profile, quiet_rms


def smooth_mask(mask: np.ndarray) -> np.ndarray:
    frequency_padded = np.pad(mask, ((0, 0), (1, 1)), mode="edge")
    mask = (
        0.18 * frequency_padded[:, :-2]
        + 0.64 * frequency_padded[:, 1:-1]
        + 0.18 * frequency_padded[:, 2:]
    )
    time_padded = np.pad(mask, ((1, 1), (0, 0)), mode="edge")
    return (
        0.16 * time_padded[:-2]
        + 0.68 * time_padded[1:-1]
        + 0.16 * time_padded[2:]
    )


def spectral_denoise(
    samples: np.ndarray,
    sample_rate: int,
    profile: np.ndarray,
) -> np.ndarray:
    window = np.hanning(FFT_SIZE)
    pad = FFT_SIZE // 2
    padded_length = len(samples) + (2 * pad)
    frame_count = max(1, math.ceil((padded_length - FFT_SIZE) / HOP_SIZE) + 1)
    total_length = ((frame_count - 1) * HOP_SIZE) + FFT_SIZE
    padded = np.pad(samples, (pad, total_length - len(samples) - pad))

    spectra = []
    for start in range(0, total_length - FFT_SIZE + 1, HOP_SIZE):
        spectra.append(np.fft.rfft(padded[start : start + FFT_SIZE] * window))
    spectra_array = np.asarray(spectra)
    power = np.abs(spectra_array) ** 2

    raw_mask = 1.0 - (OVER_SUBTRACTION * profile[None, :]) / (power + 1e-15)
    mask = smooth_mask(np.clip(raw_mask, SPECTRAL_FLOOR, 1.0))

    frequencies = np.fft.rfftfreq(FFT_SIZE, 1.0 / sample_rate)
    band_mask = np.ones_like(frequencies)
    band_mask[frequencies <= 70.0] = 0.0
    low_transition = (frequencies > 70.0) & (frequencies < 150.0)
    band_mask[low_transition] = (frequencies[low_transition] - 70.0) / 80.0
    band_mask[frequencies >= 22000.0] = 0.0
    high_transition = (frequencies > 18000.0) & (frequencies < 22000.0)
    band_mask[high_transition] = (22000.0 - frequencies[high_transition]) / 4000.0

    cleaned_spectra = spectra_array * mask * band_mask[None, :]
    output = np.zeros(total_length)
    normalization = np.zeros(total_length)
    for index, start in enumerate(range(0, total_length - FFT_SIZE + 1, HOP_SIZE)):
        frame = np.fft.irfft(cleaned_spectra[index], n=FFT_SIZE) * window
        output[start : start + FFT_SIZE] += frame
        normalization[start : start + FFT_SIZE] += window * window

    valid = normalization > 1e-10
    output[valid] /= normalization[valid]
    return output[pad : pad + len(samples)]


def moving_rms(samples: np.ndarray, window_size: int) -> np.ndarray:
    kernel = np.ones(window_size) / float(window_size)
    return np.sqrt(np.convolve(samples * samples, kernel, mode="same"))


def isolate_transient(
    samples: np.ndarray,
    sample_rate: int,
    source_noise_rms: float,
) -> tuple[np.ndarray, int, int]:
    envelope = moving_rms(samples, max(1, round(sample_rate * 0.0015)))
    peak_index = int(np.argmax(envelope))
    threshold = max(source_noise_rms * 4.5, float(envelope[peak_index]) * 0.045)
    quiet_run = max(1, round(sample_rate * 0.003))

    start = peak_index
    while start > 0:
        quiet_start = max(0, start - quiet_run)
        if np.all(envelope[quiet_start:start] < threshold):
            break
        start -= 1

    end = peak_index
    while end < len(samples) - 1:
        quiet_end = min(len(samples), end + quiet_run)
        if np.all(envelope[end:quiet_end] < threshold):
            break
        end += 1

    start = max(0, start - round(sample_rate * 0.003))
    end = min(len(samples), end + round(sample_rate * 0.007))

    maximum_length = round(sample_rate * 0.075)
    if end - start > maximum_length:
        start = max(0, peak_index - round(sample_rate * 0.030))
        end = min(len(samples), start + maximum_length)

    isolated = samples[start:end].copy()
    fade_in = min(len(isolated), max(1, round(sample_rate * 0.0015)))
    fade_out = min(len(isolated), max(1, round(sample_rate * 0.004)))
    isolated[:fade_in] *= np.sin(np.linspace(0.0, np.pi / 2.0, fade_in)) ** 2
    isolated[-fade_out:] *= np.cos(np.linspace(0.0, np.pi / 2.0, fade_out)) ** 2
    return isolated, start, end


def rms_db(samples: np.ndarray) -> float:
    if not len(samples):
        return -120.0
    rms = math.sqrt(float(np.mean(samples * samples)))
    return 20.0 * math.log10(max(rms, 1e-12))


def edge_rms_db(samples: np.ndarray, sample_rate: int) -> float:
    edge_size = min(len(samples) // 2, max(1, round(sample_rate * 0.004)))
    return rms_db(np.concatenate((samples[:edge_size], samples[-edge_size:])))


def clean_clip(
    source_path: Path,
    destination_path: Path,
    expected_sample_rate: int,
    profile: np.ndarray,
    source_noise_rms: float,
) -> dict[str, object]:
    sample_rate, original = read_pcm16_mono(source_path)
    if sample_rate != expected_sample_rate:
        raise ValueError(
            f"Sample-rate mismatch for {source_path}: {sample_rate} != {expected_sample_rate}"
        )

    original_peak = float(np.max(np.abs(original)))
    denoised = spectral_denoise(original, sample_rate, profile)
    cleaned, start, end = isolate_transient(denoised, sample_rate, source_noise_rms)

    cleaned_peak = float(np.max(np.abs(cleaned)))
    if cleaned_peak > 0.0 and original_peak > 0.0:
        cleaned *= min(1.0, original_peak / cleaned_peak)

    write_pcm16_mono(destination_path, sample_rate, cleaned)
    return {
        "file": source_path.name,
        "originalDurationMs": round(len(original) * 1000.0 / sample_rate, 1),
        "cleanedDurationMs": round(len(cleaned) * 1000.0 / sample_rate, 1),
        "originalEdgeRmsDb": round(edge_rms_db(original, sample_rate), 1),
        "cleanedEdgeRmsDb": round(edge_rms_db(cleaned, sample_rate), 1),
        "keptRangeMs": [
            round(start * 1000.0 / sample_rate, 1),
            round(end * 1000.0 / sample_rate, 1),
        ],
    }


def main() -> int:
    args = parse_args()
    sources = parse_noise_sources(args.noise_source)
    profiles = {prefix: noise_profile(path) for prefix, path in sources.items()}
    clips = sorted(args.input_dir.glob("*.wav"))
    if not clips:
        raise ValueError(f"No WAV clips found in {args.input_dir}")

    report = []
    for clip_path in clips:
        prefix = next((key for key in sources if clip_path.name.startswith(f"{key}-")), None)
        if prefix is None:
            raise ValueError(f"No noise source matches {clip_path.name}")
        sample_rate, profile, noise_rms = profiles[prefix]
        report.append(
            clean_clip(
                clip_path,
                args.output_dir / clip_path.name,
                sample_rate,
                profile,
                noise_rms,
            )
        )

    report_path = args.output_dir / "cleanup-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Cleaned {len(report)} clips into {args.output_dir}")
    print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
