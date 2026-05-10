# Godot migration scaffold

This directory now contains the first concrete replacement for `layout.js` concepts using Godot scenes and exported node data.

## Current structure

- `scenes/game_screen.tscn`
  - The `game` screen is authored directly as a Godot scene.
- `scenes/slime_target.tscn`
  - Replaces `object` elements with `role=slime`.
- `scenes/wall_zone.tscn`
  - Replaces `object` elements with `role=wall`.
- `scenes/named_gauge.tscn`
  - Replaces named `gauge` elements such as `polish-L`.
- `scenes/brush.tscn`
  - Carries brush tuning as exported properties.

## Mapping from the web editor model

- `type=object`, `role=slime`
  - Use a `SlimeTarget` scene instance.
- `type=object`, `role=wall`
  - Use a `WallZone` scene instance.
- `type=gauge`, `name=polish-L`
  - Use a `NamedGauge` instance and set `gauge_id`.
- `x`, `y`, `w`, `h`, `anchor`
  - Use node transforms and Control layout directly in the Godot editor.
- `imagePath`, `fit`, extra metadata
  - Move to exported fields on purpose-built scene scripts only when needed.

## Direction

The important change is architectural:

1. Stop treating the screen as generic runtime-authored JSON.
2. Treat the screen as a Godot-authored scene.
3. Keep only game-specific metadata as exported properties on nodes.
4. Add runtime debug tools later only if tuning actually needs them.

## Next useful steps

- Port the real brush collision and push-out logic from `js/gameplay.js`.
- Attach actual slime sprites and wall art to the placeholder nodes.
- Add a small save layer in `user://` only for tunable gameplay values, not full layout authoring.
