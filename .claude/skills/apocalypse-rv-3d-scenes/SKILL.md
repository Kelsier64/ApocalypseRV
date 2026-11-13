---
name: apocalypse-rv-3d-scenes
description: Workflow and rules for building or editing ApocalypseRV 3D content in Godot — scenes, POIs, buildings, RV parts, props, equipment — and for replacing graybox or placeholder visuals with finished assets. Use before creating, modeling, re-skinning, placing or reviewing any 3D content in .tscn/.glb files, when choosing between hand-built meshes and image-to-3D generation, or when a task touches text or labels on models.
---

# ApocalypseRV 3D Scenes

Default loop: build what the task needs → review it once in its real scene → run the checks the change affects → report briefly. Keep small changes to local checks; expand only for new changes, failures or open concerns. Add scripts, delegation, long reports or delivery packages only when the work needs them or the user asks.

## Choose how to build

| Content | Approach |
|---|---|
| Walls, floors, ramps, shells, anything a few meshes and materials can cover | Build it directly in Godot, visuals and function together |
| Static props, decoration, crates, barrels, components, equipment with clear silhouettes where approximate detail is fine | Generate with the `comfyui-image-to-3d` skill |
| Precise structure, openings, mating parts, moving joints, collision, interaction | Native meshes. A generated mesh may only be a visual shell over them |
| Large buildings | Split into components (facade sections, entrance assemblies, roof equipment, interior fittings) |

For split buildings, keep the layout and assembly in Godot and make each component replaceable on its own. Record each component's target node, local placement, orientation, and the adjoining dimensions or openings it must fit. Repeated instances share one asset. Build simple structural parts directly rather than generating them.

## Replace visuals without breaking gameplay

- Swap only the visual node. Keep the wrapper tree, collision, node names and gameplay behavior; never move collision to fit a new look.
- Check local axes, origin, design dimensions and placement in the target scene, not just in isolation.
- A graybox in the right place is not a finished visual. Inspect the integrated asset itself.

## Look at the result

You can read PNGs with the Read tool, so render and look rather than infer from numbers.

- **A single GLB:** `comfyui-image-to-3d`'s `review.py` renders 12 views (six angles, textured and clay).
- **In context:** render the integrated asset from the gameplay camera with a playground capture flag and read the PNGs before reporting. The `playtest` skill's "Render Captures First" section has the command and pitfalls.
- Compare against the surrounding cab or room: clean vector art and self-lit flat panels read as UI pasted into the world.
- Use computer use only when the check needs live interaction.

## Textures added outside the editor

`godot --headless --path . --import` creates the `.import` file without mipmaps. For any texture shown in 3D, set `mipmaps/generate=true` in it and import again, or thin lines shimmer at the default render scale.

## Text on models

The full rule is hard rule 1 in [CLAUDE.md](../../../CLAUDE.md); a hook blocks `Label3D`/`TextMesh` in game code. For 3D work in practice:

- Never put hints, controls, instructions, item names or status labels on models, textures or in the world. No `Label3D`, `TextMesh`, floating, camera-facing, white/glowing or unshaded text.
- Add words only where the fiction needs them (an essential sign, a manufacturer plate, a real instrument screen), as an authored texture, decal or device screen that matches the surface's lighting, wear and scale.
- Do not add decorative wording by default, disguise hints as texture art, or let scene generators restore removed labels. Reference images and generated assets follow the same rule.

## Blender

Blender 5.2 is on PATH. Use it headless for remeshing, baking, inspection and export:

```powershell
blender --background --python <script.py> -- <args>
```

Keep scripts in an ignored work folder under `.godot/` unless they are a reusable build step (existing ones live in `scripts/build_*.py`).

`.mcp.json` also configures a Blender MCP server (`mcp-for-blender`, safe mode) for interactive work in a running Blender. Prefer the CLI; use the MCP when you need to inspect or edit a scene the user has open. Ask the user to open Blender only when the task truly needs the GUI and the CLI cannot do it; say what you tried.
