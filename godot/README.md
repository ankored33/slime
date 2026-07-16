# Godot gameplay migration

## Current structure

- `scripts/game_rules.gd`
  - Pure gameplay formulas (`GameRules`): level curve, polish/pain modifiers, FINISH retention, fail penalty, rect push-out. Node-free and unit-tested.
- `tests/run_tests.gd`
  - Headless unit tests for `GameRules`. Run with `godot --headless -s res://tests/run_tests.gd` (exits 1 on failure).
- `scenes/game_screen.tscn`
  - Play screen authored directly in Godot.
- `scripts/game_screen.gd`
  - Day progression, gauges, FINISH/failure rules, expressions, and presentation orchestration.
- `scripts/game_screen_brushes.gd`
  - Brush discovery, input/dragging, unlock controls, and collision correction.
- `scenes/slime_target.tscn`
  - Slime target node with species-driven radius/color.
- `scenes/wall_zone.tscn`
  - Wall collision zones for brush push-out.
- `scenes/named_gauge.tscn`
  - Named gauge widget (`polish-L`, `pain-R`, etc.).
- `scenes/brush.tscn`
  - Brush node with on/off and temporary special boost tuning.

## Implemented scope (non-editor)

- Select -> Play -> Result flow is running in `main.gd`.
- Species-level progression (`finish_total`, `pain_fail_total`, level-up) is active.
- Day loop rules are active:
  - Voluntary end day
  - Forced fail at pain >= 100%
  - Fail penalty = banked finish halved
  - FINISH threshold + post-finish polish retention by level
- Regular brushes work only while rubbing; the rotating brush alone has an on/off toggle.
- All brushes use click-to-hold movement and can trigger temporary specials.
- Brush overlap resolution and wall push-out are active in play.
- Progress is saved/loaded via `user://slime_save_v2.json`.

## Explicitly out of scope

- Runtime layout editor from the deleted `web_legacy` (see Git history)
- Generic runtime-authored JSON layout workflow

## Remaining work

- Port final art/audio assets to Godot scenes/resources (placeholder rendering for now).
- FINISH effects and per-level reaction variants (see `docs/game_spec_v0_2.md`).
- Verify gameplay constants against desired balance targets.
- Consider moving hardcoded species data in `scripts/main.gd` to `.tres` resources.
