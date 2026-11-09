# White apparition

Authored in Blender 5.2; exported as a 2.2 m, Y-up skinned glTF. Feet are at the origin and the face points along -Z. A single welded anatomical surface is bound to 17 bones, with continuous weighted deformation across shoulders, elbows, knees and spine. Bone names are consumed by `enemies/white_apparition/white_apparition_visual.gd`; preserve their names when replacing the mesh.

Faceless tapered anatomy, narrow joints, elongated fingers, no clothing or text. Cross-section lofts are welded and smoothed before skinning; there are no separate spherical joint pieces. Godot replaces the authoring material with a soft-edge pale shader and two delayed pose echoes. Three large motion phrases combine serpentine side folding, opposing pelvis/chest torsion and asymmetric arm sweeps with alternating knee lifts. Short freezes and sharp shudders interrupt the dance. The lowest sole determines vertical placement. Collision and encounter logic belong to the scene wrapper, not this asset.

Editable raw source and generation/review intermediates remain locally in the ignored `.godot/white_apparition/` directory (`source.blend`, `build_continuous.py`); only the runtime GLB is delivered. The model is authored for this project, with no external asset dependencies. The continuous-skin/dance revision was not replayed or visually rechecked, at the user's request.
