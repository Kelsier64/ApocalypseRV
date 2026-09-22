# Raker v014 — inward hands, hunched back / neck

Source: [monster_refined_v014.blend](monster_refined_v014.blend), scene `MONSTER_REFINED_V014`. Preserves all previous revisions. Geometry and neutral 2.18 m height remain unchanged from v012; the bowed standing idle is visibly shorter than the neutral mesh.

The idle, walk, chase and sprint clips now share a curved upper back and forward neck. Arm FK keeps elbows close to the ribs; hand twist faces the palms inward. This replaces the previous IK elbow flare and fixed outward wrist orientation. Slight arm clearance prevents thumbs intersecting the shins.

Run [author.py](author.py), [audit.py](audit.py), then [finish.py](finish.py) through Blender MCP with a previous source blend loaded. Export only the v014 scene's selected rig / mesh; NLA names stay canonical and the exported objects retain `Raker_Rig` / `Raker_Mesh`. Older actions are preserved. Copy [raker_refined_v014.glb](raker_refined_v014.glb) to the [production asset](../../assets/models/raker/raker.glb).

All 23 clips / 748 baked frames pass the nonadjacent triangle intersection audit: [validation.json](validation.json). Shared-vertex pairs are excluded. No terrain foot IK; arbitrary animation blends are not exhaustively audited.

Views: [walk](walk.png), [walk side](walk_side.png), [run](chase.png), [sprint](sprint.png), [sprint side](sprint_side.png).

Runtime now uses distance hysteresis for pursuit speed, smoothed animation speed, separate walk/run/sprint thresholds and matching normalized foot phase when changing gait. The new [vehicle playground](../../tests/raker_vehicle_playground.tscn) offers actual wheel-driven pursuit and isolated animation preview.
