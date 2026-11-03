"use strict";

const state = {
  clips: [],
  filter: "all",
  source: "all",
  sort: "source",
  search: "",
  currentAudio: null,
  currentId: null,
  animationFrame: null,
  waveformCache: new Map(),
  audioContext: null,
  uploading: false,
};

const elements = {
  addButton: document.getElementById("addButton"),
  exportButton: document.getElementById("exportButton"),
  fileInput: document.getElementById("fileInput"),
  clipGrid: document.getElementById("clipGrid"),
  emptyState: document.getElementById("emptyState"),
  summary: document.getElementById("summary"),
  searchInput: document.getElementById("searchInput"),
  sourceFilter: document.getElementById("sourceFilter"),
  sortSelect: document.getElementById("sortSelect"),
  viewFilter: document.getElementById("viewFilter"),
  dropOverlay: document.getElementById("dropOverlay"),
  toastRegion: document.getElementById("toastRegion"),
  allCount: document.getElementById("allCount"),
  pickCount: document.getElementById("pickCount"),
  unratedCount: document.getElementById("unratedCount"),
  trashCount: document.getElementById("trashCount"),
};

function refreshIcons() {
  if (window.lucide) {
    window.lucide.createIcons({ attrs: { "stroke-width": 2 } });
  }
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function formatDuration(milliseconds) {
  if (!Number.isFinite(milliseconds)) return "0 ms";
  if (milliseconds < 1000) return `${milliseconds} ms`;
  return `${(milliseconds / 1000).toFixed(2)} s`;
}

function formatSourceTime(seconds) {
  if (!Number.isFinite(seconds)) return "";
  const minutes = Math.floor(seconds / 60);
  const remainder = (seconds % 60).toFixed(2).padStart(5, "0");
  return `${minutes}:${remainder}`;
}

async function api(url, options = {}) {
  const response = await fetch(url, options);
  let payload = {};
  try {
    payload = await response.json();
  } catch (_error) {
    payload = {};
  }
  if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
  return payload;
}

function toast(message, options = {}) {
  const item = document.createElement("div");
  item.className = `toast${options.error ? " error" : ""}`;
  const text = document.createElement("span");
  text.textContent = message;
  item.appendChild(text);

  if (options.actionLabel && options.onAction) {
    const action = document.createElement("button");
    action.type = "button";
    action.textContent = options.actionLabel;
    action.addEventListener("click", async () => {
      item.remove();
      await options.onAction();
    });
    item.appendChild(action);
  }

  elements.toastRegion.appendChild(item);
  window.setTimeout(() => item.remove(), options.duration || 4200);
}

async function loadClips() {
  const payload = await api("/api/clips");
  const audioVersion = Date.now();
  state.clips = payload.clips.map((clip) => ({
    ...clip,
    audioUrl: `${clip.audioUrl}${clip.audioUrl.includes("?") ? "&" : "?"}v=${audioVersion}`,
  }));
  render();
}

function updateCounts() {
  const active = state.clips.filter((clip) => !clip.deleted);
  const picks = active.filter((clip) => clip.rating > 0);
  const trash = state.clips.filter((clip) => clip.deleted);
  elements.allCount.textContent = String(active.length);
  elements.pickCount.textContent = String(picks.length);
  elements.unratedCount.textContent = String(active.length - picks.length);
  elements.trashCount.textContent = String(trash.length);
  elements.summary.textContent = `${active.length} candidates · ${picks.length} picks`;
}

function updateSources() {
  const current = state.source;
  const sources = Array.from(new Map(
    state.clips.filter((clip) => !clip.deleted).map((clip) => [clip.source, clip.sourceLabel]),
  ).entries()).sort((a, b) => a[1].localeCompare(b[1]));
  elements.sourceFilter.innerHTML = `<option value="all">All sources</option>${sources
    .map(([value, label]) => `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`)
    .join("")}`;
  elements.sourceFilter.value = sources.some(([value]) => value === current) ? current : "all";
  state.source = elements.sourceFilter.value;
}

function visibleClips() {
  const search = state.search.toLowerCase();
  const filtered = state.clips.filter((clip) => {
    if (state.filter === "trash" ? !clip.deleted : clip.deleted) return false;
    if (state.filter === "picks" && clip.rating === 0) return false;
    if (state.filter === "unrated" && clip.rating > 0) return false;
    if (state.source !== "all" && clip.source !== state.source) return false;
    if (search && !`${clip.displayName} ${clip.sourceLabel} ${clip.category}`.toLowerCase().includes(search)) return false;
    return true;
  });

  return filtered.sort((a, b) => {
    if (state.sort === "rating") {
      return b.rating - a.rating || (b.score || 0) - (a.score || 0) || a.displayName.localeCompare(b.displayName);
    }
    if (state.sort === "name") return a.displayName.localeCompare(b.displayName);
    return a.source.localeCompare(b.source) || (a.sourceTime ?? Infinity) - (b.sourceTime ?? Infinity) || a.fileName.localeCompare(b.fileName, undefined, { numeric: true });
  });
}

function ratingButtons(clip) {
  return [1, 2, 3].map((rating) => `
    <button
      class="icon-button rating-button${clip.rating >= rating ? " active" : ""}"
      type="button"
      data-action="rate"
      data-rating="${rating}"
      title="${rating === 1 ? "Good" : rating === 2 ? "Great" : "Best"}"
      aria-label="Rate ${rating} out of 3"
    ><i data-lucide="star"></i></button>
  `).join("");
}

function activeFooter(clip) {
  return `
    <select class="category-select" data-action="category" aria-label="Key assignment">
      ${["default", "space", "return", "delete", "modifier"].map((category) => `
        <option value="${category}"${clip.category === category ? " selected" : ""}>${category}</option>
      `).join("")}
    </select>
    <div class="rating-control" aria-label="Clip rating">
      ${ratingButtons(clip)}
      <button class="icon-button delete-button" type="button" data-action="trash" title="Move to Trash" aria-label="Move to Trash">
        <i data-lucide="trash-2"></i>
      </button>
    </div>
  `;
}

function trashFooter() {
  return `
    <span></span>
    <div class="trash-actions">
      <button class="icon-button restore-button" type="button" data-action="restore" title="Restore" aria-label="Restore clip">
        <i data-lucide="rotate-ccw"></i>
      </button>
      <button class="icon-button permanent-delete" type="button" data-action="delete" title="Delete forever" aria-label="Delete clip forever">
        <i data-lucide="trash-2"></i>
      </button>
    </div>
  `;
}

function cardMarkup(clip) {
  const timingParts = [formatDuration(clip.durationMs)];
  if (clip.sourceTime !== null) timingParts.push(formatSourceTime(clip.sourceTime));
  const playing = state.currentId === clip.id && state.currentAudio && !state.currentAudio.paused;
  return `
    <article class="clip-card${clip.rating > 0 ? " is-picked" : ""}${clip.deleted ? " is-trash" : ""}${playing ? " is-playing" : ""}" data-id="${escapeHtml(clip.id)}">
      <div class="card-meta">
        <span class="source-label">${escapeHtml(clip.sourceLabel)}</span>
        <span class="timing">${escapeHtml(timingParts.join(" · "))}</span>
      </div>
      <input
        class="clip-name"
        data-action="rename"
        value="${escapeHtml(clip.displayName)}"
        aria-label="Clip name"
        ${clip.deleted ? "disabled" : ""}
      >
      <div class="wave-row">
        <button class="icon-button play-button" type="button" data-action="play" title="${playing ? "Pause" : "Play"}" aria-label="${playing ? "Pause" : "Play"}">
          <i data-lucide="${playing ? "pause" : "play"}"></i>
        </button>
        <div class="waveform-wrap">
          <canvas class="waveform" data-action="waveform" tabindex="0" aria-label="Play ${escapeHtml(clip.displayName)}"></canvas>
        </div>
      </div>
      <div class="card-footer">
        ${clip.deleted ? trashFooter() : activeFooter(clip)}
      </div>
    </article>
  `;
}

function render() {
  updateCounts();
  updateSources();
  const clips = visibleClips();
  elements.clipGrid.innerHTML = clips.map(cardMarkup).join("");
  elements.emptyState.hidden = clips.length > 0;
  refreshIcons();
  elements.clipGrid.querySelectorAll(".clip-card").forEach((card) => {
    const clip = state.clips.find((entry) => entry.id === card.dataset.id);
    const canvas = card.querySelector(".waveform");
    if (clip && canvas) prepareWaveform(clip, canvas);
  });
}

function drawWaveform(canvas, peaks, progress = 0) {
  const width = Math.max(1, Math.round(canvas.clientWidth));
  const height = 64;
  const ratio = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * ratio);
  canvas.height = Math.round(height * ratio);
  const context = canvas.getContext("2d");
  context.scale(ratio, ratio);
  context.clearRect(0, 0, width, height);

  const center = height / 2;
  const barWidth = Math.max(1, width / peaks.length - 1);
  peaks.forEach((peak, index) => {
    const x = (index / peaks.length) * width;
    const amplitude = Math.max(2, peak * (height - 12));
    context.fillStyle = x / width <= progress ? "#8b6cff" : "#596571";
    context.fillRect(x, center - amplitude / 2, barWidth, amplitude);
  });
}

async function waveformPeaks(clip) {
  if (state.waveformCache.has(clip.id)) return state.waveformCache.get(clip.id);
  const promise = (async () => {
    const response = await fetch(clip.audioUrl);
    const arrayBuffer = await response.arrayBuffer();
    state.audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
    const audioBuffer = await state.audioContext.decodeAudioData(arrayBuffer.slice(0));
    const channel = audioBuffer.getChannelData(0);
    const count = 96;
    const blockSize = Math.max(1, Math.floor(channel.length / count));
    const peaks = [];
    let maximum = 0;
    for (let index = 0; index < count; index += 1) {
      let peak = 0;
      const start = index * blockSize;
      const end = Math.min(channel.length, start + blockSize);
      for (let sample = start; sample < end; sample += 1) peak = Math.max(peak, Math.abs(channel[sample]));
      peaks.push(peak);
      maximum = Math.max(maximum, peak);
    }
    return maximum > 0 ? peaks.map((peak) => peak / maximum) : peaks;
  })();
  state.waveformCache.set(clip.id, promise);
  return promise;
}

async function prepareWaveform(clip, canvas) {
  try {
    const peaks = await waveformPeaks(clip);
    if (!canvas.isConnected) return;
    const progress = state.currentId === clip.id && state.currentAudio?.duration
      ? state.currentAudio.currentTime / state.currentAudio.duration
      : 0;
    drawWaveform(canvas, peaks, progress);
  } catch (_error) {
    drawWaveform(canvas, Array(96).fill(0.08), 0);
  }
}

function stopCurrentAudio() {
  if (state.currentAudio) {
    state.currentAudio.pause();
    state.currentAudio.currentTime = 0;
  }
  if (state.animationFrame) cancelAnimationFrame(state.animationFrame);
  state.currentAudio = null;
  state.currentId = null;
  state.animationFrame = null;
}

function updatePlaybackFrame() {
  if (!state.currentAudio || !state.currentId) return;
  const card = Array.from(elements.clipGrid.querySelectorAll(".clip-card")).find((item) => item.dataset.id === state.currentId);
  const canvas = card?.querySelector(".waveform");
  const cached = state.waveformCache.get(state.currentId);
  if (canvas && cached) {
    Promise.resolve(cached).then((peaks) => {
      const progress = state.currentAudio?.duration ? state.currentAudio.currentTime / state.currentAudio.duration : 0;
      if (canvas.isConnected) drawWaveform(canvas, peaks, progress);
    });
  }
  if (!state.currentAudio.paused) state.animationFrame = requestAnimationFrame(updatePlaybackFrame);
}

async function togglePlayback(clip) {
  if (state.currentId === clip.id && state.currentAudio) {
    if (state.currentAudio.paused) {
      await state.currentAudio.play();
      updatePlaybackFrame();
    } else {
      state.currentAudio.pause();
    }
    render();
    return;
  }

  stopCurrentAudio();
  const audio = new Audio(clip.audioUrl);
  audio.preload = "auto";
  state.currentAudio = audio;
  state.currentId = clip.id;
  audio.addEventListener("ended", () => {
    stopCurrentAudio();
    render();
  }, { once: true });
  await audio.play();
  render();
  updatePlaybackFrame();
}

async function patchClip(id, changes) {
  const clip = state.clips.find((entry) => entry.id === id);
  if (!clip) return;
  const previous = { ...clip };
  Object.assign(clip, changes);
  render();
  try {
    await api(`/api/clips?path=${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(changes),
    });
  } catch (error) {
    Object.assign(clip, previous);
    render();
    toast(error.message, { error: true });
  }
}

async function trashClip(id) {
  stopCurrentAudio();
  await api(`/api/clips?path=${encodeURIComponent(id)}`, { method: "DELETE" });
  await loadClips();
  toast("Moved to Trash", {
    actionLabel: "Undo",
    onAction: async () => restoreClip(id),
  });
}

async function restoreClip(id) {
  await api(`/api/restore?path=${encodeURIComponent(id)}`, { method: "POST" });
  await loadClips();
  toast("Clip restored");
}

async function deleteForever(id) {
  if (!window.confirm("Delete this audio clip permanently?")) return;
  stopCurrentAudio();
  await api(`/api/trash?path=${encodeURIComponent(id)}`, { method: "DELETE" });
  state.waveformCache.delete(id);
  await loadClips();
  toast("Clip deleted permanently");
}

elements.clipGrid.addEventListener("click", async (event) => {
  const target = event.target.closest("[data-action]");
  const card = event.target.closest(".clip-card");
  if (!target || !card) return;
  const clip = state.clips.find((entry) => entry.id === card.dataset.id);
  if (!clip) return;

  try {
    if (target.dataset.action === "play" || target.dataset.action === "waveform") {
      await togglePlayback(clip);
    } else if (target.dataset.action === "rate") {
      const requested = Number(target.dataset.rating);
      const rating = clip.rating === requested ? 0 : requested;
      await patchClip(clip.id, { rating });
    } else if (target.dataset.action === "trash") {
      await trashClip(clip.id);
    } else if (target.dataset.action === "restore") {
      await restoreClip(clip.id);
    } else if (target.dataset.action === "delete") {
      await deleteForever(clip.id);
    }
  } catch (error) {
    toast(error.message, { error: true });
  }
});

elements.clipGrid.addEventListener("keydown", async (event) => {
  if ((event.key === "Enter" || event.key === " ") && event.target.dataset.action === "waveform") {
    event.preventDefault();
    const card = event.target.closest(".clip-card");
    const clip = state.clips.find((entry) => entry.id === card?.dataset.id);
    if (clip) await togglePlayback(clip);
  }
  if (event.key === "Enter" && event.target.dataset.action === "rename") {
    event.preventDefault();
    event.target.blur();
  }
});

elements.clipGrid.addEventListener("change", async (event) => {
  const card = event.target.closest(".clip-card");
  if (!card) return;
  if (event.target.dataset.action === "category") {
    await patchClip(card.dataset.id, { category: event.target.value });
  }
});

elements.clipGrid.addEventListener("focusout", async (event) => {
  if (event.target.dataset.action !== "rename") return;
  const card = event.target.closest(".clip-card");
  const clip = state.clips.find((entry) => entry.id === card?.dataset.id);
  const displayName = event.target.value.trim();
  if (!clip) return;
  if (!displayName) {
    event.target.value = clip.displayName;
    return;
  }
  if (displayName !== clip.displayName) await patchClip(clip.id, { displayName });
});

elements.viewFilter.addEventListener("click", (event) => {
  const button = event.target.closest("[data-filter]");
  if (!button) return;
  state.filter = button.dataset.filter;
  elements.viewFilter.querySelectorAll(".segment").forEach((item) => item.classList.toggle("active", item === button));
  render();
});

elements.searchInput.addEventListener("input", () => {
  state.search = elements.searchInput.value.trim();
  render();
});

elements.sourceFilter.addEventListener("change", () => {
  state.source = elements.sourceFilter.value;
  render();
});

elements.sortSelect.addEventListener("change", () => {
  state.sort = elements.sortSelect.value;
  render();
});

async function uploadFiles(fileList) {
  const files = Array.from(fileList || []).filter((file) => file.size > 0);
  if (!files.length || state.uploading) return;
  state.uploading = true;
  elements.addButton.disabled = true;
  elements.exportButton.disabled = true;

  let imported = 0;
  try {
    for (const file of files) {
      elements.summary.textContent = `Importing ${file.name}`;
      const payload = await api(`/api/import?name=${encodeURIComponent(file.name)}`, {
        method: "POST",
        headers: { "Content-Type": "application/octet-stream" },
        body: file,
      });
      imported += payload.imported;
    }
    await loadClips();
    toast(`${imported} ${imported === 1 ? "clip" : "clips"} added`);
  } catch (error) {
    toast(error.message, { error: true, duration: 7000 });
    await loadClips();
  } finally {
    state.uploading = false;
    elements.addButton.disabled = false;
    elements.exportButton.disabled = false;
    elements.fileInput.value = "";
  }
}

elements.addButton.addEventListener("click", () => elements.fileInput.click());
elements.fileInput.addEventListener("change", () => uploadFiles(elements.fileInput.files));

let dragDepth = 0;
window.addEventListener("dragenter", (event) => {
  if (!event.dataTransfer?.types?.includes("Files")) return;
  event.preventDefault();
  dragDepth += 1;
  elements.dropOverlay.hidden = false;
});
window.addEventListener("dragover", (event) => {
  if (event.dataTransfer?.types?.includes("Files")) event.preventDefault();
});
window.addEventListener("dragleave", (event) => {
  if (!event.dataTransfer?.types?.includes("Files")) return;
  dragDepth = Math.max(0, dragDepth - 1);
  if (dragDepth === 0) elements.dropOverlay.hidden = true;
});
window.addEventListener("drop", (event) => {
  event.preventDefault();
  dragDepth = 0;
  elements.dropOverlay.hidden = true;
  uploadFiles(event.dataTransfer?.files);
});

elements.exportButton.addEventListener("click", async () => {
  elements.exportButton.disabled = true;
  try {
    const payload = await api("/api/export", { method: "POST" });
    const link = document.createElement("a");
    link.href = payload.downloadUrl;
    link.download = "";
    document.body.appendChild(link);
    link.click();
    link.remove();
    toast(`${payload.count} ${payload.count === 1 ? "pick" : "picks"} exported`);
  } catch (error) {
    toast(error.message, { error: true });
  } finally {
    elements.exportButton.disabled = false;
  }
});

window.addEventListener("resize", () => {
  elements.clipGrid.querySelectorAll(".clip-card").forEach((card) => {
    const clip = state.clips.find((entry) => entry.id === card.dataset.id);
    const canvas = card.querySelector(".waveform");
    if (clip && canvas) prepareWaveform(clip, canvas);
  });
});

refreshIcons();
loadClips().catch((error) => {
  elements.summary.textContent = "Could not load candidates";
  toast(error.message, { error: true, duration: 10000 });
});
