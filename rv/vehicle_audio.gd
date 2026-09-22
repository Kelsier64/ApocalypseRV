extends Node3D
## Original deterministic PCM synthesis, shared immutable streams; see assets/audio/README.md.
static var streams: Dictionary = {}
var engine_player: AudioStreamPlayer3D
var cues: Array[AudioStreamPlayer3D] = []
var cooldowns := {}
var cue_counts := {}
var was_running := false
var phase := 0.0
var engine_rest := Vector3.ZERO
@onready var rv: Chassis = get_parent()

static func synth(kind: String) -> AudioStreamWAV:
	if streams.has(kind): return streams[kind]
	var loop := kind == "engine"
	var duration := 1.0 if loop else (0.6 if kind in ["start", "stop"] else 0.18)
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
	var running := rv.energy.engine_running and rv.has_working_engine() and rv.current_fuel > 0.0
	if running and not engine_player.playing: engine_player.play()
	if not running:
		engine_player.stop()
		if was_running: play_cue("stop")
	was_running = running
	engine_player.pitch_scale = lerpf(engine_player.pitch_scale, 0.85 + rv.throttle_input * 0.35 + clampf(rv.road_speed() / 25.0, 0, 1) * 0.5, minf(delta * 4.0, 1.0))
	engine_player.volume_db = -15.0 + rv.throttle_input * 4.0
	phase = fmod(phase + delta, 100.0)
	# Only the engine's visual assembly moves. Collision, seat and aim stay still.
	var offset := Vector3(sin(phase * 107), sin(phase * 131), 0) * 0.0012 * rv.vibration_strength if running else Vector3.ZERO
	rv.engine_bay.get_node("EngineVisual").position = engine_rest + offset
