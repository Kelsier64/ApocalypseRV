extends SceneTree
## Deterministic authoring source. Run explicitly; art_source is not game content.
func _init() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 742193
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = .035
	noise.fractal_octaves = 4
	var texture := noise.get_seamless_image(128, 128)
	var texture_error := texture.save_png("res://assets/effects/barrel_blast/turbulence.png")
	var audio_error := _make_boom().save_to_wav("res://assets/effects/barrel_blast/blast.wav")
	for variant in 3:
		var metal_error := _make_metal_landing(variant).save_to_wav(
			"res://assets/effects/barrel_blast/metal_land_%s.wav" % (variant + 1))
		if metal_error != OK:
			audio_error = metal_error
	print("BARREL_VFX_BAKE texture=%s audio=%s" % [texture_error, audio_error])
	quit(0 if texture_error == OK and audio_error == OK else 1)
static func _make_boom() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 3.0
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * DURATION))
	var rng := RandomNumberGenerator.new()
	rng.seed = 830431
	# Band-limited noise carries the blast weight without a ringing sine tone.
	var body_fast := 0.0
	var body_smooth := 0.0
	var body_low := 0.0
	var rumble_fast := 0.0
	var rumble_low := 0.0
	var roar_fast := 0.0
	var roar_low := 0.0
	var turbulence := 0.0
	var peak := 0.0
	var body_alpha := 1.0 - exp(-TAU * 240.0 / RATE)
	var body_low_alpha := 1.0 - exp(-TAU * 48.0 / RATE)
	var rumble_alpha := 1.0 - exp(-TAU * 95.0 / RATE)
	var rumble_low_alpha := 1.0 - exp(-TAU * 24.0 / RATE)
	var roar_alpha := 1.0 - exp(-TAU * 1400.0 / RATE)
	var roar_low_alpha := 1.0 - exp(-TAU * 180.0 / RATE)
	var turbulence_alpha := 1.0 - exp(-TAU * 8.0 / RATE)
	for i in samples.size():
		var t := float(i) / RATE
		var pressure_noise := rng.randf_range(-1.0, 1.0)
		var combustion_noise := rng.randf_range(-1.0, 1.0)
		body_fast = lerpf(body_fast, pressure_noise, body_alpha)
		body_smooth = lerpf(body_smooth, body_fast, body_alpha)
		body_low = lerpf(body_low, body_smooth, body_low_alpha)
		rumble_fast = lerpf(rumble_fast, pressure_noise, rumble_alpha)
		rumble_low = lerpf(rumble_low, rumble_fast, rumble_low_alpha)
		roar_fast = lerpf(roar_fast, combustion_noise, roar_alpha)
		roar_low = lerpf(roar_low, roar_fast, roar_low_alpha)
		turbulence = lerpf(turbulence, rng.randf_range(-1.0, 1.0), turbulence_alpha)
		var attack := 1.0 - exp(-t * 600.0)
		var crack := pressure_noise * 0.32 * exp(-t * 95.0)
		var body := (body_smooth - body_low) * 8.5 * exp(-t * 3.5)
		var rumble := (rumble_fast - rumble_low) * 4.2 * exp(-t * 1.25)
		var churn := clampf(1.0 + turbulence * 14.0, 0.45, 1.6)
		var roar := (roar_fast - roar_low) * 1.55 * churn
		roar *= (1.0 - exp(-t * 24.0)) * exp(-t * 1.05)
		# Fuel bursts break up the tail; their soft edges avoid a run of clicks.
		var fuel_bursts := 0.0
		for burst_time in [0.09, 0.19, 0.34, 0.57, 0.84]:
			var age: float = t - burst_time
			if age > 0.0:
				fuel_bursts += (1.0 - exp(-age * 180.0)) * exp(-age * 32.0)
		var breakup := (roar_fast - roar_low) * fuel_bursts * 0.55
		var fade := 1.0 - smoothstep(2.45, DURATION, t)
		var sample := (crack + body + rumble + roar + breakup) * attack * fade
		samples[i] = sample
		peak = maxf(peak, absf(sample))
	# Attenuate the entire mix once. No per-sample clipping or hard limiter.
	var gain := minf(1.0, 0.89 / maxf(peak, 0.001))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(samples[i] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

static func _make_metal_landing(variant: int) -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.42
	var samples := PackedFloat32Array()
	samples.resize(int(RATE * DURATION))
	var rng := RandomNumberGenerator.new()
	rng.seed = 218317 + variant * 6143
	var base_frequency := 360.0 + variant * 73.0
	var phases := PackedFloat32Array()
	var mode_ratios := [1.0, 1.47, 2.09, 2.71, 3.83, 5.17]
	for mode in mode_ratios.size():
		phases.append(rng.randf_range(0.0, TAU))
	var impact_low := 0.0
	var impact_floor := 0.0
	var scrape_low := 0.0
	var scrape_floor := 0.0
	var peak := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		impact_low = lerpf(impact_low, noise, 0.16)
		impact_floor = lerpf(impact_floor, impact_low, 0.025)
		scrape_low = lerpf(scrape_low, noise, 0.62)
		scrape_floor = lerpf(scrape_floor, scrape_low, 0.22)
		var impact := (impact_low - impact_floor) * 2.2 * exp(-t * 43.0)
		var metallic := 0.0
		for mode in mode_ratios.size():
			# Inharmonic sheet-metal modes, damped quickly rather than a bell ring.
			phases[mode] += TAU * base_frequency * mode_ratios[mode] / RATE
			metallic += sin(phases[mode]) * 0.075 * exp(-t * (19.0 + mode * 6.0))
		var scrape := (scrape_low - scrape_floor) * 0.2 * exp(-t * 16.0)
		var rebound := 0.0
		for contact_time in [0.035 + variant * 0.004, 0.076 + variant * 0.006]:
			var age: float = t - contact_time
			if age > 0.0:
				rebound += (1.0 - exp(-age * 1100.0)) * exp(-age * 170.0)
		var sample := (impact + metallic + scrape + noise * rebound * 0.12)
		sample *= (1.0 - exp(-t * 1800.0)) * (1.0 - smoothstep(0.28, DURATION, t))
		samples[i] = sample
		peak = maxf(peak, absf(sample))
	var gain := minf(1.0, 0.71 / maxf(peak, 0.001))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(samples[i] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

