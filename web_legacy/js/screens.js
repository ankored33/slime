window.SLIME = window.SLIME || {};

(() => {
  const {
    SLIME_PRESETS,
    FINISH_THRESHOLD,
    RESOLUTION_KEY,
    RESOLUTION_ID,
    RESOLUTION_OPTIONS
  } = window.SLIME.constants;
  const app = window.SLIME.app;
  const gameplay = window.SLIME.gameplay;
  const render = window.SLIME.render;
  const assets = window.SLIME.assets;
  const layout = window.SLIME.layout;

  const { canvas, ctx, worldCtx } = app;

  function selectResolution(resolutionId) {
    if (!resolutionId || resolutionId === RESOLUTION_ID) {
      return;
    }
    try {
      localStorage.setItem(RESOLUTION_KEY, resolutionId);
    } catch (_error) {
      // ignore
    }
    window.location.reload();
  }

  function drawBuiltinText(id, fallbackText, fallbackX, fallbackY, fallbackStyle = {}) {
    const cfg = layout.getBuiltinText ? layout.getBuiltinText(id) : null;
    const color = (cfg && cfg.color) || fallbackStyle.color || "#ffffff";
    const align = (cfg && cfg.align) || fallbackStyle.align || "left";
    const baseline = fallbackStyle.baseline || "middle";
    const weight = (cfg && cfg.weight) || fallbackStyle.weight || "normal";
    const size = Number.isFinite(cfg && cfg.size) ? cfg.size : (fallbackStyle.size || 24);
    const x = Number.isFinite(cfg && cfg.x) ? cfg.x : fallbackX;
    const y = Number.isFinite(cfg && cfg.y) ? cfg.y : fallbackY;
    const text = (cfg && typeof cfg.text === "string" && cfg.text.length > 0) ? cfg.text : fallbackText;

    ctx.fillStyle = color;
    ctx.textAlign = align;
    ctx.textBaseline = baseline;
    ctx.font = `${weight} ${Math.round(size)}px Segoe UI`;
    ctx.fillText(text, x, y);
  }

  function drawTitleScreen(l) {
    render.drawWorld(worldCtx);
    ctx.drawImage(app.worldCanvas, 0, 0);

    ctx.fillStyle = "rgba(7, 10, 24, 0.58)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    drawBuiltinText("titleMain", "SLIME POLISH", canvas.width / 2, 300, {
      color: "#f4f7ff",
      align: "center",
      baseline: "middle",
      weight: "bold",
      size: 110
    });
    drawBuiltinText("titleSub", "回転ブラシでスライムを磨こう", canvas.width / 2, 390, {
      color: "rgba(255,255,255,0.85)",
      align: "center",
      baseline: "middle",
      weight: "normal",
      size: 36
    });

    ctx.font = "30px Segoe UI";
    ctx.fillText(`経過日数: ${app.progress.daysElapsed}日`, canvas.width / 2, 440);

    const startRect = l.title.startButton;
    render.drawButton(ctx, startRect, "はじめる", true);
    app.addHotspot(startRect.x, startRect.y, startRect.w, startRect.h, () => app.showScreen("select"));
    if (l.title.optionsButton) {
      const optionsRect = l.title.optionsButton;
      render.drawButton(ctx, optionsRect, "オプション", false);
      app.addHotspot(optionsRect.x, optionsRect.y, optionsRect.w, optionsRect.h, () => app.showScreen("options"));
    }
  }

  function drawOptionsScreen(l) {
    render.drawWorld(worldCtx);
    ctx.drawImage(app.worldCanvas, 0, 0);

    ctx.fillStyle = "rgba(7, 10, 24, 0.64)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    const panel = l.options.panel;
    ctx.fillStyle = "rgba(10, 12, 25, 0.92)";
    ctx.beginPath();
    ctx.roundRect(panel.x, panel.y, panel.w, panel.h, 14);
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.2)";
    ctx.stroke();

    drawBuiltinText("optionsTitle", "OPTIONS", canvas.width / 2, panel.y + 70, {
      color: "#ffffff",
      align: "center",
      baseline: "middle",
      weight: "bold",
      size: 54
    });

    if (RESOLUTION_OPTIONS && RESOLUTION_OPTIONS.length > 0 && l.options.resolutionButtons) {
      const resLayout = l.options.resolutionButtons;
      drawBuiltinText("optionsResolution", "解像度", canvas.width / 2, resLayout.y - 10, {
        color: "rgba(255,255,255,0.85)",
        align: "center",
        baseline: "bottom",
        weight: "normal",
        size: 24
      });

      RESOLUTION_OPTIONS.forEach((option, index) => {
        const rect = {
          x: resLayout.x + index * (resLayout.w + resLayout.gap),
          y: resLayout.y,
          w: resLayout.w,
          h: resLayout.h
        };
        const isSelected = option.id === RESOLUTION_ID;
        render.drawButton(ctx, rect, option.label, isSelected);
        app.addHotspot(rect.x, rect.y, rect.w, rect.h, () => selectResolution(option.id));
      });
    }

    if (l.options.volumeRow) {
      const row = l.options.volumeRow;
      drawBuiltinText("optionsVolume", "音量: 今後追加", row.x, row.y + row.h / 2, {
        color: "rgba(255,255,255,0.8)",
        align: "left",
        baseline: "middle",
        weight: "normal",
        size: 20
      });
    }

    if (l.options.backButton) {
      const backRect = l.options.backButton;
      render.drawButton(ctx, backRect, "もどる", false);
      app.addHotspot(backRect.x, backRect.y, backRect.w, backRect.h, () => app.showScreen("title"));
    }
  }

  function drawSelectCard(preset, rect) {
    ctx.save();
    ctx.fillStyle = "rgba(255,255,255,0.1)";
    ctx.beginPath();
    ctx.roundRect(rect.x, rect.y, rect.w, rect.h, 12);
    ctx.fill();

    ctx.strokeStyle = "rgba(255,255,255,0.2)";
    ctx.stroke();

    const thumb = assets.getSlimeImage(preset, "thumbImage");
    if (thumb) {
      ctx.drawImage(thumb, rect.x + 18, rect.y + 16, 92, 92);
    }

    ctx.fillStyle = "#f4f7ff";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.font = "bold 28px Segoe UI";
    ctx.fillText(preset.name, rect.x + 128, rect.y + 20);

    ctx.font = "22px Segoe UI";
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.fillText(`Polish: ${preset.gain}`, rect.x + 128, rect.y + 62);
    ctx.fillText(`Firmness: ${preset.firmness.toFixed(1)}`, rect.x + 128, rect.y + 94);
    ctx.fillText(`Finish: ${app.getFinishCountForSlime(preset.id)}`, rect.x + 128, rect.y + 126);
    ctx.restore();

    app.addHotspot(rect.x, rect.y, rect.w, rect.h, () => app.startGame(preset.id));
  }

  function drawSelectScreen(l) {
    render.drawWorld(worldCtx);
    ctx.drawImage(app.worldCanvas, 0, 0);

    ctx.fillStyle = "rgba(7, 10, 24, 0.58)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    drawBuiltinText("selectTitle", "スライム選択", canvas.width / 2, 90, {
      color: "#f4f7ff",
      align: "center",
      baseline: "middle",
      weight: "bold",
      size: 56
    });

    const card = l.select.cards;
    const totalW = card.w * SLIME_PRESETS.length + card.gap * (SLIME_PRESETS.length - 1);

    let x = (canvas.width - totalW) / 2;
    SLIME_PRESETS.forEach((preset) => {
      drawSelectCard(preset, { x, y: card.top, w: card.w, h: card.h });
      x += card.w + card.gap;
    });

    const backRect = l.select.backButton;
    render.drawButton(ctx, backRect, "もどる", false);
    app.addHotspot(backRect.x, backRect.y, backRect.w, backRect.h, () => app.showScreen("title"));
  }

  function drawResultScreen(l) {
    render.drawWorld(worldCtx);
    ctx.drawImage(app.worldCanvas, 0, 0);

    ctx.fillStyle = "rgba(7, 10, 24, 0.64)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    const panel = l.result.panel;
    ctx.fillStyle = "rgba(10, 12, 25, 0.92)";
    ctx.beginPath();
    ctx.roundRect(panel.x, panel.y, panel.w, panel.h, 14);
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.2)";
    ctx.stroke();

    const snapshot = app.state.resultSnapshot || {
      slimeName: app.state.selectedSlime ? app.state.selectedSlime.name : "Unknown Slime",
      day: app.progress.daysElapsed,
      finishCount: app.state.selectedSlime ? app.getFinishCountForSlime(app.state.selectedSlime.id) : 0
    };

    drawBuiltinText("resultTitle", "RESULT", canvas.width / 2, panel.y + 74, {
      color: "#ffffff",
      align: "center",
      baseline: "middle",
      weight: "bold",
      size: 64
    });

    ctx.font = "30px Segoe UI";
    ctx.fillText(`スライム名: ${snapshot.slimeName}`, canvas.width / 2, panel.y + 154);
    ctx.fillText(`${snapshot.day}日め`, canvas.width / 2, panel.y + 206);
    ctx.fillText(`Finish回数: ${snapshot.finishCount}`, canvas.width / 2, panel.y + 258);

    const nextRect = l.result.nextButton;
    render.drawButton(ctx, nextRect, "選択画面へ", true);
    app.addHotspot(nextRect.x, nextRect.y, nextRect.w, nextRect.h, () => app.showScreen("select"));
  }

  function drawGameHud(l) {
    const state = app.state;
    const finishProgress = gameplay.getFinishProgress();

    ctx.fillStyle = "rgba(6, 11, 28, 0.72)";
    ctx.fillRect(0, 0, canvas.width, l.game.hudBarHeight);

    const endDayRect = l.game.endDayButton;
    render.drawButton(ctx, endDayRect, "一日を終える", false);
    app.addHotspot(endDayRect.x, endDayRect.y, endDayRect.w, endDayRect.h, () => app.finishDayAndGoResult());

    ctx.fillStyle = "rgba(255,255,255,0.95)";
    ctx.font = "bold 32px Segoe UI";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    const name = state.selectedSlime ? state.selectedSlime.name : "";
    ctx.fillText(name, l.game.slimeNamePos.x, l.game.slimeNamePos.y);

    const leftPleasure = state.slimes[0] ? state.slimes[0].progress : 0;
    const rightPleasure = state.slimes[1] ? state.slimes[1].progress : 0;
    const leftPain = state.slimes[0] ? state.slimes[0].painProgress : 0;
    const rightPain = state.slimes[1] ? state.slimes[1].painProgress : 0;

    const gauges = l.game.gauges;
    render.drawGauge(ctx, gauges.leftPleasure.x, gauges.leftPleasure.y, gauges.leftPleasure.w, gauges.leftPleasure.h, "左 気持ちよくなる", leftPleasure);
    render.drawGauge(ctx, gauges.leftPain.x, gauges.leftPain.y, gauges.leftPain.w, gauges.leftPain.h, "左 痛み", leftPain);
    render.drawGauge(ctx, gauges.rightPleasure.x, gauges.rightPleasure.y, gauges.rightPleasure.w, gauges.rightPleasure.h, "右 気持ちよくなる", rightPleasure);
    render.drawGauge(ctx, gauges.rightPain.x, gauges.rightPain.y, gauges.rightPain.w, gauges.rightPain.h, "右 痛み", rightPain);
    render.drawGauge(ctx, gauges.finish.x, gauges.finish.y, gauges.finish.w, gauges.finish.h, "Finish", finishProgress);

    drawBuiltinText("gameFinishCond", `Finish条件: ${FINISH_THRESHOLD}%以上`, l.game.finishCondPos.x, l.game.finishCondPos.y, {
      color: "rgba(255,255,255,0.85)",
      align: "left",
      baseline: "middle",
      weight: "normal",
      size: 18
    });

    if (state.selectedSlime) {
      ctx.fillStyle = "rgba(255,255,255,0.9)";
      ctx.font = "20px Segoe UI";
      ctx.fillText(
        `経過日数: ${app.progress.daysElapsed}日  /  ${state.selectedSlime.name} Finish: ${app.getFinishCountForSlime(state.selectedSlime.id)}`,
        l.game.statusPos.x,
        l.game.statusPos.y
      );
    }
  }

  function drawFinishOverlay(l) {
    const panel = l.finishOverlay.panel;

    ctx.fillStyle = "rgba(0,0,0,0.45)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = "rgba(10,12,25,0.94)";
    ctx.beginPath();
    ctx.roundRect(panel.x, panel.y, panel.w, panel.h, 14);
    ctx.fill();

    ctx.strokeStyle = "rgba(255,255,255,0.2)";
    ctx.stroke();

    drawBuiltinText("finishTitle", "FINISH!", canvas.width / 2, panel.y + 70, {
      color: "#ffffff",
      align: "center",
      baseline: "middle",
      weight: "bold",
      size: 56
    });

    ctx.font = "24px Segoe UI";
    const name = app.state.selectedSlime ? app.state.selectedSlime.name : "Slime";
    ctx.fillText(`${name} is polished!`, canvas.width / 2, panel.y + 128);
    ctx.fillText(`Finish Gauge: ${Math.round(gameplay.getFinishProgress())}%`, canvas.width / 2, panel.y + 156);
    if (app.state.selectedSlime) {
      ctx.fillText(
        `経過日数: ${app.progress.daysElapsed}日 / ${name} Finish: ${app.getFinishCountForSlime(app.state.selectedSlime.id)}`,
        canvas.width / 2,
        panel.y + 184
      );
    }

    drawBuiltinText("finishHint", "演出後にゲージをリセットして続行します", canvas.width / 2, panel.y + 236, {
      color: "#ffffff",
      align: "center",
      baseline: "middle",
      weight: "normal",
      size: 20
    });
  }

  function drawGameScreen(dt, l) {
    gameplay.updateBrushes(dt);
    gameplay.resolveBrushCollisions();
    gameplay.updateGameplay(dt);
    render.drawWorld(worldCtx);
    ctx.drawImage(app.worldCanvas, 0, 0);
    render.drawNamedZoomInsets();
  }

  function drawFrame(now) {
    const state = app.state;
    const l = layout.get();
    const dt = Math.min(0.033, (now - state.lastTick) / 1000);
    state.lastTick = now;
    layout.refreshForCurrentScreen();

    state.uiHotspots = [];
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    if (!state.selectedSlime && SLIME_PRESETS[0]) {
      app.startGame(SLIME_PRESETS[0].id);
    }
    if (state.currentScreen !== "game") {
      app.showScreen("game");
    }

    if (state.currentScreen === "game" && state.selectedSlime) {
      drawGameScreen(dt, l);
    }

    const hovering = app.findHotspotAt(state.pointer.x, state.pointer.y);
    const editorCursor = layout.getEditorCursor(state.pointer.x, state.pointer.y);
    canvas.style.cursor = editorCursor || (hovering ? "pointer" : "default");

    requestAnimationFrame(drawFrame);
  }

  window.SLIME.screens = {
    drawFrame
  };
})();
