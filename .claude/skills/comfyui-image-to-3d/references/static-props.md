# Static prop tool `prepare_prop.py`

Offline (needs numpy); never submits ComfyUI work or modifies the source. Accepts only: one mesh node without a transform, one indexed TRIANGLES primitive, float32 POSITION/NORMAL/TEXCOORD_0 (TANGENT optional) and embedded PNGs. Use Blender for animation, skins, morphs, extensions or multi-material models; do not force-merge them to pass the checks.

## prepare

```powershell
& $py "$skill/scripts/prepare_prop.py" prepare --source "$work/generation/raw.glb" --output "$work/prepared" `
  --asset <asset> --size 1.2 2.35 0.72 --origin bottom-center --front +Z --rotation-y 0 --ratio 0.12 --error 0.025
```

| Flag | Meaning |
|---|---|
| `--size X Y Z` | Final bounding box in meters, scaled per axis. Use one factor for all three axes to keep proportions |
| `--origin` | `bottom-center` (sits on the ground) or `center` (common for pickups) |
| `--rotation-y` | Degrees, applied before scaling. Decide from the raw front render |
| `--front` | Records the intended front only; the tool cannot detect it, so confirm by eye |
| `--ratio`, `--error` | gltfpack decimation; omit `--ratio` to skip it. `--gltfpack` picks the executable |

Output goes to a new folder: `fitted.glb`, `reduced.glb`, `final.glb`, `model_parameters.json` (size, triangles, topology counts, hashes, generation source) and `editable/` (glTF/BIN with external textures). Normals are corrected with the inverse transpose; collapsed tangents are rebuilt from UVs and orthogonalized; topology problems are counted, not fixed. Image bytes match the raw.

Review again with `review.py --source "$work/prepared/final.glb"`; a successful run is not art approval.

## Rescale only

If the shape is right and only the scale is off, do not regenerate. Scale uniformly against characters and the scene. Keep the Godot rigid-body root at scale 1: adjust the visual node and sync collision size and placement height, then check grounding, pickup and hand-held use. Record the GLB size and the final in-scene size separately.

## Publish into a graybox wrapper

Only for wrappers whose `Visuals/Model` is a Node3D not yet wired to an `Asset`. Back up the wrapper and list the graybox children to hide with `--hide`:

```powershell
Copy-Item '<wrapper>.tscn' "$work/wrapper.before.tscn"
& $py "$skill/scripts/prepare_prop.py" publish --prepared "$work/prepared" --scene '<wrapper>.tscn' `
  --expected-scene "$work/wrapper.before.tscn" --hide Blockout Panel
```

The tool checks the backup and the final hash, keeps original line endings, Model properties, node names and collision, and only adds the GLB instance and hides the graybox. It writes `assets/models/<asset>/<asset>.glb` and `art_source/<asset>/{editable/,model_parameters.json}`, and stops if delivery files already exist or the scene changed meanwhile. Add the reference image and README to `art_source/<asset>/` yourself. Then import in Godot and confirm size, origin, orientation, every use site and related behavior.

Edit other wrappers or already-integrated assets directly; never move collision to fit the look.
