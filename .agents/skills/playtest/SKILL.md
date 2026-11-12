---
name: playtest
description: Use when an ApocalypseRV change needs live on-screen verification in the running game (climbing, turning, roof destruction, driving feel, visuals) through desktop control, or when launching a playground scene.
---

# Live Playtest

Use live play only when headless tests and renders cannot answer the question. If the user's visual judgment is what matters, ask them to look instead.

## Render Captures First

For a static look (a model, a dashboard, lighting, a fixed vehicle state) render and read the image yourself; no desktop control is needed.

```powershell
godot --path . --log-file .godot/rv-workshop-capture.log res://tests/rv_design_workshop.tscn -- --capture
```

- Scenes with a capture flag are listed in [docs/guides/playgrounds.md](../../../docs/guides/playgrounds.md). They write PNGs under `.godot/<name>-captures/`, print each path as `CAPTURE:`, and quit. Open the PNGs with your image reader.
- Never pass `--headless`: it has no renderer and produces empty images.
- When a scene you need has no capture flag, add one that follows [rv_design_workshop.gd](../../../tests/rv_design_workshop.gd): fixed states, the real gameplay camera plus a close-up, two `frame_post_draw` waits before each grab.
- A camera that is not parented to a moving vehicle must be repositioned every frame, and an observer camera needs the gameplay camera's `cull_mask` or it sees the player's own head.
- Outdoor 3D renders at 540 lines by default (`render_mode` in `core/game_settings.gd`). Judge legibility at that scale, not in a close-up.
- Report captures as fixed-state renders. They say nothing about motion, feel or timing.

## Launch

Launch from the shell with an explicit log, never through the editor:

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

Omit `-- --replay` for manual WASD/Space play. Controls and arguments for every other scene are in [docs/guides/playgrounds.md](../../../docs/guides/playgrounds.md). Check the scene's `_unhandled_input` before trusting a key you have not used.

`rv_climb_playground` keys:

| Key | Action |
|---|---|
| F2 | Toggle scripted driving |
| F3 | Start the roof-ladder climb replay |
| F4 | Toggle the observer camera |
| F5 | Seat the player and run the roof-smash demo |
| F6 | Toggle the cabin view |
| F7 | Side-door ladder route |
| F9 | Capture the current view |
| F10 | Placement review on the roof ladder |
| R | Reload the scene |

## Drive the Window

1. Load your agent's desktop-control guidance first: the `computer-use` skill in Claude Code; `node_repl` with `@oai/sky` in Codex.
2. Select exactly one game window. Never target the Godot editor, and never invent window IDs.
3. Observe before each key press. Take a new screenshot only to verify a result.
4. Short key presses cannot stand in for sustained movement. Use `--replay` for continuous input.

## Climbing Checklist

- Both actors climb and stay aboard through turns.
- After F5, roof HP reaches `DESTROYED` and the monster falls.
- The log has no `SCRIPT ERROR` or `ERROR` lines.

## Finish

Close only your own game window. Report what you observed separately from automated checks and from what you did not test. Replay uses scripted vehicle motion, so wheel-driven handling, rollovers and crowds still need separate testing.
