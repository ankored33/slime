window.SLIME = window.SLIME || {};
const DEBUG_RESUME_SCREEN_KEY = "slime_debug_resume_screen_v1";

(() => {
  const { SLIME_PRESETS } = window.SLIME.constants;
  const app = window.SLIME.app;
  const assets = window.SLIME.assets;
  const gameplay = window.SLIME.gameplay;
  const screens = window.SLIME.screens;
  const layout = window.SLIME.layout;
  const brushEditor = window.SLIME.brushEditor;

  assets.preloadAllAssets();
  layout.initEditorPanel();
  if (brushEditor && typeof brushEditor.initPanel === "function") {
    brushEditor.initPanel();
  }

  const { canvas, state } = app;

  canvas.addEventListener("pointerdown", (event) => {
    if (event.pointerType === "mouse" && event.button !== 0) {
      return;
    }

    assets.unlockAudio();
    app.setPointerFromEvent(event);
    if (layout.handlePointerDown(state.pointer.x, state.pointer.y)) {
      state.heldBrushIndex = null;
      return;
    }

    const spot = app.findHotspotAt(state.pointer.x, state.pointer.y);
    if (spot) {
      spot.onClick();
      return;
    }

    if (state.currentScreen !== "game" || state.finished) {
      return;
    }

    if (state.heldBrushIndex !== null) {
      state.heldBrushIndex = null;
      return;
    }

    state.heldBrushIndex = gameplay.pickBrushIndexAt(state.pointer.x, state.pointer.y);
  });

  canvas.addEventListener("pointermove", (event) => {
    app.setPointerFromEvent(event);
    layout.handlePointerMove(state.pointer.x, state.pointer.y);
  });

  canvas.addEventListener("pointerup", () => {
    layout.handlePointerUp();
  });

  canvas.addEventListener("pointercancel", () => {
    layout.handlePointerUp();
  });

  window.addEventListener("pointerup", () => {
    layout.handlePointerUp();
  });

  canvas.addEventListener("contextmenu", (event) => {
    event.preventDefault();
  });

  window.addEventListener("keydown", (event) => {
    if (event.key === "F2") {
      event.preventDefault();
      const nextVisible = !(layout.isVisible && layout.isVisible());
      layout.togglePanel(nextVisible);
      if (brushEditor && typeof brushEditor.togglePanel === "function") {
        brushEditor.togglePanel(nextVisible);
      }
      return;
    }

    if (state.currentScreen === "game" && event.key.toLowerCase() === "r" && !event.repeat && state.heldBrushIndex !== null) {
      const held = state.brushes[state.heldBrushIndex];
      if (held) {
        held.isSpinning = !held.isSpinning;
      }
    }
  });

  const defaultSlime = SLIME_PRESETS[0];
  if (defaultSlime) {
    app.startGame(defaultSlime.id);
  } else {
    app.showScreen("game");
  }
  requestAnimationFrame(screens.drawFrame);
})();

function restoreScreenAfterResolutionSwitch(app, layout) {
  let payload = null;
  try {
    const raw = localStorage.getItem(DEBUG_RESUME_SCREEN_KEY);
    if (!raw) {
      return false;
    }
    payload = JSON.parse(raw);
    localStorage.removeItem(DEBUG_RESUME_SCREEN_KEY);
  } catch (_error) {
    try {
      localStorage.removeItem(DEBUG_RESUME_SCREEN_KEY);
    } catch (_ignore) {
      // ignore
    }
    return false;
  }

  if (!payload || typeof payload !== "object") {
    return false;
  }

  const screen = typeof payload.screen === "string" ? payload.screen : "";
  const slimeId = typeof payload.slimeId === "string" ? payload.slimeId : "";
  const editorVisible = !!payload.editorVisible;
  let restored = false;

  if (screen === "game" && slimeId) {
    app.startGame(slimeId);
    restored = true;
  } else if (screen === "title" || screen === "options" || screen === "select" || screen === "result") {
    app.showScreen(screen);
    restored = true;
  }

  if (restored && editorVisible) {
    layout.togglePanel(true);
  }

  return restored;
}
