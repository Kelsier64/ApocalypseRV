---
name: godot-playgrounds
description: Build, convert or launch an ApocalypseRV playground (測試場, tests/playgrounds/) so the user can play-test a change by hand with the normal game controls. Use whenever a change needs visual, audio, feel or in-game verification, when creating or editing a playground scene, when an old hotkey-driven playground needs to be made usable, or when handing the user a hands-on checklist.
---

# Godot Playgrounds

A playground is a small slice of the game the user plays to judge a change by hand. Headless tests cover rules; a playground covers what only a person can judge: look, sound, feel, timing.

Older playgrounds in `tests/playgrounds/` use F-key panels, observer cameras and scripted replays. Do not copy them. Convert one to this design when the user next needs it; leave the rest alone.

The promo capture world (`tests/playgrounds/promo/`) is a filming rig, not a playground. Its F-key director panel, free camera that takes over the keyboard, and Movie Maker autoplay are deliberate; do not convert it. See [promo-capture.md](../../../docs/guides/promo-capture.md).

## Principles

1. **The user plays it like the game.** Use the production Player, RV, items and monsters with the normal input map and the normal HUD: WASD, mouse, E, F, G, the drive keys, Esc. Never rebind a game key to a playground action.
2. **Start in the state.** The scene opens already set up for the check: player in place, RV parked or seated, weather and time set. Pick variants with scenarios, not keys.
3. **One place for test-only controls.** Anything normal play cannot do (switch scenario, restart, trigger an event on demand, tune a value, show a live number) goes in the **Playground tab of the Esc menu**, built with `PlaygroundControls`. Clicked with the mouse, self-describing, the same in every playground.
4. **Hotkeys only when the menu would spoil the check**: an action needed mid-motion, while the user's hands are on the controls (for example a puncture at speed). Allow at most two, on keys the game does not use, and list them in the tab's note.
5. **No instruction overlays.** No corner text listing keys. Put one short `note` in the tab if the normal controls need a reminder.
6. **Say what is fake.** If the scene removes monsters, freezes the RV, fills fuel or raises HP, say so in the note.

## Build

```
tests/playgrounds/<topic>_playground.tscn   # root Node3D with the script, nothing else
tests/playgrounds/<topic>_playground.gd
tests/playgrounds/support/                   # PlaygroundControls, PlaygroundStage
```

Skeleton (see [rv_audio_playground.gd](../../../tests/playgrounds/rv_audio_playground.gd) for a full one):

```gdscript
extends Node3D
## One line: what the user checks here.

const SCENARIOS := ["Parked", "Night"]
var controls := PlaygroundControls.new()

func _ready() -> void:
	get_window().title = "ApocalypseRV - <Topic>"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	PlaygroundStage.flat_lot(self)
	var rv := PlaygroundStage.parked_rv(self)
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Play normally. Monsters are removed.")
	controls.readout("Speed", func(): return "%.1f m/s" % rv.linear_velocity.length())
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	PlaygroundStage.player(self, Vector3(4, 0.05, 2))
```

`PlaygroundControls` rows, in display order: `scenarios(names, current)`, `section(title)`, `note(text)`, `button(text, callable)`, `buttons([[text, callable], ...])`, `toggle(text, on, callable(bool))`, `choice(text, options, selected, callable(int))`, `slider(text, min, max, step, value, callable(float))`, `readout(text, callable -> value)`. Declare rows in `_ready`; the Esc menu builds the tab on first open and opens on it. `restart(name)` reloads the scene into a scenario; `PlaygroundControls.scenario(fallback)` reads it back, else `--scenario=<name>`.

`PlaygroundStage` holds shared set dressing: `flat_lot`, `parked_rv`, `player`. Add a helper there when a second playground needs the same setup; do not copy setup between playgrounds.

- Needs the generated world or a POI? Build on `world/world_base.gd`, read `--seed=N` from `OS.get_cmdline_user_args()` and set `WorldGenerator.world_seed` before generation, as [production_minor_poi_playground.gd](../../../tests/playgrounds/production_minor_poi_playground.gd) does, then wait for `ready_for_play`.
- Wait for physics to settle (a second of physics frames) before placing the player on or in a vehicle.
- Register any new Item or Monster scene in `core/save_scene_catalog.gd` (CLAUDE.md rule 3).
- In-game text rules apply: English, screen-space only, no `Label3D`.

## Agent-only extras

Optional, for Claude's own checks, never the user's path:

- `--capture`: render fixed shots to `.godot/<topic>-captures/` and quit. Needs a renderer, so no `--headless`. Wait two `frame_post_draw` before each shot.
- `--headless-check`: run a behavior check and quit with 0 or 1.

A scripted replay does not replace the user playing. Do not make it the default mode.

## Verify before handing off

1. Load every scenario headless and press every Playground button. Put the throwaway script in `.godot/` (ignored), run it with `godot --headless --path . --fixed-fps 60 -s res://.godot/<check>.gd`, and confirm the log has no `ERROR`, `SCRIPT ERROR` or `WARNING`.
2. If the change touched game code, also run the covering automated tests (`godot-tests` skill).

## Hand off

Launch it with `run_in_background`, logging under `.godot/`:

```powershell
godot --path . --log-file .godot/<topic>-playground.log res://tests/playgrounds/<topic>_playground.tscn
godot --path . --log-file .godot/<topic>-playground.log res://tests/playgrounds/<topic>_playground.tscn -- --scenario="Driver seat"
```

Never pass a scenario name with spaces through a `Start-Process -ArgumentList` array: PowerShell 5.1 drops the quoting and the game silently falls back to the first scenario ([launch pitfalls](../../../docs/guides/playgrounds.md#啟動與固定截圖)). Confirm the loaded scenario in the log before handing off.

Every hand-off message to the user contains all of these, even when the playground is already open:

1. **What is being tested**: one or two sentences naming the change and the question the user's play answers ("Does the new engine idle sound loop without a click?").
2. **The launch command** so the user can start or restart it themselves: the exact line in its own `powershell` block, one block per scenario that matters. Give `--path` as the absolute path of the checkout you worked in (this folder, or the worktree), so it runs from any folder:

   ```powershell
   godot --path "<absolute checkout path>" res://tests/playgrounds/<topic>_playground.tscn -- --scenario="Driver seat"
   ```

3. **A short checklist**:
   - what to do, in game terms ("sit in the driver seat, rev in neutral"), plus which Playground tab entries to use;
   - what to listen or look for, and what counts as wrong;
   - what to report back.

Do not ask whether to verify, do not loop on screenshots, and never claim you saw or heard it.

## Document

Keep one row per playground in [docs/guides/playgrounds.md](../../../docs/guides/playgrounds.md): scene, what it checks, scenarios and launch arguments. The Playground tab documents its own controls, so do not list them in the docs.
