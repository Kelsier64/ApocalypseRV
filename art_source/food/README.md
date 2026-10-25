# Ready-to-eat food sources

References were created with the built-in ImageGen tool; exact prompts are saved per item. Each folder preserves the original ComfyUI GLB, reference PNG and preparation metadata. Runtime models live in `assets/models/food/`; inventory icons are renders of those models.

| Asset | Final dimensions X/Y/Z (m) | Triangles | Nutrition |
| --- | --- | ---: | ---: |
| canned_food | 0.085 / 0.12 / 0.085 | 2,986 | 40 |
| energy_bar | 0.14 / 0.025 / 0.045 | 2,998 | 20 |
| beef_jerky | 0.12 / 0.18 / 0.035 | 2,998 | 30 |

Generation used the existing TRELLIS.2 single-image 1024 profile, seed 42, approximately 50k source triangles. The first canned-food job aborted inside ComfyUI model loading; its files remain in the ignored work folder. A separate local backend on port 8189 with `--disable-dynamic-vram` completed all three assets. No weights or global software were installed.

Preparation uses the repository ComfyUI skill's `prepare_prop.py`: center origin, front +Z, dimensions above, gltfpack 1.3, ratio 0.06, error 0.025. Canned food uses rotation-y 90; the others use 0. Preparation repaired one collapsed source tangent in the can. Metadata includes source/final hashes and texture hashes. The final meshes have finite positions/normals/tangents and no zero-length tangent attributes.

Six textured and clay views were inspected, including backs and bottoms, followed by an isolated gameplay review with the production player. These are approximate static visual meshes: welded topology checks report duplicate triangles/nonmanifold edges (can 132/267, bar 7/24, jerky 6/20). They are not precision or manifold production meshes. Gameplay uses independent simple cylinder/box colliders; no generated topology drives collision.

Rebuild a working copy with the sizes/rotation above, for example from the repository root:

```powershell
python .agents/skills/comfyui-image-to-3d/scripts/prepare_prop.py prepare --source art_source/food/canned_food/raw.glb --output .godot/art-work/food/canned-rebuild --asset canned_food --size 0.085 0.12 0.085 --origin center --front +Z --rotation-y 90 --gltfpack .godot/gltfpack-1.3/bin/gltfpack.exe --ratio 0.06 --error 0.025
```

The gltfpack executable is a local authoring dependency, not a game dependency. Use another installed gltfpack 1.3 path when rebuilding elsewhere.
