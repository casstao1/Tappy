#!/usr/bin/env python3
from __future__ import annotations

import html
import random
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path


ROOT = Path("/Users/castao/Desktop/KeyboardSoundApp")
BUNDLED_SOUNDS = ROOT / "Tappy" / "Resources" / "BundledSounds"
OUTPUT_DIR = ROOT / "premium_demo_clips"
REVIEW_BOARD = ROOT / "review_boards" / "premium-demo-review.html"

TARGET_RATE = 44_100
TARGET_CHANNELS = 2
TARGET_WIDTH = 2
TARGET_SECONDS = 10.0

PACKS = [
    ("sword-battle", "Sword Battle"),
    ("bubble", "Bubble"),
    ("analog-stopwatch", "Analog Stopwatch"),
    ("stars", "Stars"),
    ("wood-brush", "Wood Brush"),
    ("fart", "Fart"),
]

# 20 mostly-default events with some special keys sprinkled in.
EVENT_PATTERN = [
    "default",
    "default",
    "default",
    "default",
    "modifier",
    "default",
    "default",
    "space",
    "default",
    "default",
    "delete",
    "default",
    "default",
    "modifier",
    "default",
    "space",
    "default",
    "default",
    "return",
    "default",
]

GAP_PATTERN_SECONDS = [
    0.21,
    0.16,
    0.15,
    0.19,
    0.17,
    0.15,
    0.22,
    0.17,
    0.15,
    0.21,
    0.16,
    0.15,
    0.19,
    0.18,
    0.15,
    0.22,
    0.16,
    0.15,
    0.26,
    0.18,
]

PACK_BLURBS = {
    "sword-battle": "Fast battle slashes with a few heavier utility hits mixed in.",
    "bubble": "Soft glossy pops with airy spaces and lighter special keys.",
    "analog-stopwatch": "Mechanical tick-style typing with punchier stopwatch accents.",
    "stars": "Bright UI-style taps with sparkly special keys dropped into the rhythm.",
    "wood-brush": "Soft woody swipes with gentle non-default keys blended through.",
    "fart": "Comic blurps trimmed into a denser mostly-default typing rhythm.",
}


def ffmpeg_path() -> str:
    binary = shutil.which("ffmpeg")
    if not binary:
        raise RuntimeError("ffmpeg is required to build premium demo snippets.")
    return binary


def load_normalized_pcm(path: Path, ffmpeg: str) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
        temp_path = Path(temp_file.name)

    try:
        subprocess.run(
            [
                ffmpeg,
                "-y",
                "-loglevel",
                "error",
                "-i",
                str(path),
                "-acodec",
                "pcm_s16le",
                "-ac",
                str(TARGET_CHANNELS),
                "-ar",
                str(TARGET_RATE),
                str(temp_path),
            ],
            check=True,
        )
        with wave.open(str(temp_path), "rb") as wav_file:
            params = (
                wav_file.getnchannels(),
                wav_file.getsampwidth(),
                wav_file.getframerate(),
            )
            expected = (TARGET_CHANNELS, TARGET_WIDTH, TARGET_RATE)
            if params != expected:
                raise RuntimeError(f"Unexpected normalized parameters for {path}: {params}")
            return wav_file.readframes(wav_file.getnframes())
    finally:
        temp_path.unlink(missing_ok=True)


def silence(seconds: float) -> bytes:
    frame_count = int(round(seconds * TARGET_RATE))
    return b"\x00" * frame_count * TARGET_CHANNELS * TARGET_WIDTH


def build_pack_demo(pack_id: str, pack_name: str, ffmpeg: str) -> tuple[Path, dict[str, int]]:
    pack_dir = BUNDLED_SOUNDS / pack_id
    category_files = {}
    for category in ["default", "space", "return", "delete", "modifier"]:
        files = sorted((pack_dir / category).glob("*.wav"))
        if not files:
            raise RuntimeError(f"Missing {category} sounds for {pack_name}")
        category_files[category] = files

    category_usage = {key: 0 for key in category_files}
    assembled = bytearray()
    assembled.extend(silence(0.12))

    rng = random.Random(pack_id)
    category_positions = {key: 0 for key in category_files}

    for index, category in enumerate(EVENT_PATTERN):
        files = category_files[category]
        position = category_positions[category]
        category_positions[category] += 1
        # Cycle through files but offset the start per-pack for some variation.
        file_index = (position + rng.randint(0, len(files) - 1)) % len(files)
        source = files[file_index]
        assembled.extend(load_normalized_pcm(source, ffmpeg))
        category_usage[category] += 1
        assembled.extend(silence(GAP_PATTERN_SECONDS[index]))

    target_frames = int(TARGET_SECONDS * TARGET_RATE)
    target_bytes = target_frames * TARGET_CHANNELS * TARGET_WIDTH
    if len(assembled) < target_bytes:
        assembled.extend(b"\x00" * (target_bytes - len(assembled)))
    else:
        del assembled[target_bytes:]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / f"{pack_id}-demo.wav"
    with wave.open(str(output_path), "wb") as wav_file:
        wav_file.setnchannels(TARGET_CHANNELS)
        wav_file.setsampwidth(TARGET_WIDTH)
        wav_file.setframerate(TARGET_RATE)
        wav_file.writeframes(bytes(assembled))

    return output_path, category_usage


def render_review_page(entries: list[tuple[str, str, Path, dict[str, int]]]) -> None:
    cards = []
    for pack_id, pack_name, audio_path, usage in entries:
        rel_audio = audio_path.relative_to(ROOT).as_posix()
        usage_text = (
            f"{usage['default']} default, "
            f"{usage['space']} space, "
            f"{usage['return']} return, "
            f"{usage['delete']} delete, "
            f"{usage['modifier']} modifier"
        )
        cards.append(
            f"""
            <section class="card">
              <div class="meta">
                <div>
                  <h2>{html.escape(pack_name)}</h2>
                  <p>{html.escape(PACK_BLURBS.get(pack_id, '10-second premium pack demo.'))}</p>
                </div>
                <span class="chip">20 strokes</span>
              </div>
              <audio controls preload="none" src="../{html.escape(rel_audio)}"></audio>
              <div class="stats">{html.escape(usage_text)}</div>
            </section>
            """.strip()
        )

    page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Premium Demo Review</title>
  <style>
    :root {{
      --bg-a: #1a1040;
      --bg-b: #0e0a25;
      --panel: rgba(18, 13, 39, 0.88);
      --panel-border: rgba(143, 111, 255, 0.22);
      --text: #f3efff;
      --muted: #b5acd7;
      --accent: #8f6fff;
      --chip: rgba(143, 111, 255, 0.14);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, #392089 0%, transparent 38%),
        radial-gradient(circle at bottom right, #132a61 0%, transparent 34%),
        linear-gradient(135deg, var(--bg-a), var(--bg-b));
      padding: 40px 24px 80px;
    }}
    .wrap {{
      max-width: 980px;
      margin: 0 auto;
    }}
    h1 {{
      margin: 0 0 10px;
      font-size: 48px;
      line-height: 1;
    }}
    .intro {{
      margin: 0 0 28px;
      color: var(--muted);
      font-size: 18px;
      max-width: 760px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 18px;
    }}
    .card {{
      background: var(--panel);
      border: 1px solid var(--panel-border);
      border-radius: 22px;
      padding: 22px;
      box-shadow: 0 18px 40px rgba(0, 0, 0, 0.25);
      backdrop-filter: blur(10px);
    }}
    .meta {{
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 16px;
    }}
    h2 {{
      margin: 0 0 6px;
      font-size: 24px;
    }}
    p {{
      margin: 0;
      color: var(--muted);
      line-height: 1.45;
    }}
    .chip {{
      flex: none;
      padding: 8px 10px;
      border-radius: 999px;
      background: var(--chip);
      color: #d7ceff;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.03em;
      text-transform: uppercase;
    }}
    audio {{
      width: 100%;
      margin: 8px 0 14px;
    }}
    .stats {{
      color: #d7ceff;
      font-size: 14px;
    }}
  </style>
</head>
<body>
  <main class="wrap">
    <h1>Premium Demo Review</h1>
    <p class="intro">Each premium pack has one generated 10-second typing snippet with 20 keystrokes, mostly default hits with a few non-default keys sprinkled in. Review these first, then I’ll wire the app to use approved demo clips instead of live premium typing.</p>
    <div class="grid">
      {' '.join(cards)}
    </div>
  </main>
</body>
</html>
"""
    REVIEW_BOARD.write_text(page, encoding="utf-8")


def main() -> None:
    ffmpeg = ffmpeg_path()
    entries = []
    for pack_id, pack_name in PACKS:
        output_path, usage = build_pack_demo(pack_id, pack_name, ffmpeg)
        entries.append((pack_id, pack_name, output_path, usage))
    render_review_page(entries)
    print(f"Built {len(entries)} premium demo clips in {OUTPUT_DIR}")
    print(f"Review board: {REVIEW_BOARD}")


if __name__ == "__main__":
    main()
