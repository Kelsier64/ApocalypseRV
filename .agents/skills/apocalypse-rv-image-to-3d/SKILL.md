---
name: apocalypse-rv-image-to-3d
description: Generate, fit, review, and integrate a textured ApocalypseRV prop using local ComfyUI TRELLIS.2. Use for static props with room for approximate geometry.
---

# ApocalypseRV Image to 3D

Reuse a suitable existing reference or use the Codex ImageGen workflow. Inspect the image before generation. Use a complete object on transparent PNG, a slight three-quarter view, and clear openings, silhouette, and materials. Follow the [project text rules](../../../AGENTS.md#project-rules).

Run from the repo root using Python with Pillow and numpy. See the [tool and delivery guide](../../../docs/guides/image-to-3d-workflow.md).

```powershell
$propPython = "$env:USERPROFILE/Apps/ComfyUI/pixal3d-runtime/.venv/Scripts/python.exe"
$propTools = 'scripts/comfyui-image-to-3d/scripts'
$propWork = '.godot/art-work/<asset>/run-01'
& $propPython "$propTools/generate.py" preflight
& $propPython "$propTools/generate.py" run --image '<reference.png>' --asset-id '<asset>' --output "$propWork/generation"
& $propPython "$propTools/review.py" --source "$propWork/generation/raw.glb" --output "$propWork/review-raw"
```

- Use a fresh directory for each run. The client finds the backend through the local `8000/health` endpoint. Poll long commands through their session. Resume existing jobs with `status` or `wait`. For an uncertain submission, find its prompt ID in queue/history and use `reconcile` before trying another submission.
- Review textured and clay renders. Check missing or fused details, proportions, materials, the back, and the underside. Repair small mesh issues or regenerate when the shape is wrong.
- Run `prepare_prop.py prepare --help` for fitting, orientation, and decimation. Set target dimensions in meters. The three size axes scale independently. Pick a ratio appropriate to the prop. Review the resulting GLB at its final size.
- Use `prepare_prop.py publish --help` for graybox wrappers with `Visuals/Model` and `apocalypse-rv-3d-scenes` for scene integration. Check lighting, scale, collision, and every use site. Deliver runtime assets under `assets/models/` and the necessary reference, editable source, and parameters under `art_source/`.
