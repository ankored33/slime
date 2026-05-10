window.SLIME = window.SLIME || {};

(() => {
  const {
    GAME_WIDTH,
    GAME_HEIGHT,
    ZOOM_CONFIG,
    RESOLUTION_ID
  } = window.SLIME.constants;

  const STORAGE_KEY = `slime_layout_editor_v2:${RESOLUTION_ID || "default"}`;
  const HISTORY_LIMIT = 120;
  const RESIZE_HIT_SIZE = 8;
  const MIN_ELEMENT_W = 12;
  const MIN_ELEMENT_H = 12;
  const FIELD_HISTORY_DEBOUNCE_MS = 500;

  const schema = window.SLIME.layoutSchema;
  const TYPE_OPTIONS = schema && Array.isArray(schema.typeOptions)
    ? schema.typeOptions
    : ["text", "panel", "button", "object", "gauge"];

  const sx = (value) => Math.round(value * (GAME_WIDTH / 1600));
  const sy = (value) => Math.round(value * (GAME_HEIGHT / 900));
  const ss = (value) => Math.round(value * Math.min(GAME_WIDTH / 1600, GAME_HEIGHT / 900));

  const DEFAULT_LAYOUT = {
    game: {
      zoom: {
        left: {
          x: ss(ZOOM_CONFIG.margin ?? 16),
          y: GAME_HEIGHT - sy(ZOOM_CONFIG.insetHeight ?? 220) - ss(ZOOM_CONFIG.margin ?? 16),
          w: sx(ZOOM_CONFIG.insetWidth ?? 220),
          h: sy(ZOOM_CONFIG.insetHeight ?? 220)
        },
        right: {
          x: GAME_WIDTH - sx(ZOOM_CONFIG.insetWidth ?? 220) - ss(ZOOM_CONFIG.margin ?? 16),
          y: GAME_HEIGHT - sy(ZOOM_CONFIG.insetHeight ?? 220) - ss(ZOOM_CONFIG.margin ?? 16),
          w: sx(ZOOM_CONFIG.insetWidth ?? 220),
          h: sy(ZOOM_CONFIG.insetHeight ?? 220)
        },
        source: {
          w: ss(ZOOM_CONFIG.sourceWidth ?? 50),
          h: ss(ZOOM_CONFIG.sourceHeight ?? 50)
        }
      }
    },
    editor: {
      screens: ["game"],
      selectedScreen: "game"
    },
    elements: {
      game: []
    }
  };

  function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
  }

  function deepMerge(base, patch) {
    if (!patch || typeof patch !== "object") {
      return clone(base);
    }
    const out = Array.isArray(base) ? [...base] : { ...base };
    Object.keys(patch).forEach((key) => {
      const b = out[key];
      const p = patch[key];
      if (Array.isArray(b) && Array.isArray(p)) {
        out[key] = clone(p);
      } else if (b && typeof b === "object" && p && typeof p === "object") {
        out[key] = deepMerge(b, p);
      } else if (typeof p === "number" || typeof p === "string" || typeof p === "boolean") {
        out[key] = p;
      }
    });
    return out;
  }

  function loadLayout() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) {
        return clone(DEFAULT_LAYOUT);
      }
      const parsed = JSON.parse(raw);
      return deepMerge(DEFAULT_LAYOUT, parsed);
    } catch (_error) {
      return clone(DEFAULT_LAYOUT);
    }
  }

  const history = typeof window.SLIME.createLayoutHistory === "function"
    ? window.SLIME.createLayoutHistory(HISTORY_LIMIT)
    : {
        clear() {},
        canUndo: () => false,
        canRedo: () => false,
        push() {},
        undo: () => null,
        redo: () => null
      };

  const state = {
    value: loadLayout(),
    visible: false,
    panelEl: null,
    screenBarEl: null,
    screenSelectEl: null,
    screenInputEl: null,
    typeSelectEl: null,
    elementSelectEl: null,
    fieldsEl: null,
    fixedLoadInputEl: null,
    undoBtnEl: null,
    redoBtnEl: null,
    keyHandlerBound: false,
    clipboardElement: null,
    fieldEdit: {
      timerId: 0,
      before: null,
      preferredId: ""
    },
    drag: {
      active: false,
      mode: "",
      elementId: "",
      resizeHandle: "",
      startPointerX: 0,
      startPointerY: 0,
      startX: 0,
      startY: 0,
      startRect: null,
      beforeLayout: null,
      moved: false
    }
  };

  function ensureElementsRoot() {
    if (!state.value.elements || typeof state.value.elements !== "object") {
      state.value.elements = {};
    }
    if (!state.value.editor || typeof state.value.editor !== "object") {
      state.value.editor = { screens: ["game"], selectedScreen: "game" };
    }

    if (!Array.isArray(state.value.editor.screens) || state.value.editor.screens.length === 0) {
      state.value.editor.screens = ["game"];
    }

    state.value.editor.screens = state.value.editor.screens
      .map((name) => String(name || "").trim())
      .filter(Boolean);

    if (state.value.editor.screens.length === 0) {
      state.value.editor.screens = ["game"];
    }

    if (!state.value.editor.screens.includes(state.value.editor.selectedScreen)) {
      state.value.editor.selectedScreen = state.value.editor.screens[0];
    }

    state.value.editor.screens.forEach((screenName) => {
      if (!Array.isArray(state.value.elements[screenName])) {
        state.value.elements[screenName] = [];
      }
    });
  }

  function saveLayout() {
    ensureElementsRoot();
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state.value));
    } catch (_error) {
      // ignore
    }
  }

  function getActiveScreenName() {
    ensureElementsRoot();
    return state.value.editor.selectedScreen || "game";
  }

  function getElementsForActiveScreen() {
    ensureElementsRoot();
    return state.value.elements[getActiveScreenName()];
  }

  function getElementsForCurrentType() {
    const type = state.typeSelectEl ? state.typeSelectEl.value : TYPE_OPTIONS[0];
    return getElementsForActiveScreen().filter((item) => item && item.type === type);
  }

  function makeElementId() {
    return `el_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
  }

  function normalizeImagePath(value) {
    let path = String(value || "").trim().replace(/\\/g, "/");
    if ((path.startsWith('"') && path.endsWith('"')) || (path.startsWith("'") && path.endsWith("'"))) {
      path = path.slice(1, -1).trim();
    }
    if (path.startsWith("assets/")) {
      path = `./${path}`;
    }
    return path;
  }

  function createDefaultElement(type, index) {
    if (schema && typeof schema.createDefaultElement === "function") {
      return schema.createDefaultElement(type, index, { makeElementId, sx, sy, ss });
    }
    return {
      id: makeElementId(),
      type,
      name: `${type}-${index + 1}`,
      x: sx(180),
      y: sy(160),
      w: sx(220),
      h: sy(140),
      z: 0,
      imagePath: "",
      fit: "contain",
      anchor: "topleft"
    };
  }

  function getSelectedElement() {
    if (!state.elementSelectEl) {
      return null;
    }
    const id = state.elementSelectEl.value;
    if (!id) {
      return null;
    }
    return getElementsForActiveScreen().find((item) => item && item.id === id) || null;
  }

  function updateHistoryButtons() {
    if (state.undoBtnEl) {
      state.undoBtnEl.disabled = !history.canUndo();
    }
    if (state.redoBtnEl) {
      state.redoBtnEl.disabled = !history.canRedo();
    }
  }

  function renderScreenManager() {
    if (!state.screenSelectEl) {
      return;
    }
    ensureElementsRoot();
    const selected = getActiveScreenName();
    state.screenSelectEl.innerHTML = "";
    state.value.editor.screens.forEach((name) => {
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      state.screenSelectEl.appendChild(opt);
    });
    state.screenSelectEl.value = selected;
  }

  function renderElementSelect(preferredId = "") {
    if (!state.elementSelectEl) {
      return;
    }
    const items = getElementsForCurrentType();
    const currentId = preferredId || state.elementSelectEl.value;
    state.elementSelectEl.innerHTML = "";
    items.forEach((item) => {
      const opt = document.createElement("option");
      opt.value = item.id;
      opt.textContent = `${item.name || item.id} (z:${Number.isFinite(item.z) ? item.z : 0})`;
      state.elementSelectEl.appendChild(opt);
    });

    if (items.some((item) => item.id === currentId)) {
      state.elementSelectEl.value = currentId;
    } else if (items[0]) {
      state.elementSelectEl.value = items[0].id;
    }
  }

  function refreshAll(preferredId = "") {
    renderScreenManager();
    renderElementSelect(preferredId);
    renderFields();
    updateHistoryButtons();
  }

  function clearFieldEditTimer() {
    if (state.fieldEdit.timerId) {
      window.clearTimeout(state.fieldEdit.timerId);
      state.fieldEdit.timerId = 0;
    }
  }

  function flushBufferedFieldHistory() {
    clearFieldEditTimer();
    if (!state.fieldEdit.before) {
      return;
    }
    const before = state.fieldEdit.before;
    const preferredId = state.fieldEdit.preferredId;
    state.fieldEdit.before = null;
    state.fieldEdit.preferredId = "";

    if (JSON.stringify(before) !== JSON.stringify(state.value)) {
      history.push(before);
      saveLayout();
      updateHistoryButtons();
      if (preferredId) {
        renderElementSelect(preferredId);
      }
    }
  }

  function bufferFieldHistory(before, preferredId) {
    if (!state.fieldEdit.before) {
      state.fieldEdit.before = before;
      state.fieldEdit.preferredId = preferredId || "";
    }
    clearFieldEditTimer();
    state.fieldEdit.timerId = window.setTimeout(() => {
      flushBufferedFieldHistory();
    }, FIELD_HISTORY_DEBOUNCE_MS);
  }

  function runWithHistory(mutator, preferredId = "") {
    flushBufferedFieldHistory();
    const before = clone(state.value);
    mutator();
    ensureElementsRoot();

    if (JSON.stringify(before) === JSON.stringify(state.value)) {
      return false;
    }

    history.push(before);
    saveLayout();
    const preferred = typeof preferredId === "function" ? preferredId() : preferredId;
    refreshAll(preferred);
    return true;
  }

  function undoLayout() {
    flushBufferedFieldHistory();
    const previous = history.undo(clone(state.value));
    if (!previous) {
      return;
    }
    state.value = deepMerge(DEFAULT_LAYOUT, previous);
    ensureElementsRoot();
    saveLayout();
    refreshAll();
  }

  function redoLayout() {
    flushBufferedFieldHistory();
    const next = history.redo(clone(state.value));
    if (!next) {
      return;
    }
    state.value = deepMerge(DEFAULT_LAYOUT, next);
    ensureElementsRoot();
    saveLayout();
    refreshAll();
  }

  function downloadFixedLayout() {
    flushBufferedFieldHistory();
    ensureElementsRoot();
    const snapshot = clone(state.value);
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const resolution = RESOLUTION_ID || "default";
    const filename = `layout_fixed_${resolution}_${stamp}.json`;
    const blob = new Blob([`${JSON.stringify(snapshot, null, 2)}\n`], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
  }

  function applyFixedLayoutFromText(rawText) {
    let parsed;
    try {
      parsed = JSON.parse(rawText);
    } catch (_error) {
      window.alert("Invalid JSON file.");
      return;
    }

    if (!parsed || typeof parsed !== "object") {
      window.alert("Invalid layout format.");
      return;
    }

    flushBufferedFieldHistory();
    const before = clone(state.value);
    state.value = deepMerge(DEFAULT_LAYOUT, parsed);
    ensureElementsRoot();

    if (JSON.stringify(before) === JSON.stringify(state.value)) {
      return;
    }

    history.push(before);
    saveLayout();
    refreshAll();
  }

  function triggerFixedLoad() {
    if (!state.fixedLoadInputEl) {
      return;
    }
    state.fixedLoadInputEl.value = "";
    state.fixedLoadInputEl.click();
  }

  function sanitizeScreenName(value) {
    return String(value || "")
      .trim()
      .replace(/\s+/g, "_")
      .replace(/[^a-zA-Z0-9_-]/g, "");
  }

  function setActiveScreenName(nextName) {
    runWithHistory(() => {
      if (!state.value.editor.screens.includes(nextName)) {
        return;
      }
      state.value.editor.selectedScreen = nextName;
    });
  }

  function addScreen() {
    const rawName = state.screenInputEl ? state.screenInputEl.value : "";
    const name = sanitizeScreenName(rawName);
    if (!name) {
      return;
    }
    runWithHistory(() => {
      if (state.value.editor.screens.includes(name)) {
        return;
      }
      state.value.editor.screens.push(name);
      state.value.elements[name] = [];
      state.value.editor.selectedScreen = name;
      if (state.screenInputEl) {
        state.screenInputEl.value = "";
      }
    });
  }

  function addElement() {
    if (!state.typeSelectEl) {
      return;
    }
    const type = state.typeSelectEl.value;
    let createdId = "";
    runWithHistory(() => {
      const list = getElementsForActiveScreen();
      const count = list.filter((item) => item && item.type === type).length;
      const entry = createDefaultElement(type, count);
      applyRectToElement(entry, buildCanvasRect(entry));
      list.push(entry);
      createdId = entry.id;
    }, () => createdId);
  }

  function removeElement() {
    if (!state.elementSelectEl || !state.elementSelectEl.value) {
      return;
    }
    const selectedId = state.elementSelectEl.value;
    runWithHistory(() => {
      const screen = getActiveScreenName();
      state.value.elements[screen] = getElementsForActiveScreen().filter((item) => item && item.id !== selectedId);
    });
  }

  function copySelectedElement() {
    const selected = getSelectedElement();
    if (!selected) {
      return;
    }
    state.clipboardElement = clone(selected);
  }

  function pasteElement() {
    if (!state.clipboardElement) {
      return;
    }
    const source = clone(state.clipboardElement);
    let createdId = "";
    runWithHistory(() => {
      const list = getElementsForActiveScreen();
      const typeCount = list.filter((item) => item && item.type === source.type).length;
      const entry = {
        ...source,
        id: makeElementId(),
        name: `${source.type}-${typeCount + 1}`,
        x: (Number.isFinite(source.x) ? source.x : sx(180)) + 16,
        y: (Number.isFinite(source.y) ? source.y : sy(160)) + 16
      };
      applyRectToElement(entry, buildCanvasRect(entry));
      list.push(entry);
      createdId = entry.id;
    }, () => createdId);
  }

  function coerceFieldValue(element, field, rawValue) {
    if (field === "imagePath") {
      const raw = String(rawValue || "");
      return raw.startsWith("data:") ? raw : normalizeImagePath(raw);
    }
    if (field === "showPercent") {
      return !!rawValue;
    }
    if (["name", "text", "fit", "anchor", "role", "hitShape", "color", "align", "verticalAlign", "fontFamily", "weight", "fillColor", "bgColor", "panelColor"].includes(field)) {
      return String(rawValue || "");
    }

    const next = Number(rawValue);
    if (!Number.isFinite(next)) {
      return element[field];
    }
    if (field === "panelOpacity") {
      return Math.max(0, Math.min(1, next));
    }
    if (field === "panelRadius") {
      return Math.max(0, Math.round(next));
    }
    return Math.round(next);
  }

  function setElementField(field, rawValue, mode = "live") {
    const selected = getSelectedElement();
    if (!selected) {
      return;
    }

    const before = clone(state.value);
    const element = getSelectedElement();
    if (!element) {
      return;
    }

    element[field] = coerceFieldValue(element, field, rawValue);
    if (["x", "y", "w", "h", "anchor"].includes(field)) {
      applyRectToElement(element, buildCanvasRect(element));
    }
    if (JSON.stringify(before) === JSON.stringify(state.value)) {
      return;
    }

    saveLayout();
    const selectedId = selected.id;

    if (field === "name" || field === "z") {
      renderElementSelect(selectedId);
    }

    if (mode === "instant") {
      flushBufferedFieldHistory();
      history.push(before);
      updateHistoryButtons();
      return;
    }

    bufferFieldHistory(before, selectedId);
  }

  function createNumericRow(label, value, onLive, onCommit, step = "1") {
    const row = document.createElement("label");
    row.className = "layout-row";

    const span = document.createElement("span");
    span.textContent = label;

    const input = document.createElement("input");
    input.type = "number";
    input.step = step;
    input.value = String(value ?? 0);
    input.addEventListener("input", onLive);
    input.addEventListener("change", onCommit);
    input.addEventListener("blur", onCommit);

    row.appendChild(span);
    row.appendChild(input);
    return row;
  }

  function createTextRow(label, value, onLive, onCommit) {
    const row = document.createElement("label");
    row.className = "layout-row layout-row-wide";

    const span = document.createElement("span");
    span.textContent = label;

    const input = document.createElement("input");
    input.type = "text";
    input.value = String(value || "");
    input.addEventListener("input", onLive);
    input.addEventListener("change", onCommit);
    input.addEventListener("blur", onCommit);

    row.appendChild(span);
    row.appendChild(input);
    return row;
  }

  function createSelectRow(label, value, options, onChange) {
    const row = document.createElement("label");
    row.className = "layout-row layout-row-wide";

    const span = document.createElement("span");
    span.textContent = label;

    const select = document.createElement("select");
    select.className = "layout-select layout-select-inline";
    options.forEach((entry) => {
      const opt = document.createElement("option");
      if (typeof entry === "string") {
        opt.value = entry;
        opt.textContent = entry;
      } else {
        opt.value = entry.value;
        opt.textContent = entry.label;
      }
      select.appendChild(opt);
    });
    select.value = value;
    select.addEventListener("change", onChange);

    row.appendChild(span);
    row.appendChild(select);
    return row;
  }

  function createCheckboxRow(label, checked, onChange) {
    const row = document.createElement("label");
    row.className = "layout-row";

    const span = document.createElement("span");
    span.textContent = label;

    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = !!checked;
    input.addEventListener("change", onChange);

    row.appendChild(span);
    row.appendChild(input);
    return row;
  }

  function createFileRow(label, onChange) {
    const row = document.createElement("label");
    row.className = "layout-row layout-row-wide";

    const span = document.createElement("span");
    span.textContent = label;

    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/*";
    input.addEventListener("change", onChange);

    row.appendChild(span);
    row.appendChild(input);
    return row;
  }

  function renderFieldByDef(element, def) {
    const key = def.key;
    if (key === "imageFile") {
      return createFileRow(def.label, (event) => {
        const file = event.target && event.target.files ? event.target.files[0] : null;
        if (!file) {
          return;
        }
        const reader = new FileReader();
        reader.onload = () => {
          if (typeof reader.result === "string") {
            setElementField("imagePath", reader.result, "instant");
          }
        };
        reader.readAsDataURL(file);
      });
    }

    if (def.kind === "text") {
      return createTextRow(
        def.label,
        element[key],
        (event) => setElementField(key, event.target.value, "live"),
        () => flushBufferedFieldHistory()
      );
    }

    if (def.kind === "number") {
      return createNumericRow(
        def.label,
        element[key],
        (event) => setElementField(key, event.target.value, "live"),
        () => flushBufferedFieldHistory(),
        def.step || "1"
      );
    }

    if (def.kind === "select") {
      const value = key === "verticalAlign"
        ? (element[key] || "middle")
        : key === "fontFamily"
          ? (element[key] || "Segoe UI")
          : key === "role"
            ? (element[key] || "none")
          : key === "hitShape"
            ? (element[key] || "rect")
          : element[key];
      return createSelectRow(
        def.label,
        value,
        def.options || [],
        (event) => setElementField(key, event.target.value, "instant")
      );
    }

    if (def.kind === "checkbox") {
      return createCheckboxRow(
        def.label,
        !!element[key],
        (event) => setElementField(key, event.target.checked, "instant")
      );
    }

    return null;
  }

  function renderFields() {
    if (!state.fieldsEl) {
      return;
    }
    state.fieldsEl.innerHTML = "";

    const screenTitle = document.createElement("div");
    screenTitle.className = "layout-shape-empty";
    screenTitle.textContent = `Screen: ${getActiveScreenName()}`;
    state.fieldsEl.appendChild(screenTitle);

    const element = getSelectedElement();
    if (!element) {
      const empty = document.createElement("div");
      empty.className = "layout-shape-empty";
      empty.textContent = "No elements. Click Add.";
      state.fieldsEl.appendChild(empty);
      return;
    }

    const defs = schema && typeof schema.getFieldDefs === "function"
      ? schema.getFieldDefs(element.type)
      : [];

    defs.forEach((def) => {
      const row = renderFieldByDef(element, def);
      if (row) {
        state.fieldsEl.appendChild(row);
      }
    });
  }

  function buildCanvasRect(element) {
    const x = Number.isFinite(element.x) ? element.x : 0;
    const y = Number.isFinite(element.y) ? element.y : 0;
    const w = Math.max(1, Number.isFinite(element.w) ? element.w : sx(220));
    const h = Math.max(1, Number.isFinite(element.h) ? element.h : sy(140));
    if ((element.anchor || "topleft") === "center") {
      return { x: x - w / 2, y: y - h / 2, w, h };
    }
    return { x, y, w, h };
  }

  function clampRectToCanvas(rect) {
    const width = Math.max(
      MIN_ELEMENT_W,
      Math.min(GAME_WIDTH, Math.round(Number.isFinite(rect && rect.w) ? rect.w : MIN_ELEMENT_W))
    );
    const height = Math.max(
      MIN_ELEMENT_H,
      Math.min(GAME_HEIGHT, Math.round(Number.isFinite(rect && rect.h) ? rect.h : MIN_ELEMENT_H))
    );
    const maxX = Math.max(0, GAME_WIDTH - width);
    const maxY = Math.max(0, GAME_HEIGHT - height);
    const left = Math.min(maxX, Math.max(0, Math.round(Number.isFinite(rect && rect.x) ? rect.x : 0)));
    const top = Math.min(maxY, Math.max(0, Math.round(Number.isFinite(rect && rect.y) ? rect.y : 0)));
    return { x: left, y: top, w: width, h: height };
  }

  function pointInRect(rect, x, y) {
    return x >= rect.x && x <= rect.x + rect.w && y >= rect.y && y <= rect.y + rect.h;
  }

  function pointInCircle(rect, x, y) {
    const cx = rect.x + rect.w / 2;
    const cy = rect.y + rect.h / 2;
    const radius = Math.max(1, Math.min(rect.w, rect.h) / 2);
    const dx = x - cx;
    const dy = y - cy;
    return dx * dx + dy * dy <= radius * radius;
  }

  function isPointInElement(element, x, y) {
    const rect = buildCanvasRect(element);
    if (element && element.type === "object") {
      if (element.hitShape === "circle") {
        return pointInCircle(rect, x, y);
      }
    }
    return pointInRect(rect, x, y);
  }

  function applyRectToElement(element, rect) {
    const clamped = clampRectToCanvas(rect);
    const width = clamped.w;
    const height = clamped.h;
    const left = clamped.x;
    const top = clamped.y;
    const anchor = element.anchor || "topleft";

    element.w = width;
    element.h = height;
    if (anchor === "center") {
      element.x = Math.round(left + width / 2);
      element.y = Math.round(top + height / 2);
    } else {
      element.x = left;
      element.y = top;
    }
  }

  function findElementAt(x, y) {
    const sorted = getElementsForActiveScreen()
      .filter(Boolean)
      .map((item, index) => ({ item, index }))
      .sort((a, b) => {
        const az = Number.isFinite(a.item.z) ? a.item.z : 0;
        const bz = Number.isFinite(b.item.z) ? b.item.z : 0;
        if (az !== bz) {
          return bz - az;
        }
        return b.index - a.index;
      });

    for (let i = 0; i < sorted.length; i += 1) {
      const element = sorted[i].item;
      if (isPointInElement(element, x, y)) {
        return element;
      }
    }
    return null;
  }

  function getResizeHandleAt(rect, x, y) {
    if (!rect) {
      return "";
    }

    const expanded = {
      x: rect.x - RESIZE_HIT_SIZE,
      y: rect.y - RESIZE_HIT_SIZE,
      w: rect.w + RESIZE_HIT_SIZE * 2,
      h: rect.h + RESIZE_HIT_SIZE * 2
    };
    const inExpanded = x >= expanded.x
      && x <= expanded.x + expanded.w
      && y >= expanded.y
      && y <= expanded.y + expanded.h;
    if (!inExpanded) {
      return "";
    }

    const nearLeft = Math.abs(x - rect.x) <= RESIZE_HIT_SIZE;
    const nearRight = Math.abs(x - (rect.x + rect.w)) <= RESIZE_HIT_SIZE;
    const nearTop = Math.abs(y - rect.y) <= RESIZE_HIT_SIZE;
    const nearBottom = Math.abs(y - (rect.y + rect.h)) <= RESIZE_HIT_SIZE;

    if (nearTop && nearLeft) return "nw";
    if (nearTop && nearRight) return "ne";
    if (nearBottom && nearLeft) return "sw";
    if (nearBottom && nearRight) return "se";
    if (nearTop) return "n";
    if (nearBottom) return "s";
    if (nearLeft) return "w";
    if (nearRight) return "e";
    return "";
  }

  function cursorForHandle(handle) {
    if (handle === "n" || handle === "s") return "ns-resize";
    if (handle === "e" || handle === "w") return "ew-resize";
    if (handle === "nw" || handle === "se") return "nwse-resize";
    if (handle === "ne" || handle === "sw") return "nesw-resize";
    return "";
  }

  function syncSelectionWithElement(element) {
    if (!element || !state.typeSelectEl || !state.elementSelectEl) {
      return;
    }
    state.typeSelectEl.value = element.type;
    renderElementSelect(element.id);
    renderFields();
  }

  function handlePointerDown(x, y) {
    if (!state.visible) {
      return false;
    }

    flushBufferedFieldHistory();

    const selected = getSelectedElement();
    if (selected) {
      const handle = getResizeHandleAt(buildCanvasRect(selected), x, y);
      if (handle) {
        state.drag.active = true;
        state.drag.mode = "resize";
        state.drag.elementId = selected.id;
        state.drag.resizeHandle = handle;
        state.drag.startPointerX = x;
        state.drag.startPointerY = y;
        state.drag.startX = Number.isFinite(selected.x) ? selected.x : 0;
        state.drag.startY = Number.isFinite(selected.y) ? selected.y : 0;
        state.drag.startRect = buildCanvasRect(selected);
        state.drag.beforeLayout = clone(state.value);
        state.drag.moved = false;
        return true;
      }
    }

    const element = findElementAt(x, y);
    if (!element) {
      if (state.elementSelectEl && state.elementSelectEl.value) {
        state.elementSelectEl.value = "";
        renderFields();
        return true;
      }
      return false;
    }

    state.drag.active = true;
    state.drag.mode = "move";
    state.drag.elementId = element.id;
    state.drag.resizeHandle = "";
    state.drag.startPointerX = x;
    state.drag.startPointerY = y;
    state.drag.startX = Number.isFinite(element.x) ? element.x : 0;
    state.drag.startY = Number.isFinite(element.y) ? element.y : 0;
    state.drag.startRect = buildCanvasRect(element);
    state.drag.beforeLayout = clone(state.value);
    state.drag.moved = false;

    syncSelectionWithElement(element);
    return true;
  }

  function handlePointerMove(x, y) {
    if (!state.drag.active) {
      return false;
    }

    const element = getElementsForActiveScreen().find((item) => item && item.id === state.drag.elementId);
    if (!element) {
      return true;
    }

    const dx = x - state.drag.startPointerX;
    const dy = y - state.drag.startPointerY;

    if (state.drag.mode === "resize" && state.drag.startRect) {
      const handle = state.drag.resizeHandle;
      const base = state.drag.startRect;
      const next = { x: base.x, y: base.y, w: base.w, h: base.h };

      if (handle.includes("e")) next.w = base.w + dx;
      if (handle.includes("s")) next.h = base.h + dy;
      if (handle.includes("w")) {
        next.x = base.x + dx;
        next.w = base.w - dx;
      }
      if (handle.includes("n")) {
        next.y = base.y + dy;
        next.h = base.h - dy;
      }

      if (next.w < MIN_ELEMENT_W) {
        if (handle.includes("w")) {
          next.x = base.x + (base.w - MIN_ELEMENT_W);
        }
        next.w = MIN_ELEMENT_W;
      }
      if (next.h < MIN_ELEMENT_H) {
        if (handle.includes("n")) {
          next.y = base.y + (base.h - MIN_ELEMENT_H);
        }
        next.h = MIN_ELEMENT_H;
      }

      const bounded = clampRectToCanvas(next);

      const preview = buildCanvasRect(element);
      if (
        preview.x !== bounded.x
        || preview.y !== bounded.y
        || preview.w !== bounded.w
        || preview.h !== bounded.h
      ) {
        applyRectToElement(element, bounded);
        state.drag.moved = true;
        renderFields();
      }
      return true;
    }

    const baseRect = state.drag.startRect || buildCanvasRect(element);
    const bounded = clampRectToCanvas({
      x: baseRect.x + dx,
      y: baseRect.y + dy,
      w: baseRect.w,
      h: baseRect.h
    });
    const preview = buildCanvasRect(element);
    if (
      preview.x !== bounded.x
      || preview.y !== bounded.y
      || preview.w !== bounded.w
      || preview.h !== bounded.h
    ) {
      applyRectToElement(element, bounded);
      state.drag.moved = true;
      renderFields();
    }

    return true;
  }

  function handlePointerUp() {
    if (!state.drag.active) {
      return false;
    }

    if (state.drag.moved && state.drag.beforeLayout) {
      history.push(state.drag.beforeLayout);
      saveLayout();
      updateHistoryButtons();
    }

    state.drag.active = false;
    state.drag.mode = "";
    state.drag.elementId = "";
    state.drag.resizeHandle = "";
    state.drag.startRect = null;
    state.drag.beforeLayout = null;
    state.drag.moved = false;
    return true;
  }

  function getEditorCursor(x, y) {
    if (!state.visible) {
      return "";
    }
    if (state.drag.active) {
      return state.drag.mode === "resize"
        ? (cursorForHandle(state.drag.resizeHandle) || "grabbing")
        : "grabbing";
    }

    const selected = getSelectedElement();
    if (selected) {
      const handle = getResizeHandleAt(buildCanvasRect(selected), x, y);
      if (handle) {
        return cursorForHandle(handle);
      }
    }

    return findElementAt(x, y) ? "grab" : "";
  }

  function resetLayout() {
    runWithHistory(() => {
      state.value = clone(DEFAULT_LAYOUT);
      history.clear();
    });
    updateHistoryButtons();
  }

  function togglePanel(forceVisible) {
    const nextVisible = typeof forceVisible === "boolean" ? forceVisible : !state.visible;
    state.visible = nextVisible;
    if (state.panelEl) {
      state.panelEl.classList.toggle("visible", nextVisible);
    }
    if (!nextVisible) {
      handlePointerUp();
      flushBufferedFieldHistory();
      return;
    }
    refreshAll();
  }

  function bindShortcuts() {
    if (state.keyHandlerBound) {
      return;
    }
    state.keyHandlerBound = true;

    window.addEventListener("keydown", (event) => {
      const key = event.key.toLowerCase();
      const isCmdOrCtrl = event.ctrlKey || event.metaKey;
      if (!isCmdOrCtrl) {
        return;
      }

      if (key === "z" && !event.shiftKey) {
        event.preventDefault();
        undoLayout();
        return;
      }
      if (key === "y" || (key === "z" && event.shiftKey)) {
        event.preventDefault();
        redoLayout();
        return;
      }

      const activeEl = document.activeElement;
      const tag = activeEl && activeEl.tagName ? activeEl.tagName.toLowerCase() : "";
      const isTyping = tag === "input" || tag === "textarea" || tag === "select" || (activeEl && activeEl.isContentEditable);
      if (isTyping) {
        return;
      }

      if (key === "c") {
        event.preventDefault();
        copySelectedElement();
        return;
      }
      if (key === "v") {
        event.preventDefault();
        pasteElement();
      }
    });
  }

  function initEditorPanel() {
    if (state.panelEl) {
      return;
    }

    const screenBar = document.createElement("section");
    screenBar.className = "screen-manager-bar";

    const screenLabel = document.createElement("span");
    screenLabel.className = "screen-manager-label";
    screenLabel.textContent = "Screens";

    const screenSelect = document.createElement("select");
    screenSelect.className = "screen-manager-select";
    screenSelect.addEventListener("change", () => setActiveScreenName(screenSelect.value));

    const screenInput = document.createElement("input");
    screenInput.className = "screen-manager-input";
    screenInput.type = "text";
    screenInput.placeholder = "new_screen";
    screenInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        addScreen();
      }
    });

    const addScreenBtn = document.createElement("button");
    addScreenBtn.type = "button";
    addScreenBtn.className = "screen-manager-add";
    addScreenBtn.textContent = "Add Screen";
    addScreenBtn.addEventListener("click", addScreen);

    screenBar.appendChild(screenLabel);
    screenBar.appendChild(screenSelect);
    screenBar.appendChild(screenInput);
    screenBar.appendChild(addScreenBtn);
    document.body.appendChild(screenBar);

    const panel = document.createElement("aside");
    panel.className = "layout-editor";

    const title = document.createElement("div");
    title.className = "layout-title";
    title.textContent = "Layout Editor (F2)";

    const typeSelect = document.createElement("select");
    typeSelect.className = "layout-select";
    TYPE_OPTIONS.forEach((type) => {
      const opt = document.createElement("option");
      opt.value = type;
      opt.textContent = type;
      typeSelect.appendChild(opt);
    });
    typeSelect.addEventListener("change", () => refreshAll());

    const elementSelect = document.createElement("select");
    elementSelect.className = "layout-select";
    elementSelect.addEventListener("change", renderFields);

    const fields = document.createElement("div");
    fields.className = "layout-fields";

    const actions = document.createElement("div");
    actions.className = "layout-actions";

    const fixedLoadInput = document.createElement("input");
    fixedLoadInput.type = "file";
    fixedLoadInput.accept = ".json,application/json";
    fixedLoadInput.style.display = "none";
    fixedLoadInput.addEventListener("change", () => {
      const file = fixedLoadInput.files && fixedLoadInput.files[0] ? fixedLoadInput.files[0] : null;
      if (!file) {
        return;
      }
      file.text()
        .then((text) => applyFixedLayoutFromText(text))
        .catch(() => {
          window.alert("Failed to read file.");
        });
    });

    const makeButton = (label, onClick) => {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.addEventListener("click", onClick);
      return button;
    };

    const addBtn = makeButton("Add", addElement);
    const removeBtn = makeButton("Remove", removeElement);
    const copyBtn = makeButton("Copy", copySelectedElement);
    const pasteBtn = makeButton("Paste", pasteElement);
    const undoBtn = makeButton("Undo", undoLayout);
    const redoBtn = makeButton("Redo", redoLayout);
    const fixedLoadBtn = makeButton("Fixed Load", triggerFixedLoad);
    const fixedSaveBtn = makeButton("Fixed Save", downloadFixedLayout);
    const resetBtn = makeButton("Reset", resetLayout);
    const closeBtn = makeButton("Close", () => togglePanel(false));

    actions.appendChild(addBtn);
    actions.appendChild(removeBtn);
    actions.appendChild(copyBtn);
    actions.appendChild(pasteBtn);
    actions.appendChild(undoBtn);
    actions.appendChild(redoBtn);
    actions.appendChild(fixedLoadBtn);
    actions.appendChild(fixedSaveBtn);
    actions.appendChild(resetBtn);
    actions.appendChild(closeBtn);

    panel.appendChild(title);
    panel.appendChild(typeSelect);
    panel.appendChild(elementSelect);
    panel.appendChild(fields);
    panel.appendChild(fixedLoadInput);
    panel.appendChild(actions);

    document.body.appendChild(panel);

    state.panelEl = panel;
    state.screenBarEl = screenBar;
    state.screenSelectEl = screenSelect;
    state.screenInputEl = screenInput;
    state.typeSelectEl = typeSelect;
    state.elementSelectEl = elementSelect;
    state.fieldsEl = fields;
    state.fixedLoadInputEl = fixedLoadInput;
    state.undoBtnEl = undoBtn;
    state.redoBtnEl = redoBtn;

    bindShortcuts();
    refreshAll();
  }

  function getLayout() {
    return state.value;
  }

  function getSelectedElementId() {
    if (!state.elementSelectEl) {
      return "";
    }
    return state.elementSelectEl.value || "";
  }

  window.SLIME.layout = {
    get: getLayout,
    initEditorPanel,
    togglePanel,
    handlePointerDown,
    handlePointerMove,
    handlePointerUp,
    getEditorCursor,
    isVisible: () => state.visible,
    refreshForCurrentScreen: () => {},
    resetLayout,
    getSelectedElementId,
    getActiveScreenName,
    undo: undoLayout,
    redo: redoLayout,
    targets: [],
    getBuiltinText: () => null
  };
})();
