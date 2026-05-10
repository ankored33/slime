window.SLIME = window.SLIME || {};

(() => {
  const app = window.SLIME.app;
  const RESOLUTION_ID = window.SLIME.constants && window.SLIME.constants.RESOLUTION_ID
    ? window.SLIME.constants.RESOLUTION_ID
    : "default";
  const STORAGE_KEY = `slime_brush_editor_v1:${RESOLUTION_ID}`;
  const EDITABLE_KEYS = [
    "image",
    "radius",
    "hitRadius",
    "followSpeed",
    "spinSpeed",
    "polishGainPerSec",
    "painGainPerSec"
  ];

  const state = {
    visible: false,
    panelEl: null,
    selectEl: null,
    fieldsEl: null
  };

  function getSpecs() {
    const specs = app.getBrushSpecs();
    return Array.isArray(specs) ? specs : [];
  }

  function pickEditableFields(spec) {
    const out = {};
    EDITABLE_KEYS.forEach((key) => {
      if (Object.prototype.hasOwnProperty.call(spec || {}, key)) {
        out[key] = spec[key];
      }
    });
    return out;
  }

  function saveToStorage() {
    const specs = getSpecs();
    const payload = specs.map((spec) => pickEditableFields(spec));
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    } catch (_error) {
      // ignore
    }
  }

  function loadFromStorage() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) {
        return;
      }
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return;
      }
      parsed.forEach((patch, index) => {
        if (!patch || typeof patch !== "object") {
          return;
        }
        app.updateBrushSpec(index, patch, true);
      });
    } catch (_error) {
      // ignore
    }
  }

  function getSelectedIndex() {
    if (!state.selectEl) {
      return 0;
    }
    const index = Number(state.selectEl.value);
    if (!Number.isInteger(index) || index < 0) {
      return 0;
    }
    return index;
  }

  function createRow(label, value, onChange, type = "number", step = "1") {
    const row = document.createElement("label");
    row.className = type === "text" ? "layout-row layout-row-wide" : "layout-row";

    const span = document.createElement("span");
    span.textContent = label;

    const input = document.createElement("input");
    input.type = type;
    input.value = String(value ?? "");
    if (type === "number") {
      input.step = step;
    }
    input.addEventListener("change", () => onChange(input.value));

    row.appendChild(span);
    row.appendChild(input);
    return row;
  }

  function renderFields() {
    if (!state.fieldsEl) {
      return;
    }
    state.fieldsEl.innerHTML = "";

    const specs = getSpecs();
    const index = getSelectedIndex();
    const spec = specs[index];
    if (!spec) {
      const empty = document.createElement("div");
      empty.className = "layout-shape-empty";
      empty.textContent = "No brush specs.";
      state.fieldsEl.appendChild(empty);
      return;
    }

    const setField = (key, value) => {
      const ok = app.updateBrushSpec(index, { [key]: value }, true);
      if (ok) {
        saveToStorage();
      }
    };

    state.fieldsEl.appendChild(createRow("image", spec.image || "", (value) => setField("image", value), "text"));
    state.fieldsEl.appendChild(createRow("radius", spec.radius, (value) => setField("radius", value), "number", "1"));
    state.fieldsEl.appendChild(createRow("hitRadius", spec.hitRadius, (value) => setField("hitRadius", value), "number", "1"));
    state.fieldsEl.appendChild(createRow("followSpeed", spec.followSpeed, (value) => setField("followSpeed", value), "number", "0.1"));
    state.fieldsEl.appendChild(createRow("spinSpeed", spec.spinSpeed, (value) => setField("spinSpeed", value), "number", "0.1"));
    state.fieldsEl.appendChild(createRow("polishGainPerSec", spec.polishGainPerSec, (value) => setField("polishGainPerSec", value), "number", "0.1"));
    state.fieldsEl.appendChild(createRow("painGainPerSec", spec.painGainPerSec, (value) => setField("painGainPerSec", value), "number", "0.1"));
  }

  function renderSelect() {
    if (!state.selectEl) {
      return;
    }
    const specs = getSpecs();
    const current = getSelectedIndex();
    state.selectEl.innerHTML = "";
    specs.forEach((_, index) => {
      const option = document.createElement("option");
      option.value = String(index);
      option.textContent = `brush${index + 1}`;
      state.selectEl.appendChild(option);
    });
    if (specs.length > 0) {
      const selected = Math.max(0, Math.min(specs.length - 1, current));
      state.selectEl.value = String(selected);
    }
  }

  function refresh() {
    renderSelect();
    renderFields();
  }

  function togglePanel(forceVisible) {
    const nextVisible = typeof forceVisible === "boolean" ? forceVisible : !state.visible;
    state.visible = nextVisible;
    if (state.panelEl) {
      state.panelEl.classList.toggle("visible", nextVisible);
    }
    if (nextVisible) {
      refresh();
    }
  }

  function initPanel() {
    if (state.panelEl) {
      return;
    }

    const panel = document.createElement("aside");
    panel.className = "layout-editor brush-editor";

    const title = document.createElement("div");
    title.className = "layout-title";
    title.textContent = "Brush Editor (F2)";

    const select = document.createElement("select");
    select.className = "layout-select";
    select.addEventListener("change", renderFields);

    const fields = document.createElement("div");
    fields.className = "layout-fields";

    const actions = document.createElement("div");
    actions.className = "layout-actions";

    const closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.textContent = "Close";
    closeBtn.addEventListener("click", () => togglePanel(false));
    actions.appendChild(closeBtn);

    panel.appendChild(title);
    panel.appendChild(select);
    panel.appendChild(fields);
    panel.appendChild(actions);
    document.body.appendChild(panel);

    state.panelEl = panel;
    state.selectEl = select;
    state.fieldsEl = fields;

    loadFromStorage();
    refresh();
  }

  window.SLIME.brushEditor = {
    initPanel,
    togglePanel,
    isVisible: () => state.visible
  };
})();
