window.SLIME = window.SLIME || {};

(() => {
  const { SAVE_KEY } = window.SLIME.constants;

  function buildInitialProgress() {
    return {
      daysElapsed: 0,
      finishBySlime: {}
    };
  }

  function normalizeProgress(value) {
    if (!value || typeof value !== "object") {
      return buildInitialProgress();
    }
    return {
      daysElapsed: Number.isFinite(value.daysElapsed) ? Math.max(0, Math.floor(value.daysElapsed)) : 0,
      finishBySlime: value.finishBySlime && typeof value.finishBySlime === "object" ? value.finishBySlime : {}
    };
  }

  function loadProgress() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (!raw) {
        const initial = buildInitialProgress();
        localStorage.setItem(SAVE_KEY, JSON.stringify(initial));
        return initial;
      }
      const parsed = JSON.parse(raw);
      const normalized = normalizeProgress(parsed);
      localStorage.setItem(SAVE_KEY, JSON.stringify(normalized));
      return normalized;
    } catch (_error) {
      return buildInitialProgress();
    }
  }

  function saveProgress(progress) {
    try {
      const normalized = normalizeProgress(progress);
      localStorage.setItem(SAVE_KEY, JSON.stringify(normalized));
    } catch (_error) {
      // Ignore save failure in restricted environments.
    }
  }

  function clearProgress() {
    try {
      localStorage.removeItem(SAVE_KEY);
    } catch (_error) {
      // Ignore clear failure in restricted environments.
    }
  }

  window.SLIME.storage = {
    buildInitialProgress,
    loadProgress,
    saveProgress,
    clearProgress
  };
})();
