#!/usr/bin/env node

"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { URL } = require("url");

const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const CLIPS_DIR = path.join(ROOT, "clips");
const SOURCES_DIR = path.join(ROOT, "sources", "uploads");
const SOURCE_WAV_DIR = path.join(ROOT, "source-wav", "uploads");
const TRASH_DIR = path.join(ROOT, "trash");
const DATA_DIR = path.join(ROOT, "data");
const EXPORTS_DIR = path.join(ROOT, "exports");
const STATE_PATH = path.join(DATA_DIR, "state.json");
const EXTRACTOR_PATH = path.resolve(ROOT, "..", "tools", "extract_tap_candidates.py");
const LUCIDE_PATH = path.join(ROOT, "node_modules", "lucide", "dist", "umd", "lucide.min.js");
const PORT = Number(process.env.PORT || 4177);
const HOST = process.env.HOST || "127.0.0.1";
const MAX_UPLOAD_BYTES = 128 * 1024 * 1024;
const CATEGORIES = new Set(["default", "space", "return", "delete", "modifier"]);
const AUDIO_EXTENSIONS = new Set([".wav", ".m4a", ".mp3", ".aiff", ".aif", ".caf"]);

for (const directory of [CLIPS_DIR, SOURCES_DIR, SOURCE_WAV_DIR, TRASH_DIR, DATA_DIR, EXPORTS_DIR]) {
  fs.mkdirSync(directory, { recursive: true });
}

function sendJson(response, statusCode, value) {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": body.length,
    "Cache-Control": "no-store",
  });
  response.end(body);
}

function sendError(response, statusCode, message) {
  sendJson(response, statusCode, { error: message });
}

function loadState() {
  try {
    const parsed = JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
    return parsed && parsed.clips ? parsed : { clips: {} };
  } catch (error) {
    if (error.code !== "ENOENT") {
      console.error("Could not read clip state:", error.message);
    }
    return { clips: {} };
  }
}

function saveState(state) {
  const temporaryPath = `${STATE_PATH}.tmp`;
  fs.writeFileSync(temporaryPath, `${JSON.stringify(state, null, 2)}\n`, "utf8");
  fs.renameSync(temporaryPath, STATE_PATH);
}

function safeRelative(input) {
  const value = String(input || "").replace(/\\/g, "/");
  const normalized = path.posix.normalize(value);
  if (!normalized || normalized === "." || normalized.startsWith("../") || path.posix.isAbsolute(normalized)) {
    throw new Error("Invalid file path");
  }
  return normalized;
}

function resolveWithin(root, relativePath) {
  const target = path.resolve(root, relativePath);
  const rootPrefix = `${path.resolve(root)}${path.sep}`;
  if (target !== path.resolve(root) && !target.startsWith(rootPrefix)) {
    throw new Error("Invalid file path");
  }
  return target;
}

function sanitizeSlug(value, fallback = "sound") {
  const cleaned = String(value || "")
    .normalize("NFKD")
    .replace(/[^a-zA-Z0-9._ -]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^[-.]+|[-.]+$/g, "")
    .toLowerCase();
  return cleaned || fallback;
}

function titleFromSlug(value) {
  return String(value || "")
    .split(/[-_]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function uniquePath(directory, fileName) {
  const extension = path.extname(fileName);
  const base = path.basename(fileName, extension);
  let candidate = path.join(directory, fileName);
  let counter = 2;
  while (fs.existsSync(candidate)) {
    candidate = path.join(directory, `${base}-${counter}${extension}`);
    counter += 1;
  }
  return candidate;
}

function walkWaveFiles(directory, root = directory) {
  if (!fs.existsSync(directory)) return [];
  const results = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkWaveFiles(absolutePath, root));
    } else if (entry.isFile() && path.extname(entry.name).toLowerCase() === ".wav") {
      results.push(path.relative(root, absolutePath).split(path.sep).join("/"));
    }
  }
  return results.sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
}

function readWaveInfo(filePath) {
  const buffer = fs.readFileSync(filePath);
  if (buffer.length < 44 || buffer.toString("ascii", 0, 4) !== "RIFF" || buffer.toString("ascii", 8, 12) !== "WAVE") {
    return { durationMs: 0, sampleRate: 0, channels: 0 };
  }

  let offset = 12;
  let byteRate = 0;
  let sampleRate = 0;
  let channels = 0;
  let dataBytes = 0;

  while (offset + 8 <= buffer.length) {
    const chunkId = buffer.toString("ascii", offset, offset + 4);
    const chunkSize = buffer.readUInt32LE(offset + 4);
    const chunkStart = offset + 8;
    if (chunkId === "fmt " && chunkSize >= 16 && chunkStart + 16 <= buffer.length) {
      channels = buffer.readUInt16LE(chunkStart + 2);
      sampleRate = buffer.readUInt32LE(chunkStart + 4);
      byteRate = buffer.readUInt32LE(chunkStart + 8);
    } else if (chunkId === "data") {
      dataBytes = Math.min(chunkSize, Math.max(0, buffer.length - chunkStart));
      break;
    }
    offset = chunkStart + chunkSize + (chunkSize % 2);
  }

  return {
    durationMs: byteRate > 0 ? Math.round((dataBytes / byteRate) * 1000) : 0,
    sampleRate,
    channels,
  };
}

function clipMetadata(relativePath, absolutePath, clipState, deleted = false) {
  const fileName = path.basename(relativePath);
  const source = relativePath.includes("/") ? relativePath.split("/")[0] : "uploads";
  const match = fileName.match(/^(\d+)_t([\d.]+)_score(\d+)\.wav$/i);
  const info = readWaveInfo(absolutePath);
  const defaultName = match
    ? `${titleFromSlug(source)} ${String(Number(match[1])).padStart(2, "0")}`
    : titleFromSlug(path.basename(fileName, path.extname(fileName)));
  const encodedPath = relativePath.split("/").map(encodeURIComponent).join("/");

  return {
    id: relativePath,
    fileName,
    source,
    sourceLabel: titleFromSlug(source),
    displayName: clipState.displayName || defaultName,
    durationMs: info.durationMs,
    sampleRate: info.sampleRate,
    channels: info.channels,
    sourceTime: match ? Number(match[2]) : null,
    score: match ? Number(match[3]) : null,
    rating: Number.isInteger(clipState.rating) ? clipState.rating : 0,
    category: CATEGORIES.has(clipState.category) ? clipState.category : "default",
    note: typeof clipState.note === "string" ? clipState.note : "",
    deleted,
    createdAt: clipState.createdAt || fs.statSync(absolutePath).birthtime.toISOString(),
    audioUrl: deleted
      ? `/trash-audio/${encodeURIComponent(clipState.trashName)}`
      : `/audio/${encodedPath}`,
  };
}

function listCatalog() {
  const state = loadState();
  let changed = false;
  const catalog = [];

  for (const relativePath of walkWaveFiles(CLIPS_DIR)) {
    const absolutePath = resolveWithin(CLIPS_DIR, relativePath);
    if (!state.clips[relativePath]) {
      state.clips[relativePath] = {
        rating: 0,
        category: "default",
        note: "",
        createdAt: fs.statSync(absolutePath).birthtime.toISOString(),
      };
      changed = true;
    }
    if (state.clips[relativePath].deleted) {
      state.clips[relativePath].deleted = false;
      delete state.clips[relativePath].trashName;
      changed = true;
    }
    catalog.push(clipMetadata(relativePath, absolutePath, state.clips[relativePath], false));
  }

  for (const [relativePath, clipState] of Object.entries(state.clips)) {
    if (!clipState.deleted || !clipState.trashName) continue;
    const trashedPath = resolveWithin(TRASH_DIR, clipState.trashName);
    if (fs.existsSync(trashedPath)) {
      catalog.push(clipMetadata(relativePath, trashedPath, clipState, true));
    }
  }

  if (changed) saveState(state);
  return catalog;
}

function readRequestBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    request.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_UPLOAD_BYTES) {
        reject(new Error("Upload exceeds the 128 MB limit"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    const detail = (result.stderr || result.stdout || result.error?.message || "Unknown command failure").trim();
    throw new Error(detail);
  }
  return result.stdout.trim();
}

function importAudio(originalName, body) {
  const extension = path.extname(originalName).toLowerCase();
  if (!AUDIO_EXTENSIONS.has(extension)) {
    throw new Error("Choose a WAV, M4A, MP3, AIFF, AIF, or CAF audio file");
  }

  const baseSlug = sanitizeSlug(path.basename(originalName, extension), "imported-sound");
  const sourcePath = uniquePath(SOURCES_DIR, `${baseSlug}${extension}`);
  fs.writeFileSync(sourcePath, body);
  const uniqueBase = path.basename(sourcePath, extension);
  const normalizedPath = uniquePath(SOURCE_WAV_DIR, `${uniqueBase}-mono.wav`);

  run("/usr/bin/afconvert", [
    "-f", "WAVE",
    "-d", "LEI16@48000",
    "-c", "1",
    sourcePath,
    normalizedPath,
  ]);

  const info = readWaveInfo(normalizedPath);
  if (info.durationMs <= 0) {
    throw new Error("The imported file did not contain readable audio");
  }

  if (info.durationMs > 1500) {
    const groupPath = uniquePath(CLIPS_DIR, uniqueBase);
    fs.mkdirSync(groupPath, { recursive: true });
    run("python3", [
      EXTRACTOR_PATH,
      normalizedPath,
      "--output-dir", groupPath,
      "--max-clips", "36",
      "--min-gap-ms", "120",
      "--pre-roll-ms", "18",
      "--min-length-ms", "75",
      "--max-length-ms", "240",
    ]);
    return { imported: walkWaveFiles(groupPath).length, mode: "recording" };
  }

  const uploadsDirectory = path.join(CLIPS_DIR, "uploads");
  fs.mkdirSync(uploadsDirectory, { recursive: true });
  const clipPath = uniquePath(uploadsDirectory, `${uniqueBase}.wav`);
  fs.copyFileSync(normalizedPath, clipPath);
  return { imported: 1, mode: "clip" };
}

function patchClip(relativePath, changes) {
  const safePath = safeRelative(relativePath);
  const state = loadState();
  if (!state.clips[safePath]) {
    throw new Error("Clip not found");
  }
  const clipState = state.clips[safePath];

  if (Object.prototype.hasOwnProperty.call(changes, "rating")) {
    const rating = Number(changes.rating);
    if (!Number.isInteger(rating) || rating < 0 || rating > 3) {
      throw new Error("Rating must be between 0 and 3");
    }
    clipState.rating = rating;
  }
  if (Object.prototype.hasOwnProperty.call(changes, "category")) {
    if (!CATEGORIES.has(changes.category)) {
      throw new Error("Unknown key category");
    }
    clipState.category = changes.category;
  }
  if (Object.prototype.hasOwnProperty.call(changes, "displayName")) {
    const displayName = String(changes.displayName || "").trim().slice(0, 80);
    if (!displayName) throw new Error("Clip name cannot be empty");
    clipState.displayName = displayName;
  }
  if (Object.prototype.hasOwnProperty.call(changes, "note")) {
    clipState.note = String(changes.note || "").slice(0, 500);
  }

  saveState(state);
}

function moveClipToTrash(relativePath) {
  const safePath = safeRelative(relativePath);
  const state = loadState();
  const sourcePath = resolveWithin(CLIPS_DIR, safePath);
  if (!fs.existsSync(sourcePath)) throw new Error("Clip not found");
  if (!state.clips[safePath]) state.clips[safePath] = {};

  const flattened = safePath.replace(/\//g, "--");
  const trashPath = uniquePath(TRASH_DIR, `${Date.now()}--${flattened}`);
  fs.renameSync(sourcePath, trashPath);
  state.clips[safePath].deleted = true;
  state.clips[safePath].trashName = path.basename(trashPath);
  saveState(state);
}

function restoreClip(relativePath) {
  const safePath = safeRelative(relativePath);
  const state = loadState();
  const clipState = state.clips[safePath];
  if (!clipState?.deleted || !clipState.trashName) throw new Error("Trashed clip not found");
  const trashPath = resolveWithin(TRASH_DIR, clipState.trashName);
  const destination = resolveWithin(CLIPS_DIR, safePath);
  if (!fs.existsSync(trashPath)) throw new Error("Trashed audio file is missing");
  if (fs.existsSync(destination)) throw new Error("A clip already exists at the restore location");
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.renameSync(trashPath, destination);
  clipState.deleted = false;
  delete clipState.trashName;
  saveState(state);
}

function permanentlyDeleteClip(relativePath) {
  const safePath = safeRelative(relativePath);
  const state = loadState();
  const clipState = state.clips[safePath];
  if (!clipState?.deleted || !clipState.trashName) throw new Error("Trashed clip not found");
  const trashPath = resolveWithin(TRASH_DIR, clipState.trashName);
  if (fs.existsSync(trashPath)) fs.unlinkSync(trashPath);
  delete state.clips[safePath];
  saveState(state);
}

function exportPicks() {
  const catalog = listCatalog()
    .filter((clip) => !clip.deleted && clip.rating > 0)
    .sort((a, b) => b.rating - a.rating || a.sourceTime - b.sourceTime || a.displayName.localeCompare(b.displayName));
  if (!catalog.length) throw new Error("Rate at least one clip before exporting");

  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z").replace("T", "-");
  const exportName = `Tappy-Picks-${stamp}`;
  const exportDirectory = path.join(EXPORTS_DIR, exportName);
  fs.mkdirSync(exportDirectory, { recursive: true });

  const usedNames = new Set();
  const manifest = [];
  catalog.forEach((clip, index) => {
    const categoryDirectory = path.join(exportDirectory, clip.category);
    fs.mkdirSync(categoryDirectory, { recursive: true });
    const baseName = sanitizeSlug(clip.displayName, `clip-${index + 1}`);
    let outputName = `${String(index + 1).padStart(2, "0")}-${baseName}.wav`;
    let suffix = 2;
    while (usedNames.has(`${clip.category}/${outputName}`)) {
      outputName = `${String(index + 1).padStart(2, "0")}-${baseName}-${suffix}.wav`;
      suffix += 1;
    }
    usedNames.add(`${clip.category}/${outputName}`);
    fs.copyFileSync(resolveWithin(CLIPS_DIR, clip.id), path.join(categoryDirectory, outputName));
    manifest.push({
      source: clip.id,
      file: `${clip.category}/${outputName}`,
      name: clip.displayName,
      rating: clip.rating,
      category: clip.category,
      durationMs: clip.durationMs,
      sourceTime: clip.sourceTime,
    });
  });

  fs.writeFileSync(
    path.join(exportDirectory, "manifest.json"),
    `${JSON.stringify({ createdAt: new Date().toISOString(), clips: manifest }, null, 2)}\n`,
    "utf8",
  );

  const zipPath = path.join(EXPORTS_DIR, `${exportName}.zip`);
  run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", exportDirectory, zipPath]);
  return {
    count: catalog.length,
    path: zipPath,
    downloadUrl: `/exports/${encodeURIComponent(path.basename(zipPath))}`,
  };
}

function contentType(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  return {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".wav": "audio/wav",
    ".zip": "application/zip",
  }[extension] || "application/octet-stream";
}

function serveFile(request, response, filePath, downloadName = null) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    sendError(response, 404, "File not found");
    return;
  }

  const size = fs.statSync(filePath).size;
  const range = request.headers.range;
  const headers = {
    "Content-Type": contentType(filePath),
    "Accept-Ranges": "bytes",
    "Cache-Control": filePath.endsWith(".wav") ? "public, max-age=3600" : "no-cache",
  };
  if (downloadName) headers["Content-Disposition"] = `attachment; filename="${downloadName.replace(/"/g, "")}"`;

  if (range) {
    const match = range.match(/bytes=(\d*)-(\d*)/);
    if (match) {
      const start = match[1] ? Number(match[1]) : 0;
      const end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
      if (Number.isFinite(start) && Number.isFinite(end) && start <= end && start < size) {
        response.writeHead(206, {
          ...headers,
          "Content-Range": `bytes ${start}-${end}/${size}`,
          "Content-Length": end - start + 1,
        });
        fs.createReadStream(filePath, { start, end }).pipe(response);
        return;
      }
    }
  }

  response.writeHead(200, { ...headers, "Content-Length": size });
  fs.createReadStream(filePath).pipe(response);
}

async function handleApi(request, response, url) {
  try {
    if (request.method === "GET" && url.pathname === "/api/clips") {
      sendJson(response, 200, { clips: listCatalog() });
      return true;
    }

    if (request.method === "PATCH" && url.pathname === "/api/clips") {
      const body = JSON.parse((await readRequestBody(request)).toString("utf8") || "{}");
      patchClip(url.searchParams.get("path"), body);
      sendJson(response, 200, { ok: true });
      return true;
    }

    if (request.method === "DELETE" && url.pathname === "/api/clips") {
      moveClipToTrash(url.searchParams.get("path"));
      sendJson(response, 200, { ok: true });
      return true;
    }

    if (request.method === "POST" && url.pathname === "/api/restore") {
      restoreClip(url.searchParams.get("path"));
      sendJson(response, 200, { ok: true });
      return true;
    }

    if (request.method === "DELETE" && url.pathname === "/api/trash") {
      permanentlyDeleteClip(url.searchParams.get("path"));
      sendJson(response, 200, { ok: true });
      return true;
    }

    if (request.method === "POST" && url.pathname === "/api/import") {
      const originalName = url.searchParams.get("name") || "imported-sound.wav";
      const body = await readRequestBody(request);
      if (!body.length) throw new Error("The uploaded audio file was empty");
      const result = importAudio(originalName, body);
      listCatalog();
      sendJson(response, 201, result);
      return true;
    }

    if (request.method === "POST" && url.pathname === "/api/export") {
      sendJson(response, 201, exportPicks());
      return true;
    }
  } catch (error) {
    const message = error instanceof SyntaxError ? "Invalid request data" : error.message;
    sendError(response, message.includes("not found") ? 404 : 400, message);
    return true;
  }
  return false;
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || `${HOST}:${PORT}`}`);

  if (url.pathname.startsWith("/api/")) {
    const handled = await handleApi(request, response, url);
    if (!handled) sendError(response, 404, "Unknown API route");
    return;
  }

  try {
    if (url.pathname.startsWith("/audio/")) {
      const relativePath = safeRelative(decodeURIComponent(url.pathname.slice("/audio/".length)));
      serveFile(request, response, resolveWithin(CLIPS_DIR, relativePath));
      return;
    }
    if (url.pathname.startsWith("/trash-audio/")) {
      const fileName = safeRelative(decodeURIComponent(url.pathname.slice("/trash-audio/".length)));
      serveFile(request, response, resolveWithin(TRASH_DIR, fileName));
      return;
    }
    if (url.pathname.startsWith("/exports/")) {
      const fileName = safeRelative(decodeURIComponent(url.pathname.slice("/exports/".length)));
      serveFile(request, response, resolveWithin(EXPORTS_DIR, fileName), fileName);
      return;
    }
    if (url.pathname === "/vendor/lucide.min.js") {
      serveFile(request, response, LUCIDE_PATH);
      return;
    }

    const requestedPath = url.pathname === "/" ? "index.html" : safeRelative(decodeURIComponent(url.pathname.slice(1)));
    const staticPath = resolveWithin(PUBLIC_DIR, requestedPath);
    if (fs.existsSync(staticPath) && fs.statSync(staticPath).isFile()) {
      serveFile(request, response, staticPath);
      return;
    }
    serveFile(request, response, path.join(PUBLIC_DIR, "index.html"));
  } catch (error) {
    sendError(response, 400, error.message);
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Tappy Clip Lab is running at http://${HOST}:${PORT}`);
  console.log(`Loaded ${listCatalog().filter((clip) => !clip.deleted).length} active clips.`);
});
