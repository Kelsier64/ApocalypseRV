extends Node3D
## Recorded engine and door pilot, with the remaining prototype cues sharing PCM.
const ASSETS := "res://assets/audio/rv/"
const DOOR_OPEN := "res://assets/audio/events/rv/door_open.tres"
const DOOR_CLOSE := "res://assets/audio/events/rv/door_close.tres"
# Chassis-local volume bounded by the finished floor, side panels and ceiling.
const CABIN := AABB(Vector3(-1.82, 0.42, -5.90), Vector3(3.64, 2.16, 11.80))
const HULL_SLOTS := ["front", "rear", "left_0", "left_1", "left_2", "right_0",
	"right_1", "right_2", "roof_0", "roof_1", "roof_2"]
static var streams: Dictionary = {}
var engine_player: AudioStreamPlayer3D
var rev_player: AudioStreamPlayer3D
var tire_player: AudioStreamPlayer3D
var scrape_player: AudioStreamPlayer3D
var cues: Array[AudioStreamPlayer3D] = []
var cooldowns := {}
var cue_counts := {}
var was_running := false
var phase := 0.0
var engine_rest := Vector3.ZERO
var legacy_audio := false
var rev_blend := 0.0
@onready var rv: Chassis = get_parent()

static func synth(kind: String) -> AudioStreamWAV:
	if streams.has(kind): return streams[kind]
	var loop := kind in ["engine", "tire_slip", "hull_scrape", "ringing"]
	var duration := 1.0 if loop else (0.6 if kind in ["start", "stop"] else 0.18)
	if kind == "crash": duration = 0.32
	if kind == "inhale": duration = .78
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(duration * rate) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4501 + kind.hash()
	var freq := 46.0 if loop else (110.0 if kind == "start" else (65.0 if kind == "stop" else 280.0))
	if kind == "complete": freq = 760.0
	if kind == "blocked": freq = 170.0
	var breath_noise := 0.0
	for i in range(data.size() / 2):
		var t := float(i) / rate
		var envelope := 1.0 if loop else minf(t / 0.006, 1.0) * pow(1.0 - t / duration, 2.0)
		var pulse := pow(0.5 + 0.5 * sin(TAU * 23.0 * t), 4.0)
		var signal_value := sin(TAU * freq * t) * 0.5 + sin(TAU * freq * 2.0 * t) * 0.18
		signal_value += rng.randf_range(-1.0, 1.0) * (0.12 + pulse * 0.12)
		if kind == "ringing": signal_value = sin(TAU * 1886.0 * t) * 0.32 + sin(TAU * 2294.0 * t) * 0.065
		if kind == "inhale":
			breath_noise = lerpf(breath_noise, rng.randf_range(-1, 1), .28)
			envelope = pow(sin(PI * t / duration), .8)
			signal_value = breath_noise * (1.0 + .3 * sin(TAU * (620.0 - 180.0 * t) * t))
		if kind == "tire_slip": signal_value = sin(TAU * 923.0 * t + sin(TAU * 17.0 * t) * 2.0) * 0.6
		if kind == "hull_scrape": signal_value = rng.randf_range(-0.65, 0.65) * (0.6 + pulse * 0.4) + 0.22 * sin(TAU * 213.0 * t)
		if kind == "crash":
			var thump := 0.75 * sin(TAU * (84.0 * t - 83.0 * t * t)) * exp(-t * 11.0)
			var metal := (0.23 * sin(TAU * 613.0 * t) + 0.19 * sin(TAU * 967.0 * t)) * exp(-t * 14.0)
			var rattle := rng.randf_range(-0.5, 0.5) * exp(-t * 18.0)
			var rebound := maxf(0.0, 1.0 - absf(t - 0.092) * 43.0)
			signal_value = thump + metal + rattle * (1.0 + 2.0 * rebound)
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
	sound.bus = &"Effects"
	sound.unit_size = 4.0
	sound.max_distance = 55.0
	sound.position = Vector3(0, 0, -5.3)
	add_child(sound)
	return sound

func _ready() -> void:
	engine_player = player()
	engine_player.bus = &"Cabin"
	engine_player.stream = load(ASSETS + "engine_idle.wav")
	rev_player = player()
	rev_player.bus = &"Cabin"
	rev_player.stream = load(ASSETS + "engine_rev.wav")
	tire_player = player()
	tire_player.position = Vector3.ZERO
	tire_player.stream = synth("tire_slip")
	scrape_player = player()
	scrape_player.position = Vector3.ZERO
	scrape_player.stream = synth("hull_scrape")
	for i in range(3): cues.append(player())
	# Chassis assigns its engine_bay reference later in its own ready callback.
	engine_rest = rv.get_node("EngineBay/EngineVisual").position

func set_legacy_audio(enabled: bool) -> void:
	if legacy_audio == enabled: return
	legacy_audio = enabled
	engine_player.stream = synth("engine") if enabled else load(ASSETS + "engine_idle.wav")
	rev_player.stop()
	rev_blend = 0.0

func play_door_motion(door: Node3D, latch: Vector3, opening: bool, started: bool) -> void:
	if legacy_audio:
		play_cue("mechanical", rv.to_local(door.to_global(latch)))
	elif opening and started:
		get_node("/root/Sfx").play(load(DOOR_OPEN), door, latch)
	elif not opening and not started:
		get_node("/root/Sfx").play(load(DOOR_CLOSE), door, latch)

func exterior_audio_cover(listener_position: Vector3) -> float:
	if legacy_audio or not CABIN.has_point(rv.to_local(listener_position)): return 0.0
	var slots := rv.get_node_or_null("StructureSlots") as RVStructureSlots
	if slots == null: return 0.0
	var opening := 0.0
	for slot in HULL_SLOTS:
		var panel := slots.occupant(slot)
		if panel == null:
			opening = 1.0
			break
		if panel is RVDoor:
			for angle: float in panel.angles:
				opening = maxf(opening, smoothstep(0.0, deg_to_rad(65.0), absf(angle)))
	return lerpf(1.0, 0.45, opening)

func play_cue(kind: String, at: Vector3 = Vector3.INF, strength := 0.5) -> void:
	var now := Time.get_ticks_msec()
	if now - cooldowns.get(kind, -1000) < 120: return
	cooldowns[kind] = now
	for cue in cues:
		if not cue.playing:
			cue.stream = _cue_stream(kind)
			cue.position = at if at.is_finite() else Vector3(0, 0, -5.3)
			cue.volume_db = lerpf(-20.0, -4.0, strength) if kind == "crash" else -10.0
			cue.pitch_scale = lerpf(1.16, 0.82, strength) if kind == "crash" else 1.0
			cue.play()
			cue_counts[kind] = cue_counts.get(kind, 0) + 1
			return

func _cue_stream(kind: String) -> AudioStream:
	if not legacy_audio:
		match kind:
			"start", "stop": return load(ASSETS + "engine_" + kind + ".wav")
	return synth(kind)

func _process(delta: float) -> void:
	update_loop(tire_player, rv.drivetrain.slip_speed, 2.0)
	update_loop(scrape_player, rv.hull_scrape_speed, rv.handling_profile.shell_scrape_min_speed)
	var rpm := rv.engine_rpm()
	var running := rpm > 0.0
	_update_engine(delta, rpm)
	if not running and was_running: play_cue("stop")
	was_running = running
	phase = fmod(phase + delta, 100.0)
	# Only the engine's visual assembly moves. Collision, seat and aim stay still.
	var offset := Vector3(sin(phase * 107), sin(phase * 131), 0) * 0.0012 * rv.vibration_strength if running else Vector3.ZERO
	rv.engine_bay.get_node("EngineVisual").position = engine_rest + offset

func _update_engine(delta: float, rpm: float) -> void:
	if rpm <= 0.0:
		if engine_player.playing: engine_player.stop()
		if rev_player.playing: rev_player.stop()
		rev_blend = 0.0
		return
	var fraction := clampf(inverse_lerp(Chassis.ENGINE_IDLE_RPM, Chassis.ENGINE_MAX_RPM, rpm), 0.0, 1.0)
	if legacy_audio:
		engine_player.pitch_scale = lerpf(engine_player.pitch_scale, lerpf(0.85, 1.7, fraction), minf(delta * 4.0, 1.0))
		engine_player.volume_db = -15.0 + rv.throttle_input * 4.0
	else:
		rev_blend = move_toward(rev_blend, smoothstep(0.12, 0.72, fraction), delta * 4.0)
		engine_player.pitch_scale = lerpf(1.0, 1.24, fraction)
		rev_player.pitch_scale = lerpf(0.86, 1.15, fraction)
		engine_player.volume_db = -9.0 + linear_to_db(maxf(0.0001, sqrt(1.0 - rev_blend)))
		rev_player.volume_db = -8.0 + linear_to_db(maxf(0.0001, sqrt(rev_blend)))
		if rev_blend > 0.0 and not rev_player.playing: rev_player.play()
		if rev_blend <= 0.0 and rev_player.playing: rev_player.stop()
	if not engine_player.playing: engine_player.play()

func update_loop(sound: AudioStreamPlayer3D, speed: float, threshold: float) -> void:
	if speed < threshold:
		if sound.playing: sound.stop()
		return
	if not sound.playing: sound.play()
	sound.volume_db = lerpf(-28.0, -11.0, clampf((speed - threshold) / 10.0, 0.0, 1.0))
	sound.pitch_scale = lerpf(0.85, 1.2, clampf(speed / 16.0, 0.0, 1.0))
