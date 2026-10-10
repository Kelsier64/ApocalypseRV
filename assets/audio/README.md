# RV procedural sounds

`rv/vehicle_audio.gd` synthesizes original mono 16-bit PCM at 22,050 Hz. The engine loop combines sinusoidal harmonics, a pulse envelope and deterministic noise. Short starter, shutdown, mechanical, blocked and completion cues use decaying envelopes. No recordings, samples or third-party sound libraries are used; these generated sounds may be distributed with this project under its source terms. No external attribution is required.

These are prototype sound designs, not recordings of a specific engine. Pitch follows throttle and road speed; it does not represent simulated RPM. Streams are generated once per process and shared across vehicles. Each vehicle owns one spatial loop and at most three simultaneous one-shot sources, all freed with the vehicle.

`rv/panel_damage_effect.gd` also synthesizes two original 22,050 Hz mono PCM cues for shell impact and destruction, combining decaying metallic harmonics with deterministic noise and staggered tearing transients. These use no external samples. Streams are shared. Each burst has one initial spatial source and at most three quieter, rate-limited landing cues (higher pitch for glass), freed on completion or with the burst. A vehicle has at most six bursts; impact bursts last 2.4 seconds and destruction debris lasts 7 seconds. Snapshot restoration and repairs are silent.
