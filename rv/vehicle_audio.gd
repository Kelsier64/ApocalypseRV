extends Node3D
## Original deterministic PCM synthesis, shared immutable streams; see assets/audio/README.md.
static var streams: Dictionary = {}
var engine_player: AudioStreamPlayer3D
var tire_player: AudioStreamPlayer3D
var scrape_player: AudioStreamPlayer3D
var cues: Array[AudioStreamPlayer3D] = []
var cooldowns := {}
var cue_counts := {}
var was_running := false
var phase := 0.0
var engine_rest := Vector3.ZERO
@onready var rv: Chassis = get_parent()

static func synth(kind: String) -> AudioStreamWAV:
	if streams.has(kind): return streams[kind]
	var loop := kind in ["engine", "tire_slip", "hull_scrape"]
	var duration := 1.0 if loop else (0.6 if kind in ["start", "stop"] else 0.18)
	if kind == "ringing": duration = 1.25
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(duration * rate) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4501 + kind.hash()
	var freq := 46.0 if loop else (110.0 if kind == "start" else (65.0 if kind == "stop" else 280.0))
	if kind == "complete": freq = 760.0
	if kind == "blocked": freq = 170.0
	for i in range(data.size() / 2):
		var t := float(i) / rate
		var envelope := 1.0 if loop else minf(t / 0.006, 1.0) * pow(1.0 - t / duration, 2.0)
		var pulse := pow(0.5 + 0.5 * sin(TAU * 23.0 * t), 4.0)
		var signal_value := sin(TAU * freq * t) * 0.5 + sin(TAU * freq * 2.0 * t) * 0.18
		signal_value += rng.randf_range(-1.0, 1.0) * (0.12 + pulse * 0.12)
		if kind == "ringing": signal_value = sin(TAU * 2450.0 * t) * 0.32
		if kind == "tire_slip": signal_value = sin(TAU * 923.0 * t + sin(TAU * 17.0 * t) * 2.0) * 0.6
		if kind == "hull_scrape": signal_value = rng.randf_range(-0.65, 0.65) * (0.6 + pulse * 0.4) + 0.22 * sin(TAU * 213.0 * t)
		if kind == "crash": signal_value = 0.54 * sin(TAU * (95.0 * t - 120.0 * t * t)) + rng.randf_range(-0.6, 0.6)
		data.encode_s16(i * 2, int(clampf(signal_value * envelope * 0.55, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = data.size() / 2
	streams[kind] = stream
	return stream

func player() -> AudioStreamPlayer3D:
	var sound := AudioStreamPlayer3D.new()
	sound.unit_size = 4.0
	sound.max_distance = 55.0
	sound.position = Vector3(0, 0, -5.3)
	add_child(sound)
	return sound

func _ready() -> void:
	engine_player = player()
	engine_player.stream = synth("engine")
	tire_player = player()
	tire_player.position = Vector3.ZERO
	tire_player.stream = synth("tire_slip")
	scrape_player = player()
	scrape_player.position = Vector3.ZERO
	scrape_player.stream = synth("hull_scrape")
	for i in range(3): cues.append(player())
	# Chassis assigns its engine_bay reference later in its own ready callback.
	engine_rest = rv.get_node("EngineBay/EngineVisual").position

func play_cue(kind: String, at: Vector3 = Vector3.INF) -> void:
	var now := Time.get_ticks_msec()
	if now - cooldowns.get(kind, -1000) < 120: return
	cooldowns[kind] = now
	for cue in cues:
		if not cue.playing:
			cue.stream = synth(kind)
			cue.position = at if at.is_finite() else Vector3(0, 0, -5.3)
			cue.volume_db = -10.0
			cue.play()
			cue_counts[kind] = cue_counts.get(kind, 0) + 1
			return

func _process(delta: float) -> void:
	update_loop(tire_player, rv.drivetrain.slip_speed, 2.0)
	update_loop(scrape_player, rv.hull_scrape_speed, rv.handling_profile.shell_scrape_min_speed)
	var rpm := rv.engine_rpm()
	var running := rpm > 0.0
	if running and not engine_player.playing: engine_player.play()
	if not running:
		engine_player.stop()
		if was_running: play_cue("stop")
	was_running = running
	var rev_fraction := clampf(inverse_lerp(Chassis.ENGINE_IDLE_RPM, Chassis.ENGINE_MAX_RPM, rpm), 0.0, 1.0)
	engine_player.pitch_scale = lerpf(engine_player.pitch_scale, lerpf(0.85, 1.7, rev_fraction), minf(delta * 4.0, 1.0))
	engine_player.volume_db = -15.0 + rv.throttle_input * 4.0
	phase = fmod(phase + delta, 100.0)
	# Only the engine's visual assembly moves. Collision, seat and aim stay still.
	var offset := Vector3(sin(phase * 107), sin(phase * 131), 0) * 0.0012 * rv.vibration_strength if running else Vector3.ZERO
	rv.engine_bay.get_node("EngineVisual").position = engine_rest + offset

func update_loop(sound: AudioStreamPlayer3D, speed: float, threshold: float) -> void:
	if speed < threshold:
		if sound.playing: sound.stop()
		return
	if not sound.playing: sound.play()
	sound.volume_db = lerpf(-28.0, -11.0, clampf((speed - threshold) / 10.0, 0.0, 1.0))
	sound.pitch_scale = lerpf(0.85, 1.2, clampf(speed / 16.0, 0.0, 1.0))
