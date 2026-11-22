# Blender authoring

Rules for modeling in Blender with Python, headless or through the MCP. They target the failures agents hit most in procedural 3D work: Blender API mismatches, parts that float or do not touch, wrong proportions, and judging by screenshots alone.

## Script structure

- **The script is the source.** Keep build steps as scripts in `art_source/<asset>/` with a rebuild order in its README, so any session can rerun them. Hand edits in the GUI are lost on the next rebuild unless saved into the `.blend` the scripts start from.
- **Build per part.** Give every part a name and build it in its own function with explicit dimensions taken from the design size. State how each part meets its neighbour (which faces touch, which joint it hangs on) in a comment or a small table, and position it from that contact, not by eye.
- **One step per run.** Run a script, read its output, then run the next. On an exception, fix the script from the traceback and rerun the same step; do not rewrite the whole asset.

## Blender 5.x API

- The installed version is Blender 5.2. Your API memory may be older: when a call fails, print `dir()` of the object or `bpy.app.version` and adapt rather than guessing again.
- Look shader nodes up by type, never by name (names are localized): `next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")`.
- Read enum identifiers at run time instead of hard-coding them, for example `[i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["file_format"].enum_items]`.
- Material colours go on shader node inputs; `material.diffuse_color` only changes the viewport.
- Actions use slots since 4.4: set `animation_data.action_slot` after assigning an action.

## Audit with numbers

Run the shared audit after every structural step and before export. It reports floating or disconnected parts, ground offset, size against the design, triangle budget, non-manifold and degenerate geometry, missing UVs, skin weights over the glTF limit and, on request, self-intersection.

```powershell
$blender = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
& $blender --background art_source/<asset>/<asset>.blend --python scripts/blender/asset_audit.py -- `
  --objects Body,Lid --size 0.6 0.6 0.9 --budget 8000 --output .godot/art-work/<asset>/audit.json
& $blender --background --factory-startup --python scripts/blender/asset_audit.py -- --glb assets/models/<asset>/<asset>.glb
```

Sizes are in Blender axes (Z up). For a model whose origin is not on the floor, pass `--ground <z>`. From the MCP, import it: `sys.path.append(r"<repo>/scripts/blender"); import asset_audit; asset_audit.audit(asset_audit.meshes(["Body"]))`.

Keep asset-specific checks (animation clips, tooth occlusion, finger flexion) in the asset's own script and call `audit()` for the shared part. After changing `asset_audit.py`, run `& $blender --background --factory-startup --python scripts/blender/test_asset_audit.py`.

## Look, then hand off

Render a fixed set of review views (front, side, back, three-quarter, top; clay and textured), read each once against the reference, and fix what the numbers and the views show. Then hand the in-game result to the user with a playground. Do not loop on more renders to decide taste.
