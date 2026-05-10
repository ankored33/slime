window.SLIME = window.SLIME || {};

(() => {
  const { TEXT_FONT_OPTIONS = [{ value: "Segoe UI", label: "Segoe UI" }] } = window.SLIME.constants || {};
  const typeOptions = ["text", "panel", "button", "object", "gauge"];

  const fieldDefs = {
    common: [
      { key: "name", label: "name", kind: "text" },
      { key: "z", label: "z", kind: "number" },
      { key: "x", label: "x", kind: "number" },
      { key: "y", label: "y", kind: "number" },
      { key: "w", label: "w", kind: "number" },
      { key: "h", label: "h", kind: "number" },
      { key: "imageFile", label: "imageFile", kind: "file" },
      { key: "imagePath", label: "imagePath", kind: "text" },
      {
        key: "fit",
        label: "表示方法",
        kind: "select",
        options: [
          { value: "contain", label: "収める" },
          { value: "cover", label: "覆う" },
          { value: "stretch", label: "引き伸ばし" }
        ]
      },
      {
        key: "anchor",
        label: "基準位置",
        kind: "select",
        options: [
          { value: "topleft", label: "左上" },
          { value: "center", label: "中央" }
        ]
      }
    ],
    text: [
      { key: "text", label: "text", kind: "text" },
      { key: "size", label: "size", kind: "number" },
      {
        key: "align",
        label: "align",
        kind: "select",
        options: ["left", "center", "right"]
      },
      {
        key: "verticalAlign",
        label: "縦揃え",
        kind: "select",
        options: [
          { value: "top", label: "上" },
          { value: "middle", label: "中央" },
          { value: "bottom", label: "下" }
        ]
      },
      {
        key: "fontFamily",
        label: "font",
        kind: "select",
        options: TEXT_FONT_OPTIONS
      },
      {
        key: "weight",
        label: "weight",
        kind: "select",
        options: ["normal", "bold"]
      },
      { key: "color", label: "color", kind: "text" }
    ],
    button: [
      { key: "text", label: "text", kind: "text" }
    ],
    gauge: [
      { key: "text", label: "label", kind: "text" },
      { key: "value", label: "value", kind: "number" },
      { key: "max", label: "max", kind: "number" },
      { key: "fillColor", label: "fillColor", kind: "text" },
      { key: "bgColor", label: "bgColor", kind: "text" },
      { key: "showPercent", label: "showPercent", kind: "checkbox" }
    ],
    panel: [
      { key: "panelColor", label: "panelColor", kind: "text" },
      { key: "panelOpacity", label: "panelOpacity", kind: "number", step: "0.01" },
      { key: "panelRadius", label: "panelRadius", kind: "number", step: "1" }
    ],
    object: [
      {
        key: "role",
        label: "role",
        kind: "select",
        options: ["none", "slime", "wall"]
      },
      {
        key: "hitShape",
        label: "hitShape",
        kind: "select",
        options: ["rect", "circle"]
      }
    ]
  };

  function createDefaultElement(type, index, helpers) {
    const { makeElementId, sx, sy, ss } = helpers;
    return {
      id: makeElementId(),
      type,
      name: `${type}-${index + 1}`,
      z: 0,
      text: type === "text" ? "New Text" : "",
      x: sx(180),
      y: sy(160),
      w: type === "text" ? sx(320) : (type === "gauge" ? sx(360) : sx(220)),
      h: type === "text" ? sy(84) : (type === "gauge" ? sy(44) : sy(140)),
      imagePath: "",
      fit: "contain",
      anchor: "topleft",
      role: "none",
      hitShape: "rect",
      color: "#ffffff",
      size: ss(36),
      align: "left",
      verticalAlign: "middle",
      fontFamily: "Segoe UI",
      weight: "bold",
      value: 50,
      max: 100,
      fillColor: "#62d0ff",
      bgColor: "rgba(255,255,255,0.22)",
      showPercent: true,
      panelColor: "#0a0c19",
      panelOpacity: 0.72,
      panelRadius: 0
    };
  }

  function getFieldDefs(type) {
    const specific = fieldDefs[type] || [];
    return [...fieldDefs.common, ...specific];
  }

  window.SLIME.layoutSchema = {
    typeOptions,
    createDefaultElement,
    getFieldDefs
  };
})();
