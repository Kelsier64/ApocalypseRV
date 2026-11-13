# Generation profile

`generate.py` uses a [pinned graph](../assets/trellis-single-1024-50k.json) and replaces only the input image and output prefix. To tune parameters, use ComfyUI's native graph/API and save a new profile; do not edit this one.

| Stage | Setting |
|---|---|
| Models | TRELLIS.2 INT8, shape/texture VAE BF16, DINOv3 |
| Input | 1024, alpha, pad 1.0, seed 42 |
| SS | 12 steps, CFG 7.5, shift 5, rescale 0.7 |
| Shape | 20 steps, CFG 7.5, rescale 0.5 |
| Upsample | 12 steps, CFG 7.5 |
| Texture | 12 steps, CFG 1, 1024 texture |
| Remesh | resolution 192, smooth_iters 2, project_back 0 |
| Decimation | midpoint, target 50,000 faces (a generation setting, not a game budget) |

`preflight` confirms that the graph's node classes and all four weight files exist. Environment: ComfyUI 0.38.0 (`f1072eb`), RTX 5070 Ti 16 GB; run preflight first anywhere else.

TRELLIS.2 and Pixal3D use different conditioning, so swapping the checkpoint alone does not work. Mesh-input texturing is not implemented locally. Historical tool validation: [workflow validation](../../../../docs/validation/2026-10-06-image-to-3d-workflow.md).
