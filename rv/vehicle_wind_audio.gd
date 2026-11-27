class_name RVWindAudio
extends Node3D
## The weather wind on the RV shell: a whistle that rises with the wind and
## with every missing hull panel, and loose panels that rattle when a gust hits.
## Both sit on the outside of the shell, so from the cabin they are muffled
## like other outside sound. The wind comes from the WorldClock of the world the
## RV is in; the driving airflow is VehicleAudio's own wind loop.

const WHISTLE: AudioStream = preload("res://assets/audio/rv/wind_whistle.wav")
const RATTLE: SoundEvent = preload("res://assets/audio/events/rv/panel_rattle.tres")
## Above the windscreen header, outside the cabin volume.
const WHISTLE_POSITION := Vector3(0.0, 2.85, -5.2)
const WHISTLE_DB := -20.0
## Wind speed in m/s at the RV where the whistle starts and reaches level 1.
const WHISTLE_SPEED := Vector2(9.0, 22.0)
## Each missing hull panel raises the whistle this much, up to WHISTLE_OPEN_DB.
const WHISTLE_PANEL_DB := 2.0
const WHISTLE_OPEN_DB := 8.0
## Rattles need this wind speed and grow most frequent at the second value,
## RATTLE_RATE per second at the top of a gust; below RATTLE_GUST there are none.
const RATTLE_SPEED := Vector2(10.0, 22.0)
const RATTLE_RATE := 0.6
const RATTLE_GUST := 0.55
## How far outside its panel a rattle plays, so it stays outside the cabin.
const RATTLE_OUTSET := 0.15
const CLOCK_RETRY_SECONDS := 1.0

var whistle: SoundLoop
var rattles := 0
## Playground override for the wind speed in m/s at the RV; negative reads the clock.
var speed_override := -1.0
var _clock: WorldClock
var _clock_retry := 0.0
## Only times rattles and picks panels; never touches gameplay randomness.
var _rng := RandomNumberGenerator.new()
@onready var audio: Node3D = get_parent()


func _ready() -> void:
	_rng.randomize()
	whistle = SoundLoop.new()
	whistle.name = "WindWhistle"
	whistle.stream = WHISTLE
	whistle.base_db = WHISTLE_DB
	audio.VEHICLE_RANGE.apply(whistle)
	whistle.position = WHISTLE_POSITION
	whistle.bus = audio.bus_for_local(WHISTLE_POSITION)
	add_child(whistle)


## Whistle level for a wind speed in m/s and a count of missing hull panels.
static func whistle_level(speed: float, missing: int) -> float:
	var level := smoothstep(WHISTLE_SPEED.x, WHISTLE_SPEED.y, speed)
	return level * db_to_linear(minf(WHISTLE_PANEL_DB * missing, WHISTLE_OPEN_DB))


## Rattles per second for a wind speed in m/s and a gust level 0 to 1.
static func rattle_rate(speed: float, gust: float) -> float:
	return RATTLE_RATE * smoothstep(RATTLE_SPEED.x, RATTLE_SPEED.y, speed) * smoothstep(RATTLE_GUST, 1.0, gust)


func _process(delta: float) -> void:
	var speed := speed_override
	var gust := 1.0
	var clock := _find_clock(delta)
	if clock != null:
		gust = clock.wind.gust(clock.elapsed_seconds)
		if speed < 0.0: speed = clock.wind_velocity.length()
	if speed < 0.0:
		whistle.set_level(0.0)
		return
	whistle.set_level(whistle_level(speed, missing_panels()), lerpf(0.95, 1.08, smoothstep(WHISTLE_SPEED.x, WHISTLE_SPEED.y * 1.2, speed)))
	if _rng.randf() < rattle_rate(speed, gust) * delta:
		play_rattle()


## Rattles one installed hull panel now.
func play_rattle() -> bool:
	var slots := audio.rv.get_node_or_null("StructureSlots") as RVStructureSlots
	if slots == null: return false
	var installed: Array[Dictionary] = []
	for slot in RVStructureSlots.layout():
		if slots.occupant(slot.id) != null: installed.append(slot)
	if installed.is_empty(): return false
	var slot: Dictionary = installed[_rng.randi_range(0, installed.size() - 1)]
	var pose: Transform3D = slot.pose
	var size: Vector3 = slot.size
	# A random point on the panel, pushed out along its face normal.
	var local := Vector3(_rng.randf_range(-0.4, 0.4) * size.x, _rng.randf_range(-0.4, 0.4) * size.y, 0.0)
	if slot.kind == "roof": local = Vector3(_rng.randf_range(-0.4, 0.4) * size.x, 0.0, _rng.randf_range(-0.4, 0.4) * size.z)
	var at: Vector3 = pose * (slot.center + local)
	var outward := Vector3.UP
	match slot.kind:
		"side": outward = Vector3(signf(pose.origin.x), 0.0, 0.0)
		"front", "rear": outward = Vector3(0.0, 0.0, signf(pose.origin.z))
	if not get_node("/root/Sfx").play(RATTLE, audio.rv, at + outward * RATTLE_OUTSET): return false
	rattles += 1
	return true


## Hull panels missing from their slots.
func missing_panels() -> int:
	var slots := audio.rv.get_node_or_null("StructureSlots") as RVStructureSlots
	if slots == null: return 0
	var missing := 0
	for slot in audio.HULL_SLOTS:
		if slots.occupant(slot) == null: missing += 1
	return missing


## The clock of the world this RV is in, through its ancestors only.
func _find_clock(delta: float) -> WorldClock:
	if is_instance_valid(_clock) and not _clock.is_queued_for_deletion(): return _clock
	_clock = null
	_clock_retry -= delta
	if _clock_retry > 0.0: return null
	_clock_retry = CLOCK_RETRY_SECONDS
	var ancestor: Node = audio.rv.get_parent()
	while ancestor != null and not ancestor is Viewport:
		var found := ancestor.get_node_or_null("WorldClock") as WorldClock
		if found != null and not found.is_queued_for_deletion():
			_clock = found
			break
		ancestor = ancestor.get_parent()
	return _clock
