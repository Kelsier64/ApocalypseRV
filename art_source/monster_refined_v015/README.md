# Raker v015 — small head lift

Source [monster_refined_v015.blend](monster_refined_v015.blend), scene `MONSTER_REFINED_V015`. Uses the v014 hunched spine, neck and inward hands, with only an additional 18-degree lift of the head in idle / walk / chase / sprint. This is a small chin lift, not an upright head or an extended neck. Neutral mesh remains 2.18 m with unchanged geometry, weights and textures.

Rebuild with [author.py](author.py), [audit.py](audit.py) and [finish.py](finish.py). Export [raker_refined_v015.glb](raker_refined_v015.glb) to [production](../../assets/models/raker/raker.glb). Previous scenes/actions remain preserved; only current scene NLA tracks are exported.

Final [validation.json](validation.json): 23 clips, 748 sampled frames, no nonadjacent triangle intersections (shared vertices excluded). No terrain foot IK or exhaustive cross-clip blending audit.

[Front three-quarter](walk.png) / [side](walk_side.png). Gameplay turn handling is implemented separately in Raker, not baked root motion.
