window.SLIME = window.SLIME || {};

(() => {
  const {
    GAME_WIDTH,
    GAME_HEIGHT,
    FIXED_SCALE,
    SLIME_PRESETS,
    PAIR_LAYOUT,
    BRUSH_CONFIG
  } = window.SLIME.constants;
  const { loadProgress, saveProgress } = window.SLIME.storage;
  const assets = window.SLIME.assets;

  const canvas = document.getElementById("game-canvas");
  const ctx = canvas.getContext("2d");
  const worldCanvas = document.createElement("canvas");
  const worldCtx = worldCanvas.getContext("2d");

  function applyGameSize() {
    canvas.width = GAME_WIDTH;
    canvas.height = GAME_HEIGHT;
    worldCanvas.width = GAME_WIDTH;
    worldCanvas.height = GAME_HEIGHT;

    if (FIXED_SCALE) {
      canvas.style.width = `${GAME_WIDTH}px`;
      canvas.style.height = `${GAME_HEIGHT}px`;
    }

    document.documentElement.style.setProperty("--game-width", `${GAME_WIDTH}px`);
    document.documentElement.style.setProperty("--game-height", `${GAME_HEIGHT}px`);
  }

  applyGameSize();

  const state = {
    currentScreen: "title",
    selectedSlime: null,
    finished: false,
    finishFxRemaining: 0,
    resultSnapshot: null,
    isPolishing: false,
    heartParticles: [],
    heldBrushIndex: null,
    pointer: { x: GAME_WIDTH * 0.5, y: GAME_HEIGHT * 0.5 },
    brushSpecs: [],
    brushes: [],
    brushSpawnOrder: [],
    nextBrushInstanceId: 1,
    slimes: [],
    uiHotspots: [],
    lastTick: performance.now()
  };

  const progress = loadProgress();

  function showScreen(screenName) {
    if (screenName !== "game") {
      state.isPolishing = false;
      assets.stopPolishLoop();
    }
    state.currentScreen = screenName;
    state.uiHotspots = [];
    canvas.style.cursor = "default";
  }

  function buildSlimePair() {
    return PAIR_LAYOUT.map((layout) => ({
      side: layout.side,
      x: canvas.width * layout.xRatio,
      y: canvas.height * layout.yRatio,
      radius: layout.radius,
      wobble: 0,
      shine: 0,
      progress: 0,
      painProgress: 0,
      wasTouching: false
    }));
  }

  function buildBrushSpecs() {
    const defaultRadius = BRUSH_CONFIG.radius ?? 34;
    const defaultHitRadius = BRUSH_CONFIG.hitRadius ?? Math.max(1, defaultRadius * 0.65);
    const defaultFollowSpeed = BRUSH_CONFIG.followSpeed ?? 16;
    const defaultSpinSpeed = BRUSH_CONFIG.spinSpeed ?? 9;
    const defaultPolishGainPerSec = BRUSH_CONFIG.polishGainPerSec ?? 20;
    const defaultPainGainPerSec = BRUSH_CONFIG.painGainPerSec ?? 8;
    const brushItems = Array.isArray(BRUSH_CONFIG.items) ? BRUSH_CONFIG.items : [];
    const startPositions = BRUSH_CONFIG.startPositions || [
      { xRatio: 0.82, yRatio: 0.14 },
      { xRatio: 0.92, yRatio: 0.24 },
      { xRatio: 0.82, yRatio: 0.34 },
      { xRatio: 0.92, yRatio: 0.44 },
      { xRatio: 0.82, yRatio: 0.54 }
    ];
    const count = Math.max(5, startPositions.length, brushItems.length);

    return Array.from({ length: count }, (_, index) => {
      const fallbackX = 0.82 + (index % 2) * 0.1;
      const fallbackY = 0.14 + Math.floor(index / 2) * 0.1;
      const pos = startPositions[index] || { xRatio: fallbackX, yRatio: fallbackY };
      const item = brushItems[index] || {};
      const xRatio = Math.max(0.05, Math.min(0.95, Number(pos.xRatio) || fallbackX));
      const yRatio = Math.max(0.05, Math.min(0.95, Number(pos.yRatio) || fallbackY));
      const radius = Number.isFinite(item.radius) ? item.radius : defaultRadius;
      const hitRadius = Number.isFinite(item.hitRadius) ? item.hitRadius : defaultHitRadius;
      const followSpeed = Number.isFinite(item.followSpeed) ? item.followSpeed : defaultFollowSpeed;
      const spinSpeed = Number.isFinite(item.spinSpeed) ? item.spinSpeed : defaultSpinSpeed;
      const polishGainPerSec = Number.isFinite(item.polishGainPerSec) ? item.polishGainPerSec : defaultPolishGainPerSec;
      const painGainPerSec = Number.isFinite(item.painGainPerSec) ? item.painGainPerSec : defaultPainGainPerSec;
      const image = typeof item.image === "string" ? item.image : "";
      return {
        brushTypeIndex: index,
        startX: canvas.width * xRatio,
        startY: canvas.height * yRatio,
        radius,
        hitRadius,
        followSpeed,
        spinSpeed,
        polishGainPerSec,
        painGainPerSec,
        image
      };
    });
  }

  function instantiateBrushFromSpec(spec) {
    if (!spec) {
      return null;
    }
    const px = Number.isFinite(state.pointer.x) ? state.pointer.x : spec.startX;
    const py = Number.isFinite(state.pointer.y) ? state.pointer.y : spec.startY;
    return {
      instanceId: state.nextBrushInstanceId++,
      brushTypeIndex: spec.brushTypeIndex,
      x: px,
      y: py,
      radius: spec.radius,
      hitRadius: spec.hitRadius,
      angle: 0,
      isSpinning: false,
      followSpeed: spec.followSpeed,
      spinSpeed: spec.spinSpeed,
      polishGainPerSec: spec.polishGainPerSec,
      painGainPerSec: spec.painGainPerSec,
      image: spec.image || ""
    };
  }

  function removeBrushAt(index) {
    if (!Number.isInteger(index) || index < 0 || index >= state.brushes.length) {
      return false;
    }
    const [removed] = state.brushes.splice(index, 1);
    if (!removed) {
      return false;
    }
    state.brushSpawnOrder = state.brushSpawnOrder.filter((id) => id !== removed.instanceId);
    if (state.heldBrushIndex === index) {
      state.heldBrushIndex = null;
    } else if (state.heldBrushIndex !== null && state.heldBrushIndex > index) {
      state.heldBrushIndex -= 1;
    }
    return true;
  }

  function enforceActiveBrushLimit(maxActiveCount) {
    while (state.brushes.length >= maxActiveCount && state.brushSpawnOrder.length > 0) {
      const oldestId = state.brushSpawnOrder[0];
      const index = state.brushes.findIndex((brush) => brush && brush.instanceId === oldestId);
      if (index < 0) {
        state.brushSpawnOrder.shift();
        continue;
      }
      removeBrushAt(index);
    }
  }

  function spawnBrushByType(brushTypeIndex) {
    if (!Number.isInteger(brushTypeIndex) || brushTypeIndex < 0 || brushTypeIndex >= state.brushSpecs.length) {
      return false;
    }
    enforceActiveBrushLimit(2);
    const spec = state.brushSpecs[brushTypeIndex];
    const brush = instantiateBrushFromSpec(spec);
    if (!brush) {
      return false;
    }
    state.brushes.push(brush);
    state.brushSpawnOrder.push(brush.instanceId);
    state.heldBrushIndex = state.brushes.length - 1;
    return true;
  }

  function getBrushSpecs() {
    return state.brushSpecs;
  }

  function updateBrushSpec(brushTypeIndex, patch, applyToActive = true) {
    if (!Number.isInteger(brushTypeIndex) || brushTypeIndex < 0 || brushTypeIndex >= state.brushSpecs.length) {
      return false;
    }
    const spec = state.brushSpecs[brushTypeIndex];
    if (!spec || !patch || typeof patch !== "object") {
      return false;
    }

    const next = { ...spec };
    if (Object.prototype.hasOwnProperty.call(patch, "image")) {
      next.image = typeof patch.image === "string" ? patch.image : "";
    }

    const numericKeys = [
      "radius",
      "hitRadius",
      "followSpeed",
      "spinSpeed",
      "polishGainPerSec",
      "painGainPerSec"
    ];
    numericKeys.forEach((key) => {
      if (!Object.prototype.hasOwnProperty.call(patch, key)) {
        return;
      }
      const value = Number(patch[key]);
      if (Number.isFinite(value)) {
        next[key] = value;
      }
    });

    state.brushSpecs[brushTypeIndex] = next;

    if (applyToActive) {
      state.brushes.forEach((brush) => {
        if (!brush || brush.brushTypeIndex !== brushTypeIndex) {
          return;
        }
        brush.radius = next.radius;
        brush.hitRadius = next.hitRadius;
        brush.followSpeed = next.followSpeed;
        brush.spinSpeed = next.spinSpeed;
        brush.polishGainPerSec = next.polishGainPerSec;
        brush.painGainPerSec = next.painGainPerSec;
        brush.image = next.image;
      });
    }

    return true;
  }

  function resetBrushes() {
    state.brushes = [];
    state.brushSpawnOrder = [];
    state.nextBrushInstanceId = 1;
    state.heldBrushIndex = null;
  }

  function startGame(slimeId) {
    state.selectedSlime = SLIME_PRESETS.find((preset) => preset.id === slimeId) || null;
    if (!state.selectedSlime) {
      return;
    }

    state.finished = false;
    state.finishFxRemaining = 0;
    state.resultSnapshot = null;
    state.isPolishing = false;
    state.heartParticles = [];
    state.slimes = buildSlimePair();
    resetBrushes();
    assets.playOneShot(state.selectedSlime.assets.voiceStart);
    showScreen("game");
  }

  function getFinishCountForSlime(slimeId) {
    return progress.finishBySlime[slimeId] || 0;
  }

  function registerSlimeFinish() {
    if (!state.selectedSlime) {
      return;
    }
    const slimeId = state.selectedSlime.id;
    progress.finishBySlime[slimeId] = getFinishCountForSlime(slimeId) + 1;
    saveProgress(progress);
  }

  function advanceDay() {
    progress.daysElapsed += 1;
    saveProgress(progress);
  }

  function resetSlimeCycle() {
    state.slimes.forEach((slime) => {
      slime.progress = 0;
      slime.painProgress = 0;
      slime.wobble = 0;
      slime.shine = 0;
      slime.wasTouching = false;
    });
    state.isPolishing = false;
    state.heartParticles = [];
    assets.stopPolishLoop();
  }

  function finishDayAndGoResult() {
    if (state.currentScreen !== "game") {
      return;
    }

    const slimeName = state.selectedSlime ? state.selectedSlime.name : "Unknown Slime";
    const slimeId = state.selectedSlime ? state.selectedSlime.id : "";

    state.finished = false;
    state.finishFxRemaining = 0;
    state.heldBrushIndex = null;
    state.isPolishing = false;
    state.heartParticles = [];
    assets.stopPolishLoop();

    advanceDay();

    state.resultSnapshot = {
      slimeName,
      day: progress.daysElapsed,
      finishCount: slimeId ? getFinishCountForSlime(slimeId) : 0
    };

    showScreen("result");
  }

  function addHotspot(x, y, w, h, onClick) {
    state.uiHotspots.push({ x, y, w, h, onClick });
  }

  function findHotspotAt(x, y) {
    return state.uiHotspots.find((spot) => (
      x >= spot.x && x <= spot.x + spot.w && y >= spot.y && y <= spot.y + spot.h
    )) || null;
  }

  function setHeldBrushByIndex(index) {
    if (!Number.isInteger(index) || index < 0 || index >= state.brushes.length) {
      return false;
    }
    state.heldBrushIndex = index;
    return true;
  }

  function getHeldBrushName() {
    if (state.heldBrushIndex === null || state.heldBrushIndex < 0) {
      return "なし";
    }
    const heldBrush = state.brushes[state.heldBrushIndex];
    if (!heldBrush || !Number.isInteger(heldBrush.brushTypeIndex)) {
      return "なし";
    }
    return `brush${heldBrush.brushTypeIndex + 1}`;
  }

  function setPointerFromEvent(event) {
    const rect = canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * canvas.width;
    const y = ((event.clientY - rect.top) / rect.height) * canvas.height;
    state.pointer.x = x;
    state.pointer.y = y;
  }

  state.brushSpecs = buildBrushSpecs();

  window.SLIME.app = {
    canvas,
    ctx,
    worldCanvas,
    worldCtx,
    state,
    progress,
    showScreen,
    startGame,
    getFinishCountForSlime,
    registerSlimeFinish,
    advanceDay,
    resetSlimeCycle,
    finishDayAndGoResult,
    addHotspot,
    findHotspotAt,
    setPointerFromEvent,
    resetBrushes,
    setHeldBrushByIndex,
    getHeldBrushName,
    spawnBrushByType,
    getBrushSpecs,
    updateBrushSpec
  };
})();
