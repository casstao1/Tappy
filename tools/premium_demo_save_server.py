#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HOST = "127.0.0.1"
PORT = 8765
OUTPUT_DIR = Path("/Users/castao/Desktop/KeyboardSoundApp/premium_demo_uploads")


class Handler(BaseHTTPRequestHandler):
    server_version = "TappyPremiumDemoSave/1.0"

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self._send_json(200, {"ok": True})

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"ok": True, "output_dir": str(OUTPUT_DIR)})
            return
        self._send_json(404, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:
        if self.path != "/save":
            self._send_json(404, {"ok": False, "error": "Not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
            filename = Path(payload["filename"]).name
            data_b64 = payload["data"]
        except Exception as exc:
            self._send_json(400, {"ok": False, "error": f"Invalid payload: {exc}"})
            return

        try:
            blob = base64.b64decode(data_b64)
        except Exception as exc:
            self._send_json(400, {"ok": False, "error": f"Invalid base64: {exc}"})
            return

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        output_path = OUTPUT_DIR / filename
        output_path.write_bytes(blob)
        self._send_json(200, {"ok": True, "path": str(output_path), "bytes": len(blob)})


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Serving premium demo save bridge on http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
