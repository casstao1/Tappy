# Tappy Clip Lab

Local review workspace for short Tappy sound candidates.

## Run

```bash
npm install
npm start
```

Open `http://127.0.0.1:4177`.

The server keeps ratings, names, and key assignments in `data/state.json`. Deleted clips move to `trash/` until they are permanently removed. Exporting creates a dated ZIP in `exports/` containing every rated clip and a manifest.

Added audio is normalized to mono 48 kHz PCM WAV. Recordings longer than 1.5 seconds are automatically split into transient candidates; shorter files are added as individual clips.
