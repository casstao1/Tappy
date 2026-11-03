#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path("/Users/castao/Desktop/Tappy")
BASE_SCRIPT = ROOT / "MarketingVideoPlugins/immersive-v2/build_audio.py"
OUTPUT = ROOT / "MarketingVideoPlugins/immersive-v3/audio/tappy-immersive-v3.wav"
SAMPLE_RATE = 48_000
DURATION = 17.0


spec = importlib.util.spec_from_file_location("tappy_immersive_v2_audio", BASE_SCRIPT)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load shared audio helpers from {BASE_SCRIPT}")

audio_helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audio_helpers)
audio_helpers.DURATION = DURATION


def main() -> None:
    master = np.zeros((round(DURATION * SAMPLE_RATE), 2), dtype=np.float64)
    libraries = {
        name: [
            audio_helpers.fade_clip(audio_helpers.normalize(audio_helpers.read_wav(path)))
            for path in paths
        ]
        for name, paths in audio_helpers.PACKS.items()
    }
    plastic_paths = [
        audio_helpers.SOUNDS / "default/default-01.wav",
        audio_helpers.SOUNDS / "default/default-02.wav",
        audio_helpers.SOUNDS / "default/default-04.wav",
        audio_helpers.SOUNDS / "default/default-06.wav",
    ]
    libraries["plastic"] = [
        audio_helpers.fade_clip(audio_helpers.normalize(audio_helpers.read_wav(path)))
        for path in plastic_paths
    ]
    audio_helpers.add_clip(master, audio_helpers.make_ambient(), 0.0, 0.048)

    # Logo, explainer line, and keyboard assembly use neutral tactile UI sounds.
    audio_helpers.add_neutral_tail(master, 0.34, 176.0, 0.2)
    audio_helpers.add_clip(master, audio_helpers.make_neutral_tap(126.0, 0.19), 0.75, 0.06)
    for index, at in enumerate((1.48, 1.62, 1.76, 1.9, 2.05)):
        audio_helpers.add_clip(
            master,
            audio_helpers.make_neutral_tap(142.0 + index * 14.0, 0.1),
            at,
            0.075 + index * 0.008,
            -0.16 + index * 0.08,
        )

    # Wet Squishy Pop grows directly out of the assembled keyboard.
    audio_helpers.add_clip(master, audio_helpers.make_whoosh(0.24, 901, 1), 2.07, 0.037)
    audio_helpers.rapid_word(master, libraries["wet"], 2.35, 7, 0.1, 0.49, 0)
    audio_helpers.rapid_word(master, libraries["wet"], 3.15, 8, 0.095, 0.5, 1)
    audio_helpers.rapid_word(master, libraries["wet"], 4.05, 7, 0.105, 0.49, 2)

    # Every showcased sound remains in one uninterrupted passage.
    audio_helpers.add_clip(master, audio_helpers.make_whoosh(0.28, 902, -1), 4.84, 0.044)
    audio_helpers.rapid_word(master, libraries["wax"], 5.1, 7, 0.105, 0.56, 0)
    audio_helpers.rapid_word(master, libraries["wax"], 5.92, 7, 0.1, 0.56, 1)
    audio_helpers.rapid_word(master, libraries["wax"], 6.75, 7, 0.105, 0.55, 2)

    audio_helpers.add_clip(master, audio_helpers.make_whoosh(0.3, 903, 1), 7.58, 0.043)
    audio_helpers.rapid_word(master, libraries["plastic"], 7.85, 7, 0.105, 1.0, 0)
    audio_helpers.rapid_word(master, libraries["plastic"], 8.67, 7, 0.1, 1.0, 1)
    audio_helpers.rapid_word(master, libraries["plastic"], 9.5, 7, 0.105, 1.0, 2)

    audio_helpers.add_clip(master, audio_helpers.make_whoosh(0.28, 904, -1), 10.36, 0.04)
    audio_helpers.rapid_word(master, libraries["bubble"], 10.6, 8, 0.095, 0.23, 0)
    audio_helpers.rapid_word(master, libraries["bubble"], 11.42, 8, 0.095, 0.23, 1)
    audio_helpers.rapid_word(master, libraries["bubble"], 12.24, 7, 0.1, 0.23, 2)

    # The original restrained logo and App Store ending.
    audio_helpers.add_neutral_tail(master, 12.95, 152.0, 0.22)
    audio_helpers.add_clip(master, audio_helpers.make_whoosh(0.32, 905, 1), 13.34, 0.027)
    audio_helpers.add_neutral_tail(master, 14.1, 118.0, 0.13)
    audio_helpers.add_neutral_tail(master, 15.7, 202.0, 0.13)

    master = np.tanh(master * 1.24)
    peak = float(np.max(np.abs(master)))
    if peak > 0.76:
        master *= 0.76 / peak
    encoded = np.round(np.clip(master, -1.0, 1.0) * 32767.0).astype("<i2")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(SAMPLE_RATE)
        target.writeframes(encoded.tobytes())

    rms = math.sqrt(float(np.mean(master * master)))
    print(
        f"immersive-v3: {DURATION:.2f}s peak={np.max(np.abs(master)):.4f} "
        f"rms={rms:.4f} path={OUTPUT}"
    )


if __name__ == "__main__":
    main()
