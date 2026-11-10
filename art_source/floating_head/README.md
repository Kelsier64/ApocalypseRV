# Floating head — stage 1

Editable source: [floating_head_stage1.blend](floating_head_stage1.blend).

White Blender blockout of an 8 m floating human head, using the supplied expression reference for contracted brows, closed eyes and pursed lips. Awaiting user approval of the silhouette and expression before refinement or game integration.

Open the `FloatingHead_Stage1` scene. `FloatingHead` contains the model; `Review_Only` contains the ground, lighting, camera and 1.8 m scale mannequin. The source faces Blender -Y with Z up. The model is centered locally; its root is raised 7 m for the review, leaving the chin 3 m above the floor.

Select `Eyelids` and use the `Blink_Left` and `Blink_Right` shape keys independently: 0 is open, 1 is closed. The 120-frame review animation starts closed, opens by frame 44, briefly blinks at frame 72, and returns closed at frame 120. Frame 52 shows both eyes open. The eyeballs and all head surfaces use white clay material.

Stage 1 checks (2026-11-10): inspected Blender front, side and three-quarter views plus rendered open, intermediate and closed states. At shape-key values 0, 0.25, 0.5, 0.75 and 1, no eyelid vertices penetrated the 0.66 m eyeball spheres beyond a 0.001 m tolerance. This is a sampled vertex check, not continuous triangle collision validation. Model height is 8 m; current model has 107,070 vertices before optimization.

This is an expression and articulation blockout. Eyelid transitions, facial anatomy, ears and topology still need refinement. No Godot asset import, floating gameplay, AI, collision or world spawning is included or tested at this stage. Local review renders are ignored under `.godot/floating_head_stage1/`.
