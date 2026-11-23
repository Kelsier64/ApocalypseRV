extends Node3D
## Simulated inline-six exhaust, recorded one-shots and contact loops for the RV;
## the weather wind on the shell is RVWindAudio, a child.
const DOOR_OPEN := "res://assets/audio/events/rv/door_open.tres"
const DOOR_CLOSE := "res://assets/audio/events/rv/door_close.tres"
const GEAR_SHIFT := "res://assets/audio/events/rv/gear_shift.tres"
# Light, medium and heavy collision recordings, chosen by impact strength.
const CRASH_SOUNDS: Array[SoundEvent] = [
	preload("res://assets/audio/events/rv/crash_light.tres"),
	preload("res://assets/audio/events/rv/crash_medium.tres"),
	preload("res://assets/audio/events/rv/crash_heavy.tres"),
]
# Each tier plays this much quieter at the bottom of its strength band.
const CRASH_SPAN_DB := 6.0
const VEHICLE_RANGE: SoundAttenuation = preload("res://assets/audio/attenuation/vehicle.tres")
# Slip and scrape loops reach this volume once they run 10 m/s past their threshold.
const CONTACT_DB := -11.0
const CONTACT_RANGE_DB := 17.0
const ENGINE_POSITION := Vector3(0, 0, -5.3)
# Engine masking is full in the cabin and within MASK_NEAR of the bay, gone by MASK_REACH.
const MASK_NEAR := 4.0
const MASK_REACH := 20.0
# Audio-only shift: load drops out and the firing rate glides to the new gear.
const SHIFT_SECONDS := 0.3
# Per-second response of the firing rate during a shift, a time constant near 0.3 s.
const SHIFT_PITCH_RESPONSE := 3.5
# Rolling loops per RVTireModel.Surface. Asphalt and rough come from an in-cab recording.
const ROAD_LOOPS := [
	"res://assets/audio/rv/road_asphalt.wav",
	"res://assets/audio/rv/road_rough.wav",
	"res://assets/audio/rv/road_gravel.wav",
]
const WIND_LOOP := "res://assets/audio/rv/wind.wav"
# Speeds in m/s at which the road and wind loops play at their base level.
const ROAD_REFERENCE_SPEED := 20.0
const WIND_REFERENCE_SPEED := 28.0
const ROAD_DB := -6.0
const WIND_DB := -13.0
const SURFACE_FADE_SECONDS := 0.35
# Chassis-local volume bounded by the finished floor, side panels and ceiling.
const CABIN := AABB(Vector3(-1.82, 0.42, -5.90), Vector3(3.64, 2.16, 11.80))
const HULL_SLOTS := ["front", "rear", "left_0", "left_1", "left_2", "right_0",
	"right_1", "right_2", "roof_0", "roof_1", "roof_2"]
var engine_cue: AudioStreamPlayer3D
var engine_start_sound: AudioStream
var engine_stop_sound: AudioStream
var tire_player: SoundLoop
var scrape_player: SoundLoop
var cue_counts := {}
var was_running := false
var phase := 0.0
var engine_rest := Vector3.ZERO
var engine_presence := 0.0
var engine_speed := 0.0
var engine_load := 0.0
var engine_player: AudioStreamPlayer3D
var engine_stream := BusEngineStream.new()
var shift_left := 0.0
var road_layers: Array[SoundLoop] = []
var road_weights := PackedFloat32Array([1.0, 0.0, 0.0])
var road_surface := RVTireModel.Surface.ASPHALT
var wind_player: SoundLoop
## Weather wind on the shell: whistle and panel rattles.
var weather_wind: RVWindAudio
var _surface_check := 0.0
# Loop start offsets only; never touches gameplay randomness.
@onready var rv: Chassis = get_parent()

func player() -> AudioStreamPlayer3D:
	return _place(AudioStreamPlayer3D.new(), ENGINE_POSITION)

func _place(sound: AudioStreamPlayer3D, local_position: Vector3) -> AudioStreamPlayer3D:
	VEHICLE_RANGE.apply(sound)
	sound.position = local_position
	sound.bus = bus_for_local(local_position)
	add_child(sound)
	return sound

func _loop(stream: AudioStream, local_position: Vector3, base_db: float) -> SoundLoop:
	var sound := SoundLoop.new()
	sound.stream = stream
	sound.base_db = base_db
	_place(sound, local_position)
	return sound

func _ready() -> void:
	engine_player = player()
	engine_player.name = "BusEngine"
	engine_player.stream = engine_stream
	engine_cue = player()
	# The engine has its own bus, so its masking of other outside sound skips it.
	engine_player.bus = &"Engine"
	engine_cue.bus = &"Engine"
	engine_start_sound = load("res://assets/audio/rv/engine_start.wav")
	engine_stop_sound = load("res://assets/audio/rv/engine_stop.wav")
	tire_player = _loop(load("res://assets/audio/rv/tire_slip.wav"), Vector3.ZERO, CONTACT_DB)
	scrape_player = _loop(load("res://assets/audio/rv/hull_scrape.wav"), Vector3.ZERO, CONTACT_DB)
	for path in ROAD_LOOPS:
		road_layers.append(_cabin_loop(path, ROAD_DB))
	wind_player = _cabin_loop(WIND_LOOP, WIND_DB)
	weather_wind = RVWindAudio.new()
	weather_wind.name = "WeatherWind"
	add_child(weather_wind)
	# Chassis assigns its engine_bay reference later in its own ready callback.
	engine_rest = rv.get_node("EngineBay/EngineVisual").position

## The rolling and wind loops are in-cab recordings, so they play on the cabin mix.
func _cabin_loop(path: String, base_db: float) -> SoundLoop:
	var sound := _loop(load(path), Vector3(0, 0.8, 0), base_db)
	sound.bus = &"Cabin"
	sound.unit_size = 6.0
	return sound

func play_door_motion(door: Node3D, latch: Vector3, opening: bool, started: bool) -> void:
	if opening and started:
		get_node("/root/Sfx").play(load(DOOR_OPEN), door, latch)
	elif not opening and not started:
		get_node("/root/Sfx").play(load(DOOR_CLOSE), door, latch)

## True when a world position lies inside the finished cabin. The roof counts as outside.
func contains_cabin_point(world_position: Vector3) -> bool:
	return CABIN.has_point(rv.to_local(world_position))

## How strongly the running engine masks other outside sound for a listener, 0 to
## 1: grows with revs and fades with distance from the bay outside the cabin.
func engine_masking(listener_position: Vector3) -> float:
	if engine_presence <= 0.0: return 0.0
	var near := 1.0
	if not contains_cabin_point(listener_position):
		near = 1.0 - smoothstep(MASK_NEAR, MASK_REACH, rv.to_global(ENGINE_POSITION).distance_to(listener_position))
	return engine_presence * engine_speed * near

## Mix bus for a sound at a chassis-local position.
static func bus_for_local(local_position: Vector3) -> StringName:
	return &"Cabin" if CABIN.has_point(local_position) else &"Exterior"

## How strongly the shell separates cabin and exterior sound: 1 sealed, lower
## with open doors or missing panels.
func shell_cover() -> float:
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
	if kind in ["start", "stop"]:
		engine_cue.stream = engine_start_sound if kind == "start" else engine_stop_sound
		engine_cue.volume_db = -4.0
		engine_cue.play()
		cue_counts[kind] = cue_counts.get(kind, 0) + 1
		return
	if kind == "gear":
		get_node("/root/Sfx").play(load(GEAR_SHIFT), rv, at if at.is_finite() else Vector3.ZERO)
		if rv.engine_rpm() > 0.0: shift_left = SHIFT_SECONDS
		cue_counts[kind] = cue_counts.get(kind, 0) + 1
		return
	if kind == "crash":
		# Strength picks the tier; within a tier the weaker hits play quieter.
		var scaled := clampf(strength, 0.0, 1.0) * CRASH_SOUNDS.size()
		var tier := mini(int(scaled), CRASH_SOUNDS.size() - 1)
		var gain_db := CRASH_SPAN_DB * (minf(scaled - tier, 1.0) - 1.0)
		if get_node("/root/Sfx").play(CRASH_SOUNDS[tier], rv, at if at.is_finite() else ENGINE_POSITION, gain_db):
			cue_counts[kind] = cue_counts.get(kind, 0) + 1

## Recorded one-shot from a chassis-local point, the engine bay when none is given.
func play_event(event: SoundEvent, at: Vector3 = Vector3.INF) -> void:
	get_node("/root/Sfx").play(event, rv, at if at.is_finite() else ENGINE_POSITION)

func _process(delta: float) -> void:
	_update_contact(tire_player, rv.drivetrain.slip_speed, 2.0)
	_update_contact(scrape_player, rv.hull_scrape_speed, rv.handling_profile.shell_scrape_min_speed)
	var rpm := rv.engine_rpm()
	var running := rpm > 0.0
	if not running and was_running: play_cue("stop")
	_update_engine(delta, rpm)
	_update_road(delta)
	was_running = running
	phase = fmod(phase + delta, 100.0)
	# Only the engine's visual assembly moves. Collision, seat and aim stay still.
	var offset := Vector3(sin(phase * 107), sin(phase * 131), 0) * 0.0012 * rv.vibration_strength if running else Vector3.ZERO
	rv.engine_bay.get_node("EngineVisual").position = engine_rest + offset

func _update_engine(delta: float, rpm: float) -> void:
	var running := rpm > 0.0
	var cranking := engine_cue.playing and engine_cue.stream == engine_start_sound \
		and engine_cue.get_playback_position() < engine_start_sound.get_length() - 0.28
	engine_presence = move_toward(engine_presence, 1.0 if running and not cranking else 0.0, delta * (5.0 if running else 12.0))
	shift_left = maxf(0.0, shift_left - delta)
	if running:
		var fraction := clampf(inverse_lerp(Chassis.ENGINE_IDLE_RPM, Chassis.ENGINE_MAX_RPM, rpm), 0.0, 1.0)
		# Revs fall with some inertia, and glide more slowly across a gear change.
		var pitch_response := SHIFT_PITCH_RESPONSE if shift_left > 0.0 else (12.0 if fraction > engine_speed else 6.5)
		engine_speed = lerpf(engine_speed, fraction, 1.0 - exp(-delta * pitch_response))
		var load_target := rv.engine_pedal() * _shift_load_scale()
		engine_load = lerpf(engine_load, load_target, 1.0 - exp(-delta * 13.0))
	elif engine_presence == 0.0:
		engine_speed = 0.0
		engine_load = 0.0
	_update_engine_player()

## Load fades out over the first half of a shift and back in over the second.
func _shift_load_scale() -> float:
	if shift_left <= 0.0: return 1.0
	return absf(1.0 - 2.0 * (1.0 - shift_left / SHIFT_SECONDS))

## Map the drivetrain range onto the auditioned bus model's idle and redline.
func sound_rpm() -> float:
	return lerpf(BusEngineStream.RPMS.front(), BusEngineStream.RPMS.back(), engine_speed)

func _update_engine_player() -> void:
	if engine_presence <= 0.0:
		if engine_player.playing: engine_player.stop()
		return
	var rpm := sound_rpm()
	engine_stream.set_operating_point(rpm, engine_load)
	engine_player.pitch_scale = BusEngineStream.pitch_for(rpm)
	# The bay is outside the shell. Keep the same small boost for the driver.
	engine_player.volume_db = 3.0 + linear_to_db(engine_presence)
	if not engine_player.playing: engine_player.play()

func _update_road(delta: float) -> void:
	var speed := Vector2(rv.linear_velocity.x, rv.linear_velocity.z).length()
	_surface_check -= delta
	if _surface_check <= 0.0:
		_surface_check = 0.1
		road_surface = RVTireModel.surface(rv.terrain_field(), rv.global_position)
	var contact := 0.0
	for wheel: VehicleWheel3D in rv.installed_wheels:
		if wheel != null and wheel.is_in_contact(): contact += 1.0 / rv.installed_wheels.size()
	var road := road_level(speed) * contact
	var pitch := clampf(lerpf(0.8, 1.0, speed / ROAD_REFERENCE_SPEED), 0.8, 1.15)
	for i in range(road_layers.size()):
		road_weights[i] = move_toward(road_weights[i], 1.0 if i == road_surface else 0.0, delta / SURFACE_FADE_SECONDS)
		road_layers[i].set_level(road * road_weights[i], pitch)
	wind_player.set_level(wind_level(speed), clampf(lerpf(0.9, 1.05, speed / WIND_REFERENCE_SPEED), 0.9, 1.1))

## Linear road loop gain for a horizontal speed in m/s.
static func road_level(speed: float) -> float:
	return pow(clampf(speed / ROAD_REFERENCE_SPEED, 0.0, 1.5), 1.2)

## Wind grows much faster than rolling noise and only matters at speed.
static func wind_level(speed: float) -> float:
	return pow(clampf(speed / WIND_REFERENCE_SPEED, 0.0, 1.4), 2.5)

## Slip and scrape loops start at their threshold speed and grow over the next 10 m/s.
func _update_contact(sound: SoundLoop, speed: float, threshold: float) -> void:
	if speed < threshold:
		sound.set_level(0.0)
		return
	var excess := clampf((speed - threshold) / 10.0, 0.0, 1.0)
	sound.set_level(db_to_linear(CONTACT_RANGE_DB * (excess - 1.0)), lerpf(0.85, 1.2, clampf(speed / 16.0, 0.0, 1.0)))
