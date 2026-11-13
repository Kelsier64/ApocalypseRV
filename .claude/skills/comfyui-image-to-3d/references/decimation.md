# Decimation

Set the budget before reducing: size, viewing distance, on-screen count, silhouette and joints. If the model is already light, leave it and briefly say why a higher count is kept. Decimation cannot straighten skew or restore missing parts. Keep the raw; put candidates in `.godot/art-work/<asset>/<run>/`; commit only the runtime asset, sources and compact parameters.

## Pick a method

| Method | When |
|---|---|
| gltfpack 1.3 (`prepare_prop.py --ratio`) | Default. Keeps UVs, normals and texture bytes; fast |
| Blender remesh + bake | gltfpack cannot reach the budget, or folds or UV/texture breakup appear |
| Local rebuild / new reference | The structure itself is wrong; voxel remesh also softens thin plates, small holes and joints |

## gltfpack

[Official v1.3](https://github.com/zeux/meshoptimizer/releases/tag/v1.3) lives in the ignored `.godot/gltfpack-1.3/bin/gltfpack.exe`; it is not a game dependency. `prepare_prop.py` runs `-si <ratio> -se <error> -sp -sv -noq -kn -km`:

- `-si`: fraction of triangles to keep; `-se`: algorithmic error limit (not meters), default 0.025.
- `-sp -sv`: allow simplification across attribute seams and update vertex attributes; `-noq` disables quantization; `-kn -km` keep nodes and materials.
- The error limit can stop above the requested ratio. Read the real `triangles` in `model_parameters.json`; never claim the target was hit without checking. Raising `-se` or using `-sa` can wreck textures or delete all geometry.

A standalone candidate without `prepare_prop.py` (same frame as raw, so `review.py --candidate` can compare side by side):

```powershell
$gltfpack = '.godot/gltfpack-1.3/bin/gltfpack.exe'
New-Item -ItemType Directory -Force "$work/candidates" | Out-Null
& $gltfpack -i "$work/generation/raw.glb" -o "$work/candidates/r012.glb" -si 0.12 -se 0.025 -sp -sv -noq -kn -km
& $py "$skill/scripts/generate.py" inspect --glb "$work/candidates/r012.glb"
& $py "$skill/scripts/review.py" --source "$work/generation/raw.glb" --candidate "$work/candidates/r012.glb" --output "$work/reviews/r012"
```

Exit 0 or a smaller file does not mean it passed. Read the clay silhouettes, thin rods, holes and material views. When claiming textures are fully preserved, compare image SHAs (`prepare_prop.py` does this automatically).

## Blender remesh + bake

Blender 5.2 is on PATH; run it headless (`blender --background --python <script.py>`) with the script in the work folder. On a copy: voxel remesh → reduce → Smart UV → bake from the high-poly. Oil-barrel starting point: voxel 0.0035 m, Smart UV 66° / margin 0.012, Cycles selected-to-active, cage 0.015 m, ray 0.06 m, padding 12 px, three 1024 maps; color as DIFFUSE color-only, metal/roughness transferred through emission (G roughness, B metallic). Scale the numbers to the object; do not apply them blindly to thin plates or fine holes. Details: [oil barrel record](../../../../docs/validation/2026-10-06-oil-barrel-optimization.md).

## Measured results

| Object | Result |
|---|---|
| Most props (food, service fan, air compressor, scavenge loot) | gltfpack ratio 0.06–0.12, error 0.025 → about 5k–13k faces, texture bytes kept |
| Oil can 0.85 m | ratio 0.12, error 0.02 → 8,280 faces; error 0.01 stopped near 11k |
| Diesel generator | ratio 0.4 → 19,968 faces; 0.2 only reached 15,657 (error limit) |
| Oil barrel, 499,846 faces | Aggressive direct reduction folded and broke UVs; Blender remesh + bake gave about 3,000 faces close to the original look |

Results vary by model; treat them as starting points.
