window.SLIME = window.SLIME || {};

(() => {
  const {
    ASSET_PATHS,
    SLIME_PRESETS,
    AUDIO_KEYS,
    IMAGE_KEYS,
    FONT_ASSETS,
    SCREEN_BACKGROUNDS,
    SCREEN_IMAGES
  } = window.SLIME.constants;

  const cache = {
    images: new Map(),
    audios: new Map(),
    fonts: new Map()
  };

  const audioState = {
    unlocked: false,
    loopAudio: null,
    loopPath: ""
  };

  function cacheImage(path) {
    if (!path) {
      return null;
    }
    if (cache.images.has(path)) {
      return cache.images.get(path);
    }
    const image = new Image();
    image.src = path;
    cache.images.set(path, image);
    return image;
  }

  function cacheAudio(path) {
    if (!path) {
      return null;
    }
    if (cache.audios.has(path)) {
      return cache.audios.get(path);
    }
    const audio = new Audio(path);
    audio.preload = "auto";
    audio.addEventListener("error", () => {
      audio._loadFailed = true;
    });
    cache.audios.set(path, audio);
    return audio;
  }

  function cacheFont(entry) {
    if (!entry || !entry.id || !entry.family || !entry.path) {
      return null;
    }
    if (cache.fonts.has(entry.id)) {
      return cache.fonts.get(entry.id);
    }
    if (typeof FontFace === "undefined" || !document.fonts || typeof document.fonts.add !== "function") {
      cache.fonts.set(entry.id, null);
      return null;
    }

    const descriptors = {
      style: entry.style || "normal",
      weight: entry.weight || "normal"
    };
    const fontFace = new FontFace(entry.family, `url("${entry.path}")`, descriptors);
    const loadPromise = fontFace.load()
      .then((loadedFace) => {
        document.fonts.add(loadedFace);
        return loadedFace;
      })
      .catch(() => null);

    cache.fonts.set(entry.id, loadPromise);
    return loadPromise;
  }

  function preloadAllAssets() {
    cacheImage(ASSET_PATHS.defaultSlime);
    cacheImage(ASSET_PATHS.defaultThumb);
    cacheImage(ASSET_PATHS.brush);
    Object.values(SCREEN_BACKGROUNDS || {}).forEach((path) => {
      cacheImage(path);
    });
    Object.values(SCREEN_IMAGES || {}).forEach((items) => {
      if (!Array.isArray(items)) {
        return;
      }
      items.forEach((item) => cacheImage(item && item.path ? item.path : ""));
    });

    SLIME_PRESETS.forEach((preset) => {
      IMAGE_KEYS.forEach((key) => cacheImage(preset.assets[key]));
      AUDIO_KEYS.forEach((key) => cacheAudio(preset.assets[key]));
    });
    const brushItems = window.SLIME_CONFIG && window.SLIME_CONFIG.brush && Array.isArray(window.SLIME_CONFIG.brush.items)
      ? window.SLIME_CONFIG.brush.items
      : [];
    brushItems.forEach((item) => {
      if (item && typeof item.image === "string" && item.image) {
        cacheImage(item.image);
      }
    });
    FONT_ASSETS.forEach((entry) => cacheFont(entry));
  }

  function getSlimeImage(preset, kind) {
    const preferred = preset && preset.assets ? preset.assets[kind] : "";
    const fallback = kind === "thumbImage" ? ASSET_PATHS.defaultThumb : ASSET_PATHS.defaultSlime;
    const preferredImage = cacheImage(preferred);
    if (preferredImage && preferredImage.complete && preferredImage.naturalWidth > 0) {
      return preferredImage;
    }
    const fallbackImage = cacheImage(fallback);
    if (fallbackImage && fallbackImage.complete && fallbackImage.naturalWidth > 0) {
      return fallbackImage;
    }
    return null;
  }

  function getBrushImage() {
    const brush = cacheImage(ASSET_PATHS.brush);
    if (brush && brush.complete && brush.naturalWidth > 0) {
      return brush;
    }
    return null;
  }

  function getBrushImageByPath(path) {
    const preferred = cacheImage(path);
    if (preferred && preferred.complete && preferred.naturalWidth > 0) {
      return preferred;
    }
    return getBrushImage();
  }
  
  function getScreenBackgroundImage(screen) {
    const path = (SCREEN_BACKGROUNDS && SCREEN_BACKGROUNDS[screen])
      || (SCREEN_BACKGROUNDS && SCREEN_BACKGROUNDS.default)
      || "";
    const background = cacheImage(path);
    if (background && background.complete && background.naturalWidth > 0) {
      return background;
    }
    return null;
  }

  function getScreenImages(screen) {
    const entries = SCREEN_IMAGES && SCREEN_IMAGES[screen];
    if (!Array.isArray(entries)) {
      return [];
    }
    return entries
      .map((item) => {
        if (!item || !item.path) {
          return null;
        }
        const image = cacheImage(item.path);
        if (!image) {
          return null;
        }
        return { image, layout: item };
      })
      .filter(Boolean);
  }

  function getImageByPath(path) {
    return cacheImage(path);
  }

  function getHeartEffectImage() {
    const heartPath = "./assets/effects/heart.png";
    const heart = cacheImage(heartPath);
    if (heart && heart.complete && heart.naturalWidth > 0) {
      return heart;
    }
    return null;
  }

  function unlockAudio() {
    audioState.unlocked = true;
  }

  function stopPolishLoop() {
    if (audioState.loopAudio) {
      audioState.loopAudio.pause();
      audioState.loopAudio.currentTime = 0;
    }
    audioState.loopAudio = null;
    audioState.loopPath = "";
  }

  function playOneShot(path) {
    if (!audioState.unlocked || !path) {
      return;
    }
    const source = cacheAudio(path);
    if (!source || source._loadFailed) {
      return;
    }
    const oneShot = source.cloneNode();
    oneShot.volume = 0.85;
    oneShot.play().catch(() => {});
  }

  function updatePolishLoopAudio(selectedSlime, isPolishing) {
    if (!audioState.unlocked || !selectedSlime || !selectedSlime.assets) {
      stopPolishLoop();
      return;
    }

    const loopPath = selectedSlime.assets.sfxPolishLoop;
    if (!isPolishing || !loopPath) {
      stopPolishLoop();
      return;
    }

    if (!audioState.loopAudio || audioState.loopPath !== loopPath) {
      stopPolishLoop();
      const loopAudio = cacheAudio(loopPath);
      if (!loopAudio || loopAudio._loadFailed) {
        return;
      }
      audioState.loopAudio = loopAudio;
      audioState.loopPath = loopPath;
      audioState.loopAudio.loop = true;
      audioState.loopAudio.volume = 0.4;
    }

    if (audioState.loopAudio.paused) {
      audioState.loopAudio.play().catch(() => {});
    }
  }

  window.SLIME.assets = {
    preloadAllAssets,
    getSlimeImage,
    getBrushImage,
    getBrushImageByPath,
    getScreenBackgroundImage,
    getScreenImages,
    getImageByPath,
    getHeartEffectImage,
    unlockAudio,
    playOneShot,
    stopPolishLoop,
    updatePolishLoopAudio
  };
})();
