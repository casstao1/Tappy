#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path

BUCKETS = ["default", "space", "return", "delete", "modifier"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a final selected-only local pack review board.")
    parser.add_argument("--title", required=True, help="Display title for the review page")
    parser.add_argument("--candidates", required=True, type=Path, help="Root candidates directory")
    parser.add_argument("--selection", required=True, type=Path, help="Pack selection JSON file")
    parser.add_argument("--output", required=True, type=Path, help="Output HTML file path")
    return parser.parse_args()


def load_selection(path: Path) -> dict[str, list[tuple[str, str]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        bucket: [(entry["group"], entry["file"]) for entry in data.get(bucket, [])]
        for bucket in BUCKETS
    }


def build_cards(
    candidates_root: Path,
    output_path: Path,
    selection: dict[str, list[tuple[str, str]]],
) -> tuple[str, str]:
    columns: list[str] = []
    state_by_bucket: dict[str, list[dict[str, str]]] = {}

    for bucket in BUCKETS:
        entries = selection.get(bucket, [])
        cards: list[str] = []

        for group_name, file_name in entries:
            audio_file = candidates_root / group_name / file_name
            if not audio_file.exists():
                continue

            audio_src = html.escape(Path(os.path.relpath(audio_file, output_path.parent)).as_posix())
            cards.append(
                f"""
                <article class="card" draggable="true" data-path="{html.escape(group_name)}/{html.escape(file_name)}" data-group="{html.escape(group_name)}" data-file="{html.escape(file_name)}" data-bucket="{html.escape(bucket)}">
                  <div class="card-header">
                    <div class="label">{html.escape(group_name)}</div>
                    <div class="file">{html.escape(file_name)}</div>
                  </div>
                  <audio controls preload="none" src="{audio_src}"></audio>
                </article>
                """
            )

        state_by_bucket[bucket] = [
            {"group": group_name, "file": file_name}
            for group_name, file_name in entries
            if (candidates_root / group_name / file_name).exists()
        ]

        columns.append(
            f"""
            <section class="column" data-bucket="{html.escape(bucket)}">
              <div class="column-header">
                <h2 class="column-title">{html.escape(bucket)}</h2>
                <span class="count" id="count-{html.escape(bucket)}">{len(entries)}</span>
              </div>
              <div class="column-cards" id="zone-{html.escape(bucket)}" data-bucket="{html.escape(bucket)}">
                {''.join(cards)}
                <div class="empty"{'' if not cards else ' hidden'}>No clips selected</div>
              </div>
            </section>
            """
        )

    return "".join(columns), json.dumps(state_by_bucket)


def build_html(title: str, columns_markup: str, initial_state_json: str, storage_key: str) -> str:
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
      align-items: center;
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
    .save-state {{
      color: var(--muted);
      font-size: 13px;
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
      grid-template-columns: repeat(5, minmax(240px, 1fr));
      gap: 16px;
      align-items: start;
      margin-top: 18px;
      overflow-x: auto;
      padding-bottom: 20px;
    }}
    .column {{
      min-height: 420px;
      background: rgba(255,255,255,0.035);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 14px;
      box-sizing: border-box;
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
    .column-cards {{
      display: flex;
      flex-direction: column;
      gap: 12px;
      min-height: 260px;
    }}
    .column.drag-over {{
      border-color: rgba(143,184,255,0.65);
      box-shadow: inset 0 0 0 1px rgba(143,184,255,0.22);
      background: rgba(143,184,255,0.08);
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
    .empty {{
      color: var(--muted);
      padding: 10px 2px;
      font-size: 14px;
    }}
    .hidden {{
      display: none;
    }}
    audio {{
      width: 100%;
    }}
    @media (max-width: 1300px) {{
      .board {{
        grid-template-columns: repeat(5, 280px);
      }}
    }}
  </style>
</head>
<body>
  <div class="shell">
    <div class="topbar">
      <h1>{html.escape(title)}</h1>
      <p class="sub">Final selected farming clips grouped by live key bucket.</p>
      <div class="controls">
        <button class="primary" id="saveButton">Save Changes</button>
        <button id="copyButton">Copy Mapping</button>
        <button id="resetButton">Reset to Original</button>
        <span class="save-state" id="saveState">Not saved</span>
      </div>
      <textarea id="output" class="output" spellcheck="false"></textarea>
    </div>
    <div class="board">
      {columns_markup}
    </div>
  </div>
  <script>
    const buckets = {json.dumps(BUCKETS)};
    const storageKey = {json.dumps(storage_key)};
    const initialState = {initial_state_json};
    const output = document.getElementById('output');
    const saveStateLabel = document.getElementById('saveState');
    const zones = Object.fromEntries(
      buckets.map((bucket) => [bucket, document.getElementById(`zone-${{bucket}}`)])
    );
    let draggedCard = null;

    function updateCounts() {{
      for (const bucket of buckets) {{
        const zone = zones[bucket];
        const count = zone.querySelectorAll('.card').length;
        document.getElementById(`count-${{bucket}}`).textContent = String(count);
        const empty = zone.querySelector('.empty');
        if (empty) {{
          empty.classList.toggle('hidden', count > 0);
        }}
      }}
    }}

    function attachCardHandlers(card) {{
      card.addEventListener('dragstart', () => {{
        draggedCard = card;
        card.classList.add('dragging');
      }});
      card.addEventListener('dragend', () => {{
        card.classList.remove('dragging');
        draggedCard = null;
        document.querySelectorAll('.column').forEach((column) => column.classList.remove('drag-over'));
      }});
    }}

    function serializeBoard() {{
      const state = {{}};
      for (const bucket of buckets) {{
        state[bucket] = Array.from(zones[bucket].querySelectorAll('.card')).map((card) => ({{
          group: card.dataset.group,
          file: card.dataset.file,
        }}));
      }}
      return state;
    }}

    function exportText() {{
      const state = serializeBoard();
      const lines = [];
      for (const bucket of buckets) {{
        const entries = state[bucket];
        if (!entries.length) continue;
        lines.push(`${{bucket}}: ${{entries.map((entry) => `${{entry.group}}/${{entry.file}}`).join(', ')}}`);
      }}
      output.value = lines.join('\\n');
    }}

    function saveBoard() {{
      localStorage.setItem(storageKey, JSON.stringify(serializeBoard()));
      saveStateLabel.textContent = 'Saved';
      exportText();
      updateCounts();
    }}

    function placeCard(card, bucket) {{
      card.dataset.bucket = bucket;
      zones[bucket].appendChild(card);
    }}

    function renderState(state) {{
      const allCards = Array.from(document.querySelectorAll('.card'));
      allCards.forEach((card) => {{
        const bucket = card.dataset.bucket;
        if (zones[bucket]) {{
          zones[bucket].appendChild(card);
        }}
      }});

      for (const bucket of buckets) {{
        const desired = state[bucket] || [];
        desired.forEach((entry) => {{
          const card = allCards.find((candidate) =>
            candidate.dataset.group === entry.group && candidate.dataset.file === entry.file
          );
          if (card) {{
            placeCard(card, bucket);
          }}
        }});
      }}

      updateCounts();
      exportText();
    }}

    function resetBoard() {{
      localStorage.removeItem(storageKey);
      renderState(initialState);
      saveStateLabel.textContent = 'Reset to original';
    }}

    document.querySelectorAll('.card').forEach(attachCardHandlers);

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
        saveStateLabel.textContent = 'Unsaved changes';
        updateCounts();
        exportText();
      }});
    }});

    document.getElementById('saveButton').addEventListener('click', saveBoard);
    document.getElementById('copyButton').addEventListener('click', async () => {{
      exportText();
      try {{
        await navigator.clipboard.writeText(output.value);
      }} catch (_error) {{
        output.focus();
        output.select();
      }}
    }});
    document.getElementById('resetButton').addEventListener('click', resetBoard);

    const saved = localStorage.getItem(storageKey);
    if (saved) {{
      try {{
        renderState(JSON.parse(saved));
        saveStateLabel.textContent = 'Loaded saved changes';
      }} catch (_error) {{
        renderState(initialState);
        saveStateLabel.textContent = 'Save unavailable';
      }}
    }} else {{
      renderState(initialState);
    }}
  </script>
</body>
</html>
"""


def main() -> int:
    args = parse_args()
    selection = load_selection(args.selection)
    columns_markup, initial_state_json = build_cards(args.candidates, args.output, selection)
    html_text = build_html(
        args.title,
        columns_markup,
        initial_state_json,
        f"final-pack-review:{args.output.stem}",
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(html_text, encoding="utf-8")
    print(f"Wrote final review board to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
