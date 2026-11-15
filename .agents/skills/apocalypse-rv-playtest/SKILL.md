---
name: apocalypse-rv-playtest
description: Launch ApocalypseRV playgrounds, capture Godot renders, and verify visible behavior or gameplay feel.
---

# ApocalypseRV Playtest

Choose a scene and arguments from the [playground guide](../../../docs/guides/playgrounds.md). Start Godot directly from the project root and log under `.godot/`.

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

- For user play, launch at the relevant state and give a short checklist of controls and expected results. Omit `-- --replay` for manual control.
- For static visuals, use a playground's `--capture` mode without `--headless`. Inspect the images listed as `CAPTURE:`. Follow [rv_design_workshop.gd](../../../tests/rv_design_workshop.gd) when adding a fixed capture.
- Drive the game only when asked, using the available Codex desktop tools. Check that the game window is selected since the editor uses the same executable. Verify controls in `_unhandled_input`. Use scripted replays for sustained movement when applicable.
- Check logs for errors and close only game windows you started. State whether evidence came from a fixed render, replay, hands-on play, or automated test. Scripted RV motion leaves driving feel and rollover for hands-on testing.
