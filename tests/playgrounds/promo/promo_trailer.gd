extends "res://tests/playgrounds/promo/promo_outdoor.gd"
## Trailer takes (T group). Each shot's `timeline` drives the RV, the cab speaker, the
## weather and, in unattended takes, the driver's view. F3 starts the timeline.

const TIMELINE := preload("res://tests/playgrounds/promo/promo_timeline.gd")
const BROADCAST := preload("res://tests/playgrounds/promo/promo_broadcast.gd")
const EYELIDS := preload("res://player/san_eyelids.gdshader")
const STEERING_GAIN := 2.4
## Throttle or brake per km/h of speed error.
const SPEED_GAIN := 0.12

var timeline := TIMELINE.new()
var broadcast := BROADCAST.new()
var cruise: Dictionary = {}
var unattended := false
var _look := {}
var _eyes := {}
var _weather := {}
var _lids := ShaderMaterial.new()
var _lid_rect: ColorRect

func placement(world) -> Transform3D:
	return _road_mark(world.field, float(world.shot.distance), float(world.shot.get("lateral", 0.0)))

func prepare(world) -> bool:
	if not await super.prepare(world): return false
	timeline.load_from(world.shot.timeline)
	if not broadcast.attach(world.rv, int(world.shot.get("radio_level", 1))): return false
	_build_eyelids(world, 1.0 if world.shot.get("eyes_closed", false) else 0.0)
	# The engine idles behind the handbrake until the timeline starts.
	return world.rv.set_engine_running(true)

func trigger(world) -> bool:
	if timeline.running or triggered: return false
	world.rv.set_handbrake(false)
	timeline.start()
	triggered = true
	return true

func tick(world, delta: float) -> void:
	super.tick(world, delta)
	broadcast.tick()
	if not timeline.advance(delta, func(cue: Dictionary) -> bool: return _fire(world, cue)):
		world._fail("Timeline action failed")
		return
	_cruise(world)
	_ease_view(world, delta)

func _fire(world, cue: Dictionary) -> bool:
	var rv: Chassis = world.rv
	match str(cue.do):
		"drive":
			cruise = {"speed": float(cue.speed), "lateral": float(cue.get("lateral", cruise.get("lateral", world.shot.get("lateral", 0.0))))}
			if rv.gear == 0: rv.set_gear(1)
		"gear":
			return rv.set_gear(int(cue.gear))
		"brake":
			cruise = {}
			rv.control_override = {"throttle": 0.0, "brake": 1.0, "steering": 0.0}
		"line":
			# JSON numbers arrive as floats; narration ids are their integer text.
			var id := str(int(cue.id)) if cue.id is float else str(cue.id)
			world.director.mark("line " + id)
			return broadcast.play(id)
		"static":
			broadcast.set_signal(float(cue.level), bool(cue.get("cut", false)))
		"radio_off":
			broadcast.silence()
		"weather":
			var clock := world.get_node("WorldClock") as WorldClock
			_weather = {"from": clock.weather.sample(), "to": Vector3(float(cue.to[0]), float(cue.to[1]), float(cue.to[2])),
				"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
		"look":
			# Live takes leave the view to the mouse.
			if unattended:
				var seat: Node = world.actor.seated_in
				if not is_instance_valid(seat): return false
				var rest: Vector3 = seat.REST_CAMERA_ROTATION
				_look = {"camera": seat.seat_camera, "from": seat.seat_camera.rotation,
					"to": rest + Vector3(deg_to_rad(float(cue.pitch)), deg_to_rad(float(cue.yaw)), 0.0),
					"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
		"eyes":
			_eyes = {"from": float(_lids.get_shader_parameter("closure")), "to": 0.0 if bool(cue.open) else 1.0,
				"seconds": maxf(0.01, float(cue.seconds)), "time": 0.0}
		"marker":
			world.director.mark(str(cue.name))
	return true

func _cruise(world) -> void:
	if cruise.is_empty(): return
	var rv: Chassis = world.rv
	var field: WorldField = world.field
	var road := field.road_query(rv.global_position.x, rv.global_position.z)
	var frame: Transform3D = road.frame
	var speed := rv.linear_velocity.length() * 3.6
	var lookahead := clampf(5.0 + speed / 3.6 * 0.65, 5.0, 13.0)
	var ahead := _road_mark(field, float(road.s) + lookahead * absf(frame.basis.z.z), float(cruise.lateral))
	var relative := rv.to_local(ahead.origin)
	var correction := -atan2(relative.x, maxf(0.1, -relative.z))
	var error := float(cruise.speed) - speed
	rv.control_override = {"throttle": clampf(error * SPEED_GAIN, 0.0, 1.0), "brake": clampf(-error * SPEED_GAIN, 0.0, 1.0),
		"steering": clampf(correction * STEERING_GAIN, -1.0, 1.0)}

func _ease_view(world, delta: float) -> void:
	if not _look.is_empty():
		_look.time += delta
		var t := smoothstep(0.0, 1.0, minf(1.0, _look.time / _look.seconds))
		if is_instance_valid(_look.camera): _look.camera.rotation = (_look.from as Vector3).lerp(_look.to, t)
		if t >= 1.0: _look = {}
	if not _eyes.is_empty():
		_eyes.time += delta
		var closure := lerpf(_eyes.from, _eyes.to, smoothstep(0.0, 1.0, minf(1.0, _eyes.time / _eyes.seconds)))
		_set_lids(closure)
		if _eyes.time >= _eyes.seconds: _eyes = {}
	if not _weather.is_empty():
		_weather.time += delta
		var t := smoothstep(0.0, 1.0, minf(1.0, _weather.time / _weather.seconds))
		(world.get_node("WorldClock") as WorldClock).weather.set_weather((_weather.from as Vector3).lerp(_weather.to, t), true)
		if t >= 1.0: _weather = {}

## The game's own eyelid shader on a layer the clean view keeps visible.
func _build_eyelids(world, closure: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 47
	world.director.add_child(layer)
	_lids.shader = EYELIDS
	_lid_rect = ColorRect.new()
	_lid_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lid_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lid_rect.material = _lids
	layer.add_child(_lid_rect)
	_set_lids(closure)

func _set_lids(closure: float) -> void:
	_lids.set_shader_parameter("closure", closure)
	_lid_rect.visible = closure > 0.001

## Unattended take for Movie Maker. Returns how long to keep filming, or -1 after failing.
func autoplay(world) -> float:
	unattended = true
	if not world.trigger_take():
		world._fail("Could not start the trailer timeline")
		return -1.0
	if world.director.exterior_requested(): world.director.follow_preset("chase", world.rv)
	return timeline.length() + float(world.shot.get("tail", 0.5))

func autoplay_error(_world) -> String:
	return ""
