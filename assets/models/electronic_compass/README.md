# Electronic Compass

Self-authored hard-surface model: [enclosure.obj](enclosure.obj) is the original bevelled enclosure mesh. The [Item scene](../../../props/electronic_compass.tscn) assembles its rubber gasket, ribbed grips, corner guards, screws, bezel, indicator and buttons with native Godot meshes/materials. No generated or third-party model is used.

Metres; +Y up, front screen faces +Z. Overall collision envelope: 0.164 × 0.236 × 0.064 m, centred at the Item origin. The collision remains a separate BoxShape3D. Hand grips are authored on both lower sides; hold rotation and carry offset belong to the wrapper scene.

The physical LCD uses a per-instance 256 × 332 SubViewport texture and vector artwork in [electronic_compass_screen.gd](../../../props/electronic_compass_screen.gd). First-person mesh copies share that same live material. The [inventory PNG](../../inventory/electronic_compass.png) is a transparent render of the actual model.

Validation: rendered the real player holding and turning with the live screen, inspected the assembled model and its warehouse shelf placement. Automated coverage checks targeting, field isolation, worker lifetime, portable Item ownership and manufacturing. Full free-play travel was not performed.
