# RV procedural sounds

`rv/vehicle_audio.gd` synthesizes original mono 16-bit PCM at 22,050 Hz. The engine loop combines sinusoidal harmonics, a pulse envelope and deterministic noise. Short starter, shutdown, mechanical, blocked and completion cues use decaying envelopes. No recordings, samples or third-party sound libraries are used; these generated sounds may be distributed with this project under its source terms. No external attribution is required.

These are prototype sound designs, not recordings of a specific engine. Pitch follows throttle and road speed; it does not represent simulated RPM. Streams are generated once per process and shared across vehicles. Each vehicle owns one spatial loop and at most three simultaneous one-shot sources, all freed with the vehicle.

`rv/panel_damage_effect.gd` also synthesizes two original 22,050 Hz mono PCM cues for shell impact and destruction, combining decaying metallic harmonics with deterministic noise and staggered tearing transients. These use no external samples. Streams are shared. Each burst has one initial spatial source and at most three quieter, rate-limited landing cues (higher pitch for glass), freed on completion or with the burst. A vehicle has at most six bursts; impact bursts last 2.4 seconds and destruction debris lasts 7 seconds. Snapshot restoration and repairs are silent.

# Slender Speaker loudspeaker music

`slender_speaker/patrol.wav` is the giant's head loudspeaker: Beethoven's *Für Elise* (public domain) arranged as an electronic garbage-truck melody. It was synthesized in REAPER with Surge XT (a narrow 25% pulse wave through a mild horn-speaker saturation and EQ), with no recordings or samples. It may be distributed with this project under its source terms, and no attribution is required.

The file is mono 16-bit PCM at 44.1 kHz, 42.1875 s long, at 64 BPM. It is cut from the pickup to exactly one repeat later, so it loops seamlessly; the import loop mode is Forward. The giant plays it from spawn to removal, including capture and execution. Its audible distance follows the actor removal distance, `RoadSpawns.SAFE_DISTANCE`. The source project, notes and loop script are in `art_source/music/slender_speaker/`.
