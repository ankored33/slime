window.SLIME = window.SLIME || {};

(() => {
  const { ZOOM_CONFIG, ART_BASE_WIDTH, ART_BASE_HEIGHT } = window.SLIME.constants;
  const assets = window.SLIME.assets;
  const layout = window.SLIME.layout;
  const app = window.SLIME.app;
  const { canvas, ctx, worldCanvas } = app;

  function resolveLayoutButtonAction(element) {
    const name = String(element && element.name ? element.name : "").trim().toLowerCase();
    const match = /^brush([1-5])$/.exec(name);
    if (!match) {
      return null;
    }
    const brushIndex = Number(match[1]) - 1;
    return () => {
      if (app.state.currentScreen !== "game") {
        return;
      }
      app.spawnBrushByType(brushIndex);
    };
  }

  function resolveLayoutText(element) {
    const name = String(element && element.name ? element.name : "").trim().toLowerCase();
    if (name === "selectbrushname") {
      return app.getHeldBrushName();
    }
    if (name === "selectbrushspec") {
      const heldIndex = app.state.heldBrushIndex;
      const heldBrush = Number.isInteger(heldIndex) && heldIndex >= 0
        ? app.state.brushes[heldIndex]
        : null;
      if (!heldBrush) {
        return "polish:- / pain:-";
      }
      const polish = Number.isFinite(heldBrush.polishGainPerSec) ? heldBrush.polishGainPerSec : "-";
      const pain = Number.isFinite(heldBrush.painGainPerSec) ? heldBrush.painGainPerSec : "-";
      return `polish:${polish} / pain:${pain}`;
    }
    return String(element && element.text ? element.text : "");
  }

  function resolveFontStack(fontFamily) {
    const family = typeof fontFamily === "string" ? fontFamily.trim() : "";
    if (!family) {
      return '"Segoe UI", sans-serif';
    }
    return `${family}, "Segoe UI", sans-serif`;
  }

  function drawButton(renderCtx, rect, label, primary = true) {
    renderCtx.save();

    const gradient = primary
      ? renderCtx.createLinearGradient(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h)
      : null;

    if (gradient) {
      gradient.addColorStop(0, "#f3b73f");
      gradient.addColorStop(1, "#e78e24");
      renderCtx.fillStyle = gradient;
    } else {
      renderCtx.fillStyle = "rgba(255,255,255,0.14)";
    }

    renderCtx.beginPath();
    renderCtx.roundRect(rect.x, rect.y, rect.w, rect.h, 10);
    renderCtx.fill();

    renderCtx.strokeStyle = "rgba(255,255,255,0.2)";
    renderCtx.stroke();

    renderCtx.fillStyle = primary ? "#1e1810" : "#ffffff";
    renderCtx.font = "bold 24px Segoe UI";
    renderCtx.textAlign = "center";
    renderCtx.textBaseline = "middle";
    renderCtx.fillText(label, rect.x + rect.w / 2, rect.y + rect.h / 2);
    renderCtx.restore();
  }

  function drawGauge(renderCtx, x, y, w, h, label, progress) {
    renderCtx.fillStyle = "rgba(255,255,255,0.09)";
    renderCtx.beginPath();
    renderCtx.roundRect(x, y, w, h, 10);
    renderCtx.fill();

    renderCtx.fillStyle = "rgba(255,255,255,0.9)";
    renderCtx.font = "18px Segoe UI";
    renderCtx.textAlign = "left";
    renderCtx.textBaseline = "bottom";
    renderCtx.fillText(label, x + 2, y - 6);

    const fillW = Math.max(0, Math.min(1, progress / 100)) * (w - 8);
    const gradient = renderCtx.createLinearGradient(x, y, x + w, y);
    gradient.addColorStop(0, "#62d0ff");
    gradient.addColorStop(1, "#f3b73f");
    renderCtx.fillStyle = gradient;
    renderCtx.beginPath();
    renderCtx.roundRect(x + 4, y + 4, fillW, h - 8, 6);
    renderCtx.fill();
  }

  function drawSlime(renderCtx, slime) {
    const state = app.state;
    const wobbleScale = 1 + Math.sin(state.lastTick / 90) * 0.02 * slime.wobble;
    const r = slime.radius;
    const slimeSprite = assets.getSlimeImage(state.selectedSlime, "slimeImage");

    renderCtx.save();
    renderCtx.translate(slime.x, slime.y);
    renderCtx.scale(1 + 0.04 * slime.wobble, wobbleScale);

    if (slimeSprite) {
      const width = r * 2.8;
      const height = r * 2.4;
      renderCtx.drawImage(slimeSprite, -width * 0.5, -height * 0.5, width, height);

      renderCtx.globalAlpha = 0.15 + 0.45 * slime.shine;
      renderCtx.fillStyle = "#ffffff";
      renderCtx.beginPath();
      renderCtx.ellipse(-r * 0.22, -r * 0.2, r * 0.18, r * 0.12, -0.4, 0, Math.PI * 2);
      renderCtx.fill();
      renderCtx.globalAlpha = 1;
    } else {
      const grad = renderCtx.createRadialGradient(-r * 0.3, -r * 0.35, 8, 0, 0, r * 1.2);
      grad.addColorStop(0, "#ffffff");
      grad.addColorStop(0.12, state.selectedSlime ? state.selectedSlime.color : "#a0ffc0");
      grad.addColorStop(1, "#274560");
      renderCtx.fillStyle = grad;
      renderCtx.beginPath();
      renderCtx.ellipse(0, 0, r, r * 0.82, 0, 0, Math.PI * 2);
      renderCtx.fill();
    }

    renderCtx.fillStyle = "rgba(255,255,255,0.9)";
    renderCtx.font = "16px Segoe UI";
    renderCtx.textAlign = "center";
    renderCtx.fillText(`${Math.round(slime.progress)}%`, 0, r + 24);
    renderCtx.font = "13px Segoe UI";
    renderCtx.fillText(`痛み ${Math.round(slime.painProgress)}%`, 0, r + 42);
    renderCtx.restore();
  }

  function drawBrush(renderCtx, brush, brushIndex) {
    renderCtx.save();
    renderCtx.translate(brush.x, brush.y);
    renderCtx.rotate(brush.angle);

    const brushImage = assets.getBrushImageByPath(brush.image);
    if (brushImage) {
      const size = brush.radius * 3.1;
      renderCtx.drawImage(brushImage, -size * 0.5, -size * 0.5, size, size);
    } else {
      const brushBase = brushIndex === 0 ? "#f8d089" : "#ffb3a1";
      renderCtx.fillStyle = brushBase;
      renderCtx.beginPath();
      renderCtx.arc(0, 0, brush.radius, 0, Math.PI * 2);
      renderCtx.fill();
    }

    renderCtx.restore();
  }

  function drawImageFit(renderCtx, image, target, mode) {
    const imgW = image.naturalWidth || image.width;
    const imgH = image.naturalHeight || image.height;
    if (!imgW || !imgH || !target.w || !target.h) {
      return;
    }
    const scale = mode === "cover"
      ? Math.max(target.w / imgW, target.h / imgH)
      : Math.min(target.w / imgW, target.h / imgH);
    const drawW = imgW * scale;
    const drawH = imgH * scale;
    const dx = target.x + (target.w - drawW) / 2;
    const dy = target.y + (target.h - drawH) / 2;
    renderCtx.drawImage(image, dx, dy, drawW, drawH);
  }

  function drawScreenDecorations(renderCtx, screen) {
    const decorations = assets.getScreenImages(screen);
    if (!decorations.length) {
      return;
    }

    const scaleX = canvas.width / ART_BASE_WIDTH;
    const scaleY = canvas.height / ART_BASE_HEIGHT;

    decorations.forEach(({ image, layout }) => {
      if (!image || !image.complete || image.naturalWidth <= 0) {
        return;
      }
      const x = Number.isFinite(layout.x) ? layout.x * scaleX : 0;
      const y = Number.isFinite(layout.y) ? layout.y * scaleY : 0;
      const w = Number.isFinite(layout.w) ? layout.w * scaleX : image.naturalWidth * Math.min(scaleX, scaleY);
      const h = Number.isFinite(layout.h) ? layout.h * scaleY : image.naturalHeight * Math.min(scaleX, scaleY);
      const anchor = layout.anchor || "topleft";
      const rect = {
        x: anchor === "center" ? x - w / 2 : x,
        y: anchor === "center" ? y - h / 2 : y,
        w,
        h
      };
      const fit = layout.fit || "contain";
      if (fit === "stretch") {
        renderCtx.drawImage(image, rect.x, rect.y, rect.w, rect.h);
      } else {
        drawImageFit(renderCtx, image, rect, fit === "cover" ? "cover" : "contain");
      }
    });
  }

  function drawLayoutElements(renderCtx, screen) {
    const l = layout.get();
    const elementMap = l && l.elements ? l.elements : null;
    const renderScreen = layout.getActiveScreenName ? layout.getActiveScreenName() : screen;
    const elements = elementMap && Array.isArray(elementMap[renderScreen]) ? elementMap[renderScreen] : [];
    if (!elements.length) {
      return;
    }

    const textScale = 1;
    const selectedId = layout.getSelectedElementId ? layout.getSelectedElementId() : "";
    const showSelection = !!(layout.isVisible && layout.isVisible());

    const sortedElements = elements
      .map((element, index) => ({ element, index }))
      .sort((a, b) => {
        const az = Number.isFinite(a.element && a.element.z) ? a.element.z : 0;
        const bz = Number.isFinite(b.element && b.element.z) ? b.element.z : 0;
        if (az !== bz) {
          return az - bz;
        }
        return a.index - b.index;
      });

    sortedElements.forEach(({ element }) => {
      if (!element || typeof element !== "object") {
        return;
      }
      const x = Number.isFinite(element.x) ? element.x : 0;
      const y = Number.isFinite(element.y) ? element.y : 0;
      const w = Number.isFinite(element.w) ? element.w : 0;
      const h = Number.isFinite(element.h) ? element.h : 0;
      if (w <= 0 || h <= 0) {
        return;
      }

      const anchor = element.anchor || "topleft";
      const rect = {
        x: anchor === "center" ? x - w / 2 : x,
        y: anchor === "center" ? y - h / 2 : y,
        w,
        h
      };

      const imagePath = typeof element.imagePath === "string" && element.imagePath
        ? element.imagePath
        : (typeof element.path === "string" ? element.path : "");
      const image = assets.getImageByPath(imagePath);
      const hasImage = image && image.complete && image.naturalWidth > 0;
      if (hasImage) {
        const fit = element.fit || "contain";
        if (fit === "stretch") {
          renderCtx.drawImage(image, rect.x, rect.y, rect.w, rect.h);
        } else {
          drawImageFit(renderCtx, image, rect, fit === "cover" ? "cover" : "contain");
        }
      }

      const type = element.type || "object";
      if (type === "panel" && !hasImage) {
        const opacityRaw = Number.isFinite(element.panelOpacity) ? element.panelOpacity : 0.72;
        const opacity = Math.max(0, Math.min(1, opacityRaw));
        const panelRadius = Math.max(0, Number.isFinite(element.panelRadius) ? element.panelRadius : 0);
        renderCtx.save();
        renderCtx.globalAlpha = opacity;
        renderCtx.fillStyle = element.panelColor || "#0a0c19";
        renderCtx.strokeStyle = "rgba(255,255,255,0.2)";
        if (panelRadius > 0) {
          renderCtx.beginPath();
          renderCtx.roundRect(rect.x, rect.y, rect.w, rect.h, panelRadius);
          renderCtx.fill();
          renderCtx.stroke();
        } else {
          renderCtx.fillRect(rect.x, rect.y, rect.w, rect.h);
          renderCtx.strokeRect(rect.x, rect.y, rect.w, rect.h);
        }
        renderCtx.restore();
      } else if (type === "button" && !hasImage) {
        drawButton(renderCtx, rect, element.text || element.name || "Button", true);
      } else if (type === "gauge") {
        const max = Math.max(1, Number.isFinite(element.max) ? element.max : 100);
        const value = Math.max(0, Math.min(max, Number.isFinite(element.value) ? element.value : 0));
        const ratio = value / max;
        const pad = Math.max(2, Math.round(rect.h * 0.1));
        const fillW = Math.max(0, (rect.w - pad * 2) * ratio);

        renderCtx.save();
        renderCtx.fillStyle = element.bgColor || "rgba(255,255,255,0.22)";
        renderCtx.beginPath();
        renderCtx.roundRect(rect.x, rect.y, rect.w, rect.h, 8);
        renderCtx.fill();

        renderCtx.fillStyle = element.fillColor || "#62d0ff";
        renderCtx.beginPath();
        renderCtx.roundRect(rect.x + pad, rect.y + pad, fillW, rect.h - pad * 2, 6);
        renderCtx.fill();

        renderCtx.strokeStyle = "rgba(255,255,255,0.28)";
        renderCtx.lineWidth = 1.5;
        renderCtx.strokeRect(rect.x, rect.y, rect.w, rect.h);

        if (element.text) {
          renderCtx.fillStyle = "#ffffff";
          renderCtx.font = "bold 16px Segoe UI";
          renderCtx.textAlign = "left";
          renderCtx.textBaseline = "bottom";
          renderCtx.fillText(String(element.text), rect.x, rect.y - 6);
        }

        if (element.showPercent !== false) {
          renderCtx.fillStyle = "#ffffff";
          renderCtx.font = "bold 14px Segoe UI";
          renderCtx.textAlign = "right";
          renderCtx.textBaseline = "middle";
          renderCtx.fillText(`${Math.round(ratio * 100)}%`, rect.x + rect.w - 6, rect.y + rect.h / 2);
        }
        renderCtx.restore();
      } else if (type === "text") {
        const text = resolveLayoutText(element);
        if (text) {
          const drawX = anchor === "center" ? rect.x + rect.w / 2 : rect.x;
          const verticalAlign = element.verticalAlign === "top" || element.verticalAlign === "bottom"
            ? element.verticalAlign
            : "middle";
          const drawY = verticalAlign === "top"
            ? rect.y
            : verticalAlign === "bottom"
              ? rect.y + rect.h
              : rect.y + rect.h / 2;
          const size = Math.max(10, (Number.isFinite(element.size) ? element.size : 36) * textScale);
          const align = element.align === "center" || element.align === "right" ? element.align : "left";
          const weight = element.weight === "normal" ? "normal" : "bold";
          const baseline = verticalAlign === "top"
            ? "top"
            : verticalAlign === "bottom"
              ? "bottom"
              : "middle";
          renderCtx.save();
          renderCtx.fillStyle = element.color || "#ffffff";
          renderCtx.font = `${weight} ${Math.round(size)}px ${resolveFontStack(element.fontFamily)}`;
          renderCtx.textAlign = align;
          renderCtx.textBaseline = baseline;
          renderCtx.fillText(text, drawX, drawY);
          renderCtx.restore();
        }
      } else if (!hasImage) {
        renderCtx.save();
        renderCtx.strokeStyle = "rgba(255, 255, 255, 0.45)";
        renderCtx.lineWidth = 2;
        renderCtx.setLineDash([8, 5]);
        renderCtx.strokeRect(rect.x, rect.y, rect.w, rect.h);
        renderCtx.restore();
      }

      if (type === "button") {
        const onClick = resolveLayoutButtonAction(element);
        if (onClick) {
          app.addHotspot(rect.x, rect.y, rect.w, rect.h, onClick);
        }
      }

      if (showSelection && selectedId && element.id === selectedId) {
        renderCtx.save();
        renderCtx.strokeStyle = "rgba(255, 208, 92, 0.98)";
        renderCtx.lineWidth = 3;
        renderCtx.setLineDash([]);
        renderCtx.strokeRect(rect.x - 2, rect.y - 2, rect.w + 4, rect.h + 4);

        const hs = 6;
        const points = [
          [rect.x, rect.y],
          [rect.x + rect.w / 2, rect.y],
          [rect.x + rect.w, rect.y],
          [rect.x, rect.y + rect.h / 2],
          [rect.x + rect.w, rect.y + rect.h / 2],
          [rect.x, rect.y + rect.h],
          [rect.x + rect.w / 2, rect.y + rect.h],
          [rect.x + rect.w, rect.y + rect.h]
        ];
        renderCtx.fillStyle = "rgba(255, 208, 92, 0.98)";
        points.forEach(([px, py]) => {
          renderCtx.fillRect(px - hs / 2, py - hs / 2, hs, hs);
        });
        renderCtx.restore();
      }
    });
  }

  function drawWorld(renderCtx) {
    const state = app.state;
    renderCtx.clearRect(0, 0, canvas.width, canvas.height);
    const background = assets.getScreenBackgroundImage(state.currentScreen);
    if (background) {
      drawImageFit(renderCtx, background, { x: 0, y: 0, w: canvas.width, h: canvas.height }, "cover");
    } else {
      const bg = renderCtx.createLinearGradient(0, 0, 0, canvas.height);
      bg.addColorStop(0, "#1b2250");
      bg.addColorStop(1, "#13183a");
      renderCtx.fillStyle = bg;
      renderCtx.fillRect(0, 0, canvas.width, canvas.height);
    }
    drawScreenDecorations(renderCtx, state.currentScreen);
    drawLayoutElements(renderCtx, state.currentScreen);
    state.brushes.forEach((brush, index) => drawBrush(renderCtx, brush, index));
  }

  function getNamedGameElement(type, name) {
    const l = layout.get();
    const elements = l && l.elements && Array.isArray(l.elements.game) ? l.elements.game : [];
    const targetName = String(name || "").trim().toLowerCase();
    return elements.find((element) => (
      element
      && element.type === type
      && String(element.name || "").trim().toLowerCase() === targetName
    )) || null;
  }

  function getElementRect(element) {
    const x = Number.isFinite(element && element.x) ? element.x : 0;
    const y = Number.isFinite(element && element.y) ? element.y : 0;
    const w = Math.max(1, Number.isFinite(element && element.w) ? element.w : 1);
    const h = Math.max(1, Number.isFinite(element && element.h) ? element.h : 1);
    const anchor = element && element.anchor ? element.anchor : "topleft";
    return {
      x: anchor === "center" ? x - w / 2 : x,
      y: anchor === "center" ? y - h / 2 : y,
      w,
      h
    };
  }

  function drawZoomFromNames(camName, panelName, labelText) {
    const camElement = getNamedGameElement("object", camName);
    const panelElement = getNamedGameElement("panel", panelName);
    if (!camElement || !panelElement) {
      return;
    }

    const src = getElementRect(camElement);
    const dst = getElementRect(panelElement);
    const srcX = Math.max(0, Math.min(canvas.width - src.w, src.x));
    const srcY = Math.max(0, Math.min(canvas.height - src.h, src.y));
    const srcW = Math.max(1, Math.min(canvas.width, src.w));
    const srcH = Math.max(1, Math.min(canvas.height, src.h));
    const panelRadius = Math.max(0, Number.isFinite(panelElement.panelRadius) ? panelElement.panelRadius : 0);

    ctx.save();
    if (panelRadius > 0) {
      ctx.beginPath();
      ctx.roundRect(dst.x, dst.y, dst.w, dst.h, panelRadius);
      ctx.clip();
    } else {
      ctx.beginPath();
      ctx.rect(dst.x, dst.y, dst.w, dst.h);
      ctx.clip();
    }
    ctx.drawImage(worldCanvas, srcX, srcY, srcW, srcH, dst.x, dst.y, dst.w, dst.h);
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = "rgba(255,255,255,0.65)";
    ctx.lineWidth = 2;
    if (panelRadius > 0) {
      ctx.beginPath();
      ctx.roundRect(dst.x, dst.y, dst.w, dst.h, panelRadius);
      ctx.stroke();
    } else {
      ctx.strokeRect(dst.x, dst.y, dst.w, dst.h);
    }
    if (labelText) {
      ctx.fillStyle = "rgba(255,255,255,0.9)";
      ctx.font = "14px Segoe UI";
      ctx.textAlign = "left";
      ctx.textBaseline = "bottom";
      ctx.fillText(labelText, dst.x + 8, dst.y - 6);
    }
    ctx.restore();
  }

  function drawNamedZoomInsets() {
    drawZoomFromNames("zoomCam-L", "zoom-L");
    drawZoomFromNames("zoomCam-R", "zoom-R");
  }

  function drawZoomInset(slime, side) {
    const l = layout.get();
    const zoomLayout = l.game && l.game.zoom ? l.game.zoom : null;
    const fallbackInsetW = ZOOM_CONFIG.insetWidth ?? 220;
    const fallbackInsetH = ZOOM_CONFIG.insetHeight ?? 220;
    const fallbackMargin = ZOOM_CONFIG.margin ?? 16;
    const frame = zoomLayout
      ? (side === "left" ? zoomLayout.left : zoomLayout.right)
      : {
          x: side === "left" ? fallbackMargin : canvas.width - fallbackInsetW - fallbackMargin,
          y: canvas.height - fallbackInsetH - fallbackMargin,
          w: fallbackInsetW,
          h: fallbackInsetH
        };
    const srcW = zoomLayout && zoomLayout.source ? zoomLayout.source.w : (ZOOM_CONFIG.sourceWidth ?? 50);
    const srcH = zoomLayout && zoomLayout.source ? zoomLayout.source.h : (ZOOM_CONFIG.sourceHeight ?? 50);
    const insetX = frame.x;
    const insetY = frame.y;
    const insetW = frame.w;
    const insetH = frame.h;

    const sx = Math.max(0, Math.min(canvas.width - srcW, slime.x - srcW / 2));
    const sy = Math.max(0, Math.min(canvas.height - srcH, slime.y - srcH / 2));

    ctx.save();
    ctx.fillStyle = "rgba(6, 11, 28, 0.76)";
    ctx.fillRect(insetX, insetY, insetW, insetH);
    ctx.strokeStyle = "rgba(255,255,255,0.65)";
    ctx.lineWidth = 2;
    ctx.strokeRect(insetX, insetY, insetW, insetH);

    ctx.beginPath();
    ctx.rect(insetX + 6, insetY + 6, insetW - 12, insetH - 12);
    ctx.clip();
    ctx.drawImage(worldCanvas, sx, sy, srcW, srcH, insetX + 6, insetY + 6, insetW - 12, insetH - 12);
    ctx.restore();

  }

  function drawHeartEffects(renderCtx) {
    const particles = app.state.heartParticles;
    if (!particles || particles.length === 0) {
      return;
    }

    const heartImage = assets.getHeartEffectImage();
    particles.forEach((particle) => {
      const lifeRatio = Math.max(0, particle.life / particle.maxLife);
      const growth = 1 - lifeRatio;
      const size = (particle.sizeStart ?? 10) + ((particle.sizeEnd ?? 20) - (particle.sizeStart ?? 10)) * growth;
      renderCtx.save();
      renderCtx.translate(particle.x, particle.y);
      renderCtx.rotate(particle.rotation);
      renderCtx.globalAlpha = lifeRatio;

      if (heartImage) {
        const imageSize = size * 2;
        renderCtx.drawImage(heartImage, -imageSize * 0.5, -imageSize * 0.5, imageSize, imageSize);
      } else {
        const s = size;
        renderCtx.fillStyle = "#ff6d98";
        renderCtx.beginPath();
        renderCtx.moveTo(0, s * 0.35);
        renderCtx.bezierCurveTo(s * 1.05, -s * 0.35, s * 0.75, -s * 1.25, 0, -s * 0.7);
        renderCtx.bezierCurveTo(-s * 0.75, -s * 1.25, -s * 1.05, -s * 0.35, 0, s * 0.35);
        renderCtx.fill();
      }

      renderCtx.restore();
    });
  }

  function drawHint(renderCtx) {
    const state = app.state;
    renderCtx.save();
    renderCtx.fillStyle = "rgba(255,255,255,0.85)";
    renderCtx.font = "22px Segoe UI";
    renderCtx.textAlign = "left";
    renderCtx.textBaseline = "top";

    if (state.finished) {
      renderCtx.fillText("Finish!", 24, 146);
    } else {
      const holdText = state.heldBrushIndex === null ? "none" : `${state.heldBrushIndex + 1}`;
      renderCtx.fillText("Left click: pick/release brush. R: toggle held brush spin.", 24, 146);
      renderCtx.fillText(`Held brush: ${holdText}`, 24, 174);
    }

    renderCtx.restore();
  }

  window.SLIME.render = {
    drawButton,
    drawGauge,
    drawWorld,
    drawHeartEffects,
    drawNamedZoomInsets,
    drawZoomInset,
    drawHint
  };
})();
