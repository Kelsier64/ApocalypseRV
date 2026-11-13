---
name: comfyui-image-to-3d
description: Turn one reference image into a textured, game-ready GLB with the local ComfyUI TRELLIS.2 service, then review it in Godot renders, fit and decimate it, and wire it into ApocalypseRV. Use for static props, decoration, crates, barrels, components and equipment with clear silhouettes where approximate detail is acceptable — whenever a task asks to generate, replace or upgrade a model from an image, or to make a graybox prop look finished.
---

# Image → 3D

Run the whole pipeline yourself: reference image → generate → review → fit/decimate → integrate. Start as soon as the asset is clear; ask the user only for real choices (look, scale, which reference).

## Fit for purpose

- **Good:** static props, decoration, crates and barrels, components, equipment — clear silhouette, approximate detail is fine.
- **Not directly:** wall panels, floors, precise openings, parts that must mate exactly, moving joints, rigged characters. Generate the look if useful, but build structure, moving parts and rigs separately; simple geometry is faster to model by hand.
- **Expect:** the hidden back is guessed, so parts can be missing, fused or skewed, and straight lines may bend. The GLB almost always needs size, orientation and origin fixes; collision and interaction are separate work.

## Setup

Run from the repository root with the PowerShell tool. The scripts need Pillow (`prepare_prop.py` also needs numpy). Use the ComfyUI runtime venv rather than installing globally:

```powershell
$skill = '.claude/skills/comfyui-image-to-3d'
$py = "$env:USERPROFILE/Apps/ComfyUI/pixal3d-runtime/.venv/Scripts/python.exe"   # or any Python with Pillow + numpy
$work = '.godot/art-work/<asset>/run-01'                                          # a fresh ignored folder per run
```

Shell state does not persist between tool calls, so repeat these assignments at the top of every command.

The service entry point is `http://127.0.0.1:8000/health`; the scripts find the ComfyUI backend (8188) through it. A refused `preflight` connection means the service is not running, not that the graph is broken — see [operations](references/operations.md#start-the-service).

## 1. Reference image

Reuse a suitable existing image first (`art_source/<asset>/`, `docs/modeling/requests/`). If none fits, have Gemini draw one through the user-level `agy` skill — see [reference images](references/reference-images.md) for the brief and checks. If agy fails, write the spec and ask the user for an image.

Requirements:

- Static PNG with a real transparent background; one complete object; three-quarter view with weak perspective; tall objects shot near horizontal.
- Clear outline, feet, holes and joints; keep the intended colors and material style. No floor, shadow, background, collage or orthographic sheet.
- Thicken thin wires or build them separately; show wear in the texture, not as extra loose parts.
- No hints, key prompts, item names, status labels or glowing text (CLAUDE.md "In-Game Text").

Read the image yourself before generating. If the user asked to see it first, show it and wait.

## 2. Generate

```powershell
& $py "$skill/scripts/generate.py" preflight
& $py "$skill/scripts/generate.py" run --image '<reference.png>' --asset-id '<asset>' --output "$work/generation"
```

`run` submits once, waits (30 min default, `--timeout` to change) and collects. One asset takes a few minutes on the RTX 5070 Ti, which can exceed the tool timeout, so launch `run` with `run_in_background` and wait for the notification. On success `$work/generation/` holds `raw.glb`, `conditioning.png` and `result.json` with status `ART_REVIEW_REQUIRED` (technical checks passed; the art still needs review).

| Result | Action |
|---|---|
| exit 3 / `RUNNING`, `QUEUED` | Not done: `generate.py wait --output <job>` (in the background). **Never submit again** |
| `STOPPED` busy | The shared queue is busy; retry later. Never clear or interrupt other jobs |
| `SUBMISSION_UNKNOWN` | Outcome unknown: follow [reconcile](references/operations.md#unknown-submission). Do not resubmit |
| `attribute_issues` non-empty | Normal/tangent problems; `prepare_prop.py` rebuilds tangents, fix anything else on a copy |

The scripts refuse an existing output folder, so a rerun can never overwrite or double-submit. Step-by-step commands are in [operations](references/operations.md); graph settings in [profile](references/profile.md).

## 3. Review

```powershell
& $py "$skill/scripts/review.py" --source "$work/generation/raw.glb" --output "$work/reviews/raw"
```

This renders six views (front, side, back, oblique, top, underside) × textured and lit clay, 12 PNGs, plus `review.json` (initially `UNKNOWN`), in an isolated temporary Godot project. **Read every image.** Judge proportions, bending, missing parts, holes, ground support, materials and joints; use the clay views to tell geometry problems from texture problems.

- Small issues (orientation, size, origin) → fix in step 4.
- Structural errors (missing parts, fused or badly skewed geometry) → change the reference and regenerate. Decimation cannot straighten or add parts.
- Record checks and defects in `review.json` when useful. A technical PASS is not art approval.

## 4. Fit and decimate

Set a triangle budget from size, viewing distance and how many appear on screen; the ~50k faces from generation are not a game budget. Close-up small props usually land at 5k–13k. For single-mesh static props, one command applies rotation, size, origin and gltfpack decimation:

```powershell
& $py "$skill/scripts/prepare_prop.py" prepare --source "$work/generation/raw.glb" --output "$work/prepared" `
  --asset <asset> --size <X> <Y> <Z> --origin bottom-center --front +Z --rotation-y 0 --ratio 0.12
& $py "$skill/scripts/review.py" --source "$work/prepared/final.glb" --output "$work/reviews/final"
```

`--size` is in meters and scales each axis independently (compute uniform factors yourself to keep proportions). `--rotation-y` applies before scaling. gltfpack is found on PATH or in `.godot/gltfpack-1.3/bin/`. Read all 12 images again and confirm orientation, silhouette and textures survived. Details: [static props](references/static-props.md). When gltfpack cannot reach the budget or breaks textures: [decimation](references/decimation.md) (Blender remesh + bake).

Use `review.py --candidate <glb>` only for candidates in the **same coordinate frame** as the source (for example, different decimations of one raw). `final.glb` has been resized, so review it as its own `--source`, as above.

## 5. Integrate and deliver

- Graybox wrappers (`Visuals/Model` is a Node3D): integrate with `prepare_prop.py publish`, see [static props](references/static-props.md#publish-into-a-graybox-wrapper). Edit other scenes directly and never move collision to fit the look.
- Verify real size, lighting, collision, interaction and every use site in the game scene (see the `apocalypse-rv-3d-scenes` skill for in-context captures). Keep existing behavior.
- Runtime model → `assets/models/<asset>/`. Reference image, `editable/`, `model_parameters.json` and a short README (source, prompt ID, parameters, triangle count, known issues) → `art_source/<asset>/`.
- Jobs, candidates, review renders and logs under `.godot/art-work/` stay local and out of Git.
- Report the result, triangle count, what you looked at and what remains. Never call something verified that you did not inspect.

## Batches and tool tests

Generate one asset at a time: collect its `raw.glb` before submitting the next. After editing the scripts, run the offline tests (no service, no GPU):

```powershell
& $py "$skill/scripts/test_client.py"
& $py "$skill/scripts/test_prepare_prop.py"
```
