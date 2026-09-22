# RV procedural sounds

`rv/vehicle_audio.gd` synthesizes original mono 16-bit PCM at 22,050 Hz. The engine loop combines sinusoidal harmonics, a pulse envelope and deterministic noise. Short starter, shutdown, mechanical, blocked and completion cues use decaying envelopes. No recordings, samples or third-party sound libraries are used; these generated sounds may be distributed with this project under its source terms. No external attribution is required.

These are prototype sound designs, not recordings of a specific engine. Pitch follows throttle and road speed; it does not represent simulated RPM. Streams are generated once per process and shared across vehicles. Each vehicle owns one spatial loop and at most three simultaneous one-shot sources, all freed with the vehicle.
