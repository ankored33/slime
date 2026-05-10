window.SLIME = window.SLIME || {};

(() => {
  const {
    PROGRESS_DECAY_PER_SEC,
    PAIN_GAIN_PER_SEC,
    PAIN_DECAY_PER_SEC,
    FINISH_THRESHOLD,
    FINISH_FX_DURATION_SEC,
    BRUSH_CONFIG
  } = window.SLIME.constants;
  const assets = window.SLIME.assets;
  const app = window.SLIME.app;
  const layout = window.SLIME.layout;
  const { state } = app;

  function buildElementRect(element) {
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

  function getGameObjectElementsByRole(role) {
    const data = layout && typeof layout.get === "function" ? layout.get() : null;
    const elements = data && data.elements && Array.isArray(data.elements.game)
      ? data.elements.game
      : [];
    return elements.filter((element) => (
      element
      && element.type === "object"
      && (element.role || "none") === role
    ));
  }

  function getGameElementByName(type, name) {
    const data = layout && typeof layout.get === "function" ? layout.get() : null;
    const elements = data && data.elements && Array.isArray(data.elements.game)
      ? data.elements.game
      : [];
    return elements.find((element) => (
      element
      && element.type === type
      && String(element.name || "").trim().toLowerCase() === String(name || "").trim().toLowerCase()
    )) || null;
  }

  function setGaugeValueByName(name, value) {
    const gauge = getGameElementByName("gauge", name);
    if (!gauge) {
      return;
    }
    const max = Math.max(1, Number.isFinite(gauge.max) ? gauge.max : 100);
    gauge.value = Math.max(0, Math.min(max, value));
  }

  function syncNamedGaugesFromState() {
    const left = state.slimes[0];
    const right = state.slimes[1];
    if (left) {
      setGaugeValueByName("polish-L", left.progress);
      setGaugeValueByName("pain-L", left.painProgress);
    }
    if (right) {
      setGaugeValueByName("polish-R", right.progress);
      setGaugeValueByName("pain-R", right.painProgress);
    }
  }

  function resolveSlimeTargetObjects() {
    const slimeObjects = getGameObjectElementsByRole("slime");
    if (!slimeObjects.length) {
      return { left: null, right: null };
    }

    const byName = (targetName) => slimeObjects.find((element) => (
      String(element && element.name ? element.name : "").trim().toLowerCase() === targetName
    )) || null;

    const leftByName = byName("slime-l");
    const rightByName = byName("slime-r");

    const sortedByX = [...slimeObjects].sort((a, b) => {
      const ra = buildElementRect(a);
      const rb = buildElementRect(b);
      return (ra.x + ra.w * 0.5) - (rb.x + rb.w * 0.5);
    });

    const leftFallback = sortedByX[0] || null;
    const rightFallback = sortedByX[1] || leftFallback;

    return {
      left: leftByName || leftFallback,
      right: rightByName || rightFallback
    };
  }

  function getBrushHitRadius(brush) {
    const value = Number.isFinite(brush && brush.hitRadius) ? brush.hitRadius : (brush && brush.radius);
    return Math.max(1, Number.isFinite(value) ? value : 1);
  }

  function resolveCircleVsCircle(brush, cx, cy, cr) {
    const dx = brush.x - cx;
    const dy = brush.y - cy;
    const distance = Math.hypot(dx, dy);
    const minDistance = getBrushHitRadius(brush) + cr;
    if (distance >= minDistance) {
      return false;
    }
    if (distance < 0.0001) {
      brush.x = cx + minDistance;
      brush.y = cy;
      return true;
    }
    const nx = dx / distance;
    const ny = dy / distance;
    brush.x = cx + nx * minDistance;
    brush.y = cy + ny * minDistance;
    return true;
  }

  function resolveCircleVsRect(brush, rect) {
    const nearestX = Math.max(rect.x, Math.min(brush.x, rect.x + rect.w));
    const nearestY = Math.max(rect.y, Math.min(brush.y, rect.y + rect.h));
    const dx = brush.x - nearestX;
    const dy = brush.y - nearestY;
    const distSq = dx * dx + dy * dy;
    const hitRadius = getBrushHitRadius(brush);
    const radiusSq = hitRadius * hitRadius;
    if (distSq >= radiusSq) {
      return false;
    }

    if (distSq < 0.0001) {
      const toLeft = Math.abs(brush.x - rect.x);
      const toRight = Math.abs(rect.x + rect.w - brush.x);
      const toTop = Math.abs(brush.y - rect.y);
      const toBottom = Math.abs(rect.y + rect.h - brush.y);
      const minEdge = Math.min(toLeft, toRight, toTop, toBottom);
      if (minEdge === toLeft) {
        brush.x = rect.x - hitRadius;
      } else if (minEdge === toRight) {
        brush.x = rect.x + rect.w + hitRadius;
      } else if (minEdge === toTop) {
        brush.y = rect.y - hitRadius;
      } else {
        brush.y = rect.y + rect.h + hitRadius;
      }
      return true;
    }

    const distance = Math.sqrt(distSq);
    const push = hitRadius - distance;
    brush.x += (dx / distance) * push;
    brush.y += (dy / distance) * push;
    return true;
  }

  function brushTouchesRect(brush, rect) {
    const nearestX = Math.max(rect.x, Math.min(brush.x, rect.x + rect.w));
    const nearestY = Math.max(rect.y, Math.min(brush.y, rect.y + rect.h));
    const dx = brush.x - nearestX;
    const dy = brush.y - nearestY;
    const hitRadius = getBrushHitRadius(brush);
    return dx * dx + dy * dy <= hitRadius * hitRadius;
  }

  function brushTouchesObject(brush, element) {
    const rect = buildElementRect(element);
    if (element.hitShape === "circle") {
      const cx = rect.x + rect.w / 2;
      const cy = rect.y + rect.h / 2;
      const radius = Math.max(1, Math.min(rect.w, rect.h) / 2);
      const dx = brush.x - cx;
      const dy = brush.y - cy;
      return Math.hypot(dx, dy) <= getBrushHitRadius(brush) + radius;
    }
    return brushTouchesRect(brush, rect);
  }

  function brushTouchesSlimeTarget(brush, slime, slimeObject) {
    if (slimeObject) {
      return brushTouchesObject(brush, slimeObject);
    }
    const dx = brush.x - slime.x;
    const dy = brush.y - slime.y;
    const distance = Math.hypot(dx, dy);
    const contactDistance = getBrushHitRadius(brush) + slime.radius * 0.88;
    return distance <= contactDistance;
  }

  function getFinishProgress() {
    if (state.slimes.length === 0) {
      return 0;
    }
    const totalPleasure = state.slimes.reduce((sum, slime) => sum + slime.progress, 0);
    return (totalPleasure / (state.slimes.length * 100)) * 100;
  }

  function setPainProgress(slime, nextValue) {
    slime.painProgress = Math.min(100, Math.max(0, nextValue));
  }

  function setProgress(slime, nextValue) {
    slime.progress = Math.min(100, Math.max(0, nextValue));
  }

  function pickBrushIndexAt(x, y) {
    let bestIndex = null;
    let bestDistance = Number.POSITIVE_INFINITY;

    state.brushes.forEach((brush, index) => {
      const distance = Math.hypot(brush.x - x, brush.y - y);
      if (distance <= getBrushHitRadius(brush) * 1.3 && distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    });

    return bestIndex;
  }

  function updateBrushes(dt) {
    if (state.heldBrushIndex !== null) {
      const active = state.brushes[state.heldBrushIndex];
      if (active) {
        const follow = (Number.isFinite(active.followSpeed) ? active.followSpeed : (BRUSH_CONFIG.followSpeed ?? 16)) * dt;
        active.x += (state.pointer.x - active.x) * Math.min(1, follow);
        active.y += (state.pointer.y - active.y) * Math.min(1, follow);
      }
    }

    state.brushes.forEach((brush) => {
      if (brush.isSpinning) {
        const spinSpeed = Number.isFinite(brush.spinSpeed) ? brush.spinSpeed : (BRUSH_CONFIG.spinSpeed ?? 9);
        brush.angle += spinSpeed * dt;
      }
    });
  }

  function resolveBrushCollisions() {
    const wallObjects = getGameObjectElementsByRole("wall");
    const slimeObjects = getGameObjectElementsByRole("slime");

    state.brushes.forEach((brush) => {
      wallObjects.forEach((wall) => {
        const rect = buildElementRect(wall);
        if (wall.hitShape === "circle") {
          const cx = rect.x + rect.w / 2;
          const cy = rect.y + rect.h / 2;
          const radius = Math.max(1, Math.min(rect.w, rect.h) / 2);
          resolveCircleVsCircle(brush, cx, cy, radius);
          return;
        }
        resolveCircleVsRect(brush, rect);
      });

      slimeObjects.forEach((slimeObject) => {
        const rect = buildElementRect(slimeObject);
        if (slimeObject.hitShape === "circle") {
          const cx = rect.x + rect.w / 2;
          const cy = rect.y + rect.h / 2;
          const radius = Math.max(1, Math.min(rect.w, rect.h) / 2);
          resolveCircleVsCircle(brush, cx, cy, radius);
          return;
        }
        resolveCircleVsRect(brush, rect);
      });

      state.slimes.forEach((slime) => {
        const dx = brush.x - slime.x;
        const dy = brush.y - slime.y;
        const distance = Math.hypot(dx, dy);
        const minDistance = getBrushHitRadius(brush) + slime.radius * 0.82;

        if (distance >= minDistance) {
          return;
        }

        if (distance < 0.0001) {
          brush.x = slime.x + minDistance;
          brush.y = slime.y;
          return;
        }

        const nx = dx / distance;
        const ny = dy / distance;
        brush.x = slime.x + nx * minDistance;
        brush.y = slime.y + ny * minDistance;
      });
    });
  }

  function updateGameplay(dt) {
    const slimeTargets = resolveSlimeTargetObjects();
    const anySpinningBrush = state.brushes.some((brush) => brush.isSpinning);
    let touchingAnySlime = false;

    state.slimes.forEach((slime, index) => {
      const slimeObject = index === 0 ? slimeTargets.left : slimeTargets.right;
      const touchingBrushes = !state.finished && slime.progress < 100
        ? state.brushes.filter((brush) => {
            if (!brush.isSpinning) {
              return false;
            }
            return brushTouchesSlimeTarget(brush, slime, slimeObject);
          })
        : [];
      const touching = touchingBrushes.length > 0;

      if (touching) {
        touchingAnySlime = true;
        spawnHeartFromSlime(slime, dt);
        const speedBoost = slime.wasTouching ? 1.2 : 1.0;
        const totalPolishGainPerSec = touchingBrushes.reduce((sum, brush) => {
          const gain = Number.isFinite(brush.polishGainPerSec) ? brush.polishGainPerSec : 0;
          return sum + gain;
        }, 0);
        const totalPainGainPerSec = touchingBrushes.reduce((sum, brush) => {
          const gain = Number.isFinite(brush.painGainPerSec) ? brush.painGainPerSec : PAIN_GAIN_PER_SEC;
          return sum + gain;
        }, 0);
        setProgress(slime, slime.progress + totalPolishGainPerSec * speedBoost * dt);
        setPainProgress(slime, slime.painProgress + totalPainGainPerSec * dt);
        slime.wobble = Math.min(1, slime.wobble + 3.5 * dt);
        slime.shine = Math.min(1, slime.shine + 1.9 * dt);
      } else {
        if (!state.finished && anySpinningBrush && slime.progress > 0) {
          setProgress(slime, slime.progress - PROGRESS_DECAY_PER_SEC * dt);
        }
        if (slime.painProgress > 0) {
          setPainProgress(slime, slime.painProgress - PAIN_DECAY_PER_SEC * dt);
        }
        slime.wobble = Math.max(0, slime.wobble - 2.7 * dt);
        slime.shine = Math.max(0, slime.shine - 0.8 * dt);
      }

      slime.wasTouching = touching;
    });

    updateHeartParticles(dt);
    syncNamedGaugesFromState();
    state.isPolishing = touchingAnySlime && !state.finished;
    assets.updatePolishLoopAudio(state.selectedSlime, state.isPolishing);
  }

  function spawnHeartFromSlime(slime, dt) {
    const spawnRatePerSec = 22;
    const chance = Math.min(1, spawnRatePerSec * dt);
    if (Math.random() > chance) {
      return;
    }

    const angle = Math.random() * Math.PI * 2;
    const distance = slime.radius * (0.25 + Math.random() * 0.75);
    const x = slime.x + Math.cos(angle) * distance;
    const y = slime.y + Math.sin(angle) * distance * 0.6;

    state.heartParticles.push({
      x,
      y,
      vx: (Math.random() - 0.5) * 36,
      vy: -90 - Math.random() * 55,
      life: 0.85 + Math.random() * 0.55,
      maxLife: 0.85 + Math.random() * 0.55,
      sizeStart: 12 + Math.random() * 12,
      sizeEnd: 30 + Math.random() * 22,
      rotation: (Math.random() - 0.5) * 0.6,
      spin: (Math.random() - 0.5) * 1.8
    });
  }

  function updateHeartParticles(dt) {
    if (state.heartParticles.length === 0) {
      return;
    }

    state.heartParticles = state.heartParticles.filter((particle) => {
      particle.life -= dt;
      if (particle.life <= 0) {
        return false;
      }
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particle.vy -= 38 * dt;
      particle.rotation += particle.spin * dt;
      return true;
    });
  }

  window.SLIME.gameplay = {
    getFinishProgress,
    pickBrushIndexAt,
    updateBrushes,
    resolveBrushCollisions,
    updateGameplay
  };
})();
