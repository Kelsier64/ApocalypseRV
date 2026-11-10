# Floating head — stage 1

Editable source: [floating_head_stage1.blend](floating_head_stage1.blend).

White Blender blockout of an 8 m floating human head, using the supplied expression reference for contracted brows, closed eyes and pursed lips. Awaiting user approval of the silhouette and expression before refinement or game integration.

Current revision (2026-11-10): replaced the egg-shaped silhouette with a fuller rounded cranium, defined temples and cheekbones, wider mandibular angles and a broader forward chin with a rounded underside. Softened the nasal tip and filled the hollow above the pursed lips. Applied the same deformation to the skin, ears, eyeballs and both eyelid shape keys; an eyelid boundary-normal modifier blends shading into the skin.

Open the `FloatingHead_Stage1` scene. `FloatingHead` contains the model; `Review_Only` contains the ground, lighting, camera and 1.8 m scale mannequin. The source faces Blender -Y with Z up. The model is centered locally; its root is raised 7 m for the review, leaving the chin 3 m above the floor.

Select `Eyelids` and use the `Blink_Left` and `Blink_Right` shape keys independently: 0 is open, 1 is closed. The 120-frame review animation starts closed, opens by frame 44, briefly blinks at frame 72, and returns closed at frame 120. Frame 52 shows both eyes open. The eyeballs and all head surfaces use white clay material.

Initial revision checks (2026-11-10, historical): inspected Blender front, side and three-quarter views plus rendered open, intermediate and closed states. At shape-key values 0, 0.25, 0.5, 0.75 and 1, no eyelid vertices penetrated the original 0.66 m eyeball spheres beyond a 0.001 m tolerance.

Current revision checks: inspected the revised front, side and three-quarter silhouette and rendered open/closed states. Rechecked eyelid vertices at 0, 0.25, 0.5, 0.75 and 1 against the actual deformed eyeball meshes with a nearest-surface/normal test: no interior vertices beyond 0.001 m. The skin has zero boundary or non-manifold edges. These are sampled geometry checks, not continuous triangle collision validation. Model height remains 8 m with 107,070 vertices before optimization.

This is an expression and articulation blockout. Eyelid transitions, facial anatomy, ears and topology still need refinement. No Godot asset import, floating gameplay, AI, collision or world spawning is included or tested at this stage. Local review renders are ignored under `.godot/floating_head_stage1/`.
