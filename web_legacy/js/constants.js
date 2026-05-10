window.SLIME = window.SLIME || {};

(() => {
  const CONFIG = window.SLIME_CONFIG || {};
  const GAME_CONFIG = CONFIG.game || {};
  const RAW_SLIME_PRESETS = CONFIG.slimePresets || [];
  const ART_CONFIG = CONFIG.art || {};
  const RAW_FONT_ASSETS = Array.isArray(ART_CONFIG.fonts) ? ART_CONFIG.fonts : [];
  const RESOLUTION_KEY = "slime_polish_resolution_v1";

  const ASSET_PATHS = {
    defaultSlime: "./assets/default/slime.svg",
    defaultThumb: "./assets/default/thumb.svg",
    brush: "./assets/brush.svg"
  };

  function normalizeSlimePreset(preset) {
    const assets = preset && preset.assets ? preset.assets : {};
    return {
      ...preset,
      assets: {
        slimeImage: assets.slimeImage || ASSET_PATHS.defaultSlime,
        thumbImage: assets.thumbImage || assets.slimeImage || ASSET_PATHS.defaultThumb,
        voiceStart: assets.voiceStart || "",
        voiceFinish: assets.voiceFinish || "",
        sfxPolishLoop: assets.sfxPolishLoop || ""
      }
    };
  }

  function normalizeFontAsset(entry, index) {
    const family = entry && typeof entry.family === "string" ? entry.family.trim() : "";
    let path = entry && typeof entry.path === "string" ? entry.path.trim().replace(/\\/g, "/") : "";
    const weight = entry && typeof entry.weight === "string" ? entry.weight.trim() : "normal";
    const style = entry && typeof entry.style === "string" ? entry.style.trim() : "normal";
    const id = entry && typeof entry.id === "string" && entry.id.trim()
      ? entry.id.trim()
      : `font_${index + 1}`;

    if ((path.startsWith('"') && path.endsWith('"')) || (path.startsWith("'") && path.endsWith("'"))) {
      path = path.slice(1, -1).trim();
    }
    if (path.startsWith("assets/fonts/")) {
      path = `./${path}`;
    }

    if (!family || !path) {
      return null;
    }
    if (!path.startsWith("./assets/fonts/")) {
      return null;
    }

    return {
      id,
      family,
      path,
      weight: weight || "normal",
      style: style || "normal"
    };
  }

  function resolveResolution() {
    const resolutions = GAME_CONFIG.resolutions;
    if (!resolutions || typeof resolutions !== "object") {
      return {
        id: "",
        label: "",
        width: GAME_CONFIG.width ?? 1600,
        height: GAME_CONFIG.height ?? 900,
        options: []
      };
    }

    const optionIds = Object.keys(resolutions);
    const defaultId = typeof GAME_CONFIG.defaultResolution === "string"
      ? GAME_CONFIG.defaultResolution
      : (optionIds[0] || "");
    let storedId = "";
    try {
      storedId = localStorage.getItem(RESOLUTION_KEY) || "";
    } catch (_error) {
      storedId = "";
    }

    const selectedId = resolutions[storedId] ? storedId : defaultId;
    const selected = resolutions[selectedId] || {};
    const width = Number.isFinite(selected.width) ? selected.width : (GAME_CONFIG.width ?? 1600);
    const height = Number.isFinite(selected.height) ? selected.height : (GAME_CONFIG.height ?? 900);
    const label = selected.label || `${width}x${height}`;
    const options = optionIds.map((id) => {
      const entry = resolutions[id] || {};
      const optionWidth = Number.isFinite(entry.width) ? entry.width : width;
      const optionHeight = Number.isFinite(entry.height) ? entry.height : height;
      return {
        id,
        width: optionWidth,
        height: optionHeight,
        label: entry.label || `${optionWidth}x${optionHeight}`
      };
    });

    return { id: selectedId, label, width, height, options };
  }

  const resolution = resolveResolution();
  const FONT_ASSETS = RAW_FONT_ASSETS
    .map(normalizeFontAsset)
    .filter(Boolean);
  const TEXT_FONT_OPTIONS = Array.from(
    new Set(["Segoe UI", ...FONT_ASSETS.map((item) => item.family)])
  ).map((family) => ({ value: family, label: family }));

  window.SLIME.constants = {
    GAME_WIDTH: resolution.width,
    GAME_HEIGHT: resolution.height,
    FIXED_SCALE: GAME_CONFIG.fixedScale !== false,
    SAVE_KEY: "slime_polish_progress_v1",
    PROGRESS_DECAY_PER_SEC: 2.4,
    PAIN_GAIN_PER_SEC: 8,
    PAIN_DECAY_PER_SEC: 3.2,
    FINISH_THRESHOLD: 90,
    FINISH_FX_DURATION_SEC: 1.35,
    ASSET_PATHS,
    AUDIO_KEYS: ["voiceStart", "voiceFinish", "sfxPolishLoop"],
    IMAGE_KEYS: ["slimeImage", "thumbImage"],
    SLIME_PRESETS: RAW_SLIME_PRESETS.map(normalizeSlimePreset),
    PAIR_LAYOUT: CONFIG.pairLayout || [],
    BRUSH_CONFIG: CONFIG.brush || {},
    ZOOM_CONFIG: CONFIG.zoom || {},
    ART_BASE_WIDTH: ART_CONFIG.baseWidth ?? (GAME_CONFIG.width ?? 1600),
    ART_BASE_HEIGHT: ART_CONFIG.baseHeight ?? (GAME_CONFIG.height ?? 900),
    SCREEN_BACKGROUNDS: ART_CONFIG.backgrounds || {},
    SCREEN_IMAGES: ART_CONFIG.images || {},
    FONT_ASSETS,
    TEXT_FONT_OPTIONS,
    RESOLUTION_KEY,
    RESOLUTION_ID: resolution.id,
    RESOLUTION_LABEL: resolution.label,
    RESOLUTION_OPTIONS: resolution.options
  };
})();
