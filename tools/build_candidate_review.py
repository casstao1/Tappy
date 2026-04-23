#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path

BUCKETS = ["available", "default", "space", "return", "delete", "modifier"]
EXPORT_BUCKETS = ["default", "space", "return", "delete", "modifier"]
REMOVED_BUCKET = "removed"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a local candidate review board.")
    parser.add_argument("--title", required=True, help="Display title for the review page")
    parser.add_argument("--candidates", required=True, type=Path, help="Root candidates directory")
    parser.add_argument("--selection", required=True, type=Path, help="Pack selection JSON file")
    parser.add_argument("--output", required=True, type=Path, help="Output HTML file path")
    return parser.parse_args()


def load_selection(path: Path) -> dict[str, list[str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    by_path: dict[str, list[str]] = {}
    for bucket, entries in data.items():
        for entry in entries:
            key = f"{entry['group']}/{entry['file']}"
            by_path.setdefault(key, []).append(bucket)
    return by_path


def build_cards(candidates_root: Path, output_path: Path, selection_map: dict[str, list[str]]) -> tuple[str, str]:
    cards: list[str] = []
    flat_paths: list[str] = []

    groups = sorted(
        [
            path for path in candidates_root.iterdir()
            if path.is_dir() and not path.name.startswith(".")
        ],
        key=lambda item: item.name.lower(),
    )

    for group in groups:
        audio_files = sorted(group.glob("*.wav"))
        if not audio_files:
            continue

        for audio_file in audio_files:
            relative_key = f"{group.name}/{audio_file.name}"
            selected_buckets = selection_map.get(relative_key, [])
            initial_bucket = selected_buckets[0] if selected_buckets else "available"
            audio_src = html.escape(Path(os.path.relpath(audio_file, output_path.parent)).as_posix())
            cards.append(
                f"""
                <article class="card" draggable="true" data-path="{html.escape(relative_key)}" data-bucket="{html.escape(initial_bucket)}">
                  <div class="card-header">
                    <div class="label">{html.escape(group.name)}</div>
                    <div class="file-actions">
                      <div class="file">{html.escape(audio_file.name)}</div>
                      <button type="button" class="remove-card" title="Hide this sound">Remove</button>
                    </div>
                  </div>
                  <audio controls preload="none" src="{audio_src}"></audio>
                  <div class="bucket-pill">{html.escape(initial_bucket)}</div>
                </article>
                """
            )
            flat_paths.append(relative_key)

    return "".join(cards), json.dumps(flat_paths)


def build_html(title: str, cards_markup: str, all_paths_json: str, storage_key: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #11131a;
      --panel: #1a1d26;
      --panel-2: #232734;
      --text: #f3f5fa;
      --muted: #adb6c8;
      --accent: #8fb8ff;
      --border: rgba(255,255,255,0.08);
    }}
    body {{
      margin: 0;
      font-family: ui-rounded, system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      background: linear-gradient(180deg, #0f1218 0%, #171b24 100%);
      color: var(--text);
    }}
    .shell {{
      max-width: 1600px;
      margin: 0 auto;
      padding: 28px 24px 48px;
    }}
    .topbar {{
      position: sticky;
      top: 0;
      z-index: 10;
      backdrop-filter: blur(18px);
      background: rgba(15,18,24,0.84);
      border-bottom: 1px solid var(--border);
      margin: -28px -24px 24px;
      padding: 18px 24px 16px;
    }}
    h1 {{
      margin: 0 0 6px;
      font-size: 34px;
      line-height: 1.05;
    }}
    .sub {{
      margin: 0;
      color: var(--muted);
      font-size: 15px;
    }}
    .controls {{
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 16px;
    }}
    button {{
      appearance: none;
      border: 0;
      border-radius: 14px;
      padding: 10px 14px;
      background: var(--panel-2);
      color: var(--text);
      font: inherit;
      cursor: pointer;
    }}
    button.primary {{
      background: var(--accent);
      color: #0e1730;
      font-weight: 700;
    }}
    .output {{
      margin-top: 16px;
      width: 100%;
      min-height: 120px;
      border-radius: 18px;
      border: 1px solid var(--border);
      background: var(--panel);
      color: var(--text);
      padding: 14px 16px;
      font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
      resize: vertical;
      box-sizing: border-box;
    }}
    .board {{
      display: grid;
      grid-template-columns: repeat(6, minmax(240px, 1fr));
      gap: 16px;
      align-items: start;
      margin-top: 18px;
      overflow-x: auto;
      padding-bottom: 20px;
    }}
    .column {{
      min-height: 520px;
      background: rgba(255,255,255,0.035);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 14px;
      box-sizing: border-box;
    }}
    .column.drag-over {{
      border-color: rgba(143,184,255,0.65);
      box-shadow: inset 0 0 0 1px rgba(143,184,255,0.22);
      background: rgba(143,184,255,0.08);
    }}
    .column-header {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 12px;
    }}
    .column-title {{
      margin: 0;
      font-size: 15px;
      color: #e7edf8;
      text-transform: capitalize;
    }}
    .count {{
      color: var(--muted);
      font-size: 12px;
      padding: 5px 8px;
      border-radius: 999px;
      background: rgba(255,255,255,0.06);
    }}
    .dropzone {{
      display: flex;
      flex-direction: column;
      gap: 12px;
      min-height: 440px;
    }}
    .card {{
      background: rgba(255,255,255,0.04);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 14px;
      cursor: grab;
    }}
    .card.dragging {{
      opacity: 0.45;
    }}
    .card-header {{
      display: flex;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 10px;
      align-items: baseline;
    }}
    .label {{
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #9ab0d9;
    }}
    .file {{
      font-size: 12px;
      color: var(--muted);
      text-align: right;
      word-break: break-all;
    }}
    .file-actions {{
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: 6px;
    }}
    audio {{
      width: 100%;
      margin-bottom: 10px;
    }}
    .bucket-pill {{
      display: inline-flex;
      align-items: center;
      border-radius: 999px;
      padding: 6px 10px;
      background: rgba(143,184,255,0.14);
      color: #cfe0ff;
      font-size: 12px;
      text-transform: capitalize;
    }}
    .hidden-cards {{
      display: none;
    }}
    .remove-card {{
      padding: 6px 9px;
      border-radius: 10px;
      font-size: 11px;
      background: rgba(255,255,255,0.08);
      color: var(--muted);
    }}
    @media (max-width: 1300px) {{
      .board {{
        grid-template-columns: repeat(6, 280px);
      }}
    }}
  </style>
</head>
<body>
  <div class="shell">
    <div class="topbar">
      <h1>{html.escape(title)}</h1>
      <p class="sub">Play clips, assign a bucket, then copy the exported text back into chat.</p>
      <div class="controls">
        <button class="primary" id="copyButton">Copy Reply Text</button>
        <button id="refreshButton">Refresh Export</button>
        <button id="clearButton">Clear All</button>
        <button id="restoreButton">Restore Hidden (0)</button>
      </div>
      <textarea id="output" class="output" spellcheck="false"></textarea>
    </div>
    <div class="board" id="board">
      {"".join(
          f'''
          <section class="column" data-bucket="{bucket}">
            <div class="column-header">
              <h2 class="column-title">{bucket}</h2>
              <span class="count" id="count-{bucket}">0</span>
            </div>
            <div class="dropzone" id="zone-{bucket}" data-bucket="{bucket}"></div>
          </section>
          '''
          for bucket in BUCKETS
      )}
    </div>
    <div class="hidden-cards" id="cardStore">
      {cards_markup}
    </div>
  </div>
  <script>
    const storageKey = {json.dumps(storage_key)};
    const allPaths = {all_paths_json};
    const output = document.getElementById('output');
    const cardStore = document.getElementById('cardStore');
    const restoreButton = document.getElementById('restoreButton');
    const zones = Object.fromEntries(
      Array.from(document.querySelectorAll('.dropzone')).map((zone) => [zone.dataset.bucket, zone])
    );
    let draggedCard = null;

    function bucketForCard(card) {{
      return card.dataset.bucket || 'available';
    }}

    function setCardBucket(card, bucket) {{
      card.dataset.bucket = bucket;
      const pill = card.querySelector('.bucket-pill');
      if (pill) pill.textContent = bucket;
    }}

    function updateCounts() {{
      for (const bucket of {json.dumps(BUCKETS)}) {{
        const zone = zones[bucket];
        const count = zone ? zone.querySelectorAll('.card').length : 0;
        const badge = document.getElementById(`count-${{bucket}}`);
        if (badge) badge.textContent = String(count);
      }}
      const removedCount = cardStore.querySelectorAll('.card[data-bucket="removed"]').length;
      restoreButton.textContent = `Restore Hidden (${{removedCount}})`;
    }}

    function exportText() {{
      const grouped = {{
        default: [],
        space: [],
        return: [],
        delete: [],
        modifier: []
      }};

      document.querySelectorAll('.dropzone .card').forEach((card) => {{
        const path = card.dataset.path;
        const bucket = bucketForCard(card);
        if (bucket !== 'available') {{
          grouped[bucket].push(path);
        }}
      }});

      const lines = [];
      for (const bucket of {json.dumps(EXPORT_BUCKETS)}) {{
        if (grouped[bucket].length > 0) {{
          lines.push(`${{bucket}}: ${{grouped[bucket].join(', ')}}`);
        }}
      }}
      output.value = lines.join('\\n');
    }}

    function saveState() {{
      const state = {{}};
      document.querySelectorAll('.dropzone .card').forEach((card) => {{
        state[card.dataset.path] = bucketForCard(card);
      }});
      localStorage.setItem(storageKey, JSON.stringify(state));
      updateCounts();
      exportText();
    }}

    function placeCard(card, bucket) {{
      const targetBucket = bucket === {json.dumps(REMOVED_BUCKET)} ? {json.dumps(REMOVED_BUCKET)} : (zones[bucket] ? bucket : 'available');
      setCardBucket(card, targetBucket);
      if (targetBucket === {json.dumps(REMOVED_BUCKET)}) {{
        cardStore.appendChild(card);
      }} else {{
        zones[targetBucket].appendChild(card);
      }}
    }}

    function attachDragHandlers(card) {{
      card.addEventListener('dragstart', () => {{
        draggedCard = card;
        card.classList.add('dragging');
      }});
      card.addEventListener('dragend', () => {{
        card.classList.remove('dragging');
        draggedCard = null;
        document.querySelectorAll('.column').forEach((column) => column.classList.remove('drag-over'));
      }});
      const removeButton = card.querySelector('.remove-card');
      if (removeButton) {{
        removeButton.addEventListener('click', () => {{
          placeCard(card, {json.dumps(REMOVED_BUCKET)});
          saveState();
        }});
      }}
    }}

    function loadStateAndRender() {{
      const cards = Array.from(document.querySelectorAll('#cardStore .card'));
      const raw = localStorage.getItem(storageKey);
      let state = null;
      for (const card of cards) {{
        attachDragHandlers(card);
      }}

      if (!raw) {{
        cards.forEach((card) => placeCard(card, bucketForCard(card)));
        saveState();
        return;
      }}

      try {{
        state = JSON.parse(raw);
      }} catch (_error) {{
        state = null;
      }}

      cards.forEach((card) => {{
        placeCard(card, state?.[card.dataset.path] || bucketForCard(card));
      }});
      saveState();
    }}

    document.getElementById('refreshButton').addEventListener('click', exportText);
    document.getElementById('clearButton').addEventListener('click', () => {{
      document.querySelectorAll('.dropzone .card').forEach((card) => placeCard(card, 'available'));
      saveState();
    }});
    restoreButton.addEventListener('click', () => {{
      cardStore.querySelectorAll('.card[data-bucket="removed"]').forEach((card) => placeCard(card, 'available'));
      saveState();
    }});
    document.getElementById('copyButton').addEventListener('click', async () => {{
      exportText();
      try {{
        await navigator.clipboard.writeText(output.value);
      }} catch (_error) {{
        output.focus();
        output.select();
      }}
    }});

    document.querySelectorAll('.column').forEach((column) => {{
      column.addEventListener('dragover', (event) => {{
        event.preventDefault();
        column.classList.add('drag-over');
      }});
      column.addEventListener('dragleave', () => {{
        column.classList.remove('drag-over');
      }});
      column.addEventListener('drop', (event) => {{
        event.preventDefault();
        column.classList.remove('drag-over');
        if (!draggedCard) return;
        placeCard(draggedCard, column.dataset.bucket);
        saveState();
      }});
    }});

    loadStateAndRender();
  </script>
</body>
</html>
"""


def main() -> int:
    args = parse_args()
    selection_map = load_selection(args.selection)
    cards_markup, all_paths_json = build_cards(args.candidates, args.output, selection_map)
    storage_key = f"candidate-review:{args.output.stem}"
    html_text = build_html(args.title, cards_markup, all_paths_json, storage_key)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(html_text, encoding="utf-8")
    print(f"Wrote review board to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
