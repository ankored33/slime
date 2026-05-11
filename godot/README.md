# Godot gameplay migration

## Current structure

- `scenes/game_screen.tscn`
  - Play screen authored directly in Godot.
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
- Brushes can be dragged, toggled independently, and special-triggered.
- Brush overlap resolution and wall push-out are active in play.
- Progress is saved/loaded via `user://slime_save_v1.json`.

## Explicitly out of scope

- Runtime layout editor from `web_legacy/layout.js`
- Generic runtime-authored JSON layout workflow

## Remaining before deleting `web_legacy`

- If visual parity is required, port final art/audio assets to Godot scenes/resources.
- Verify gameplay constants against desired balance targets.
- Run a final QA pass in Godot and freeze legacy-independent behavior.
