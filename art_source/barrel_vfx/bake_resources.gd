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
	print("BARREL_VFX_BAKE texture=%s audio=%s" % [texture_error, audio_error])
	quit(0 if texture_error == OK and audio_error == OK else 1)
static func _make_boom() -> AudioStreamWAV:
	const RATE := 22050
	var data := PackedByteArray()
	data.resize(int(RATE * 1.65) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 830431
	var low := 0.0
	var rumble := 0.0
	for i in data.size() / 2:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1, 1)
		low = lerpf(low, noise, .22)
		rumble = lerpf(rumble, noise, .035)
		var crack := noise * exp(-t * 65.0) * .6
		var body := (low * 1.6 + sin(TAU * (68.0 * t - 17.0 * t * t)) * .5) * exp(-t * 7.0)
		var tail := rumble * 2.1 * exp(-t * 3.8)
		var metallic := sin(t * 2340.0) * sin(t * 1730.0) * exp(-t * 9.0) * .06
		var sample := clampf((crack + body + tail + metallic) * minf(1, t * 1400), -1, 1)
		data.encode_s16(i * 2, int(sample * 28500))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

