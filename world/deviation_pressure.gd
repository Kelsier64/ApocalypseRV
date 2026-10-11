extends Node
class_name DeviationPressure
## Owns route pressure only. Existing actors keep their normal AI and lifetime.
var state := RoutePressureState.new()
var rng := RandomNumberGenerator.new()
var _rng_initialized := false
var _sample_timer := 0.0
var _route_sample: Dictionary = {}

func _ready() -> void:
	_sync_fog()

func _sync_fog() -> void:
	var clock := get_parent().get_node_or_null("WorldClock") as WorldClock
	var instances := get_parent().get_node_or_null("PoiInstances") as PoiInstanceManager
	if clock != null:
		clock.set_deviation_fog(0.0 if instances != null and (instances.busy or not instances.active_id.is_empty()) else state.fog)

func _physics_process(delta: float) -> void:
	var world := get_parent() as Node3D
	var generator := world.get_node_or_null("WorldGenerator")
	var player := world.get_node_or_null("Player") as Node3D
	var clock := world.get_node_or_null("WorldClock") as WorldClock
	if generator == null or clock == null or player == null or generator.profile == null: return
	if generator.profile.generation_version < 10: return
	var instances := world.get_node_or_null("PoiInstances") as PoiInstanceManager
	var indoors := instances != null and (instances.busy or not instances.active_id.is_empty())
	if indoors:
		clock.set_deviation_fog(0.0)
		_sample_timer = 0.0
		return
	var start := world.get_node_or_null("StartRun") as StartRun
	if not world.get("play_ready") or generator.restoring_entities or (start != null and start.phase == "preparing"): return
	if player.get("is_player_dead") == true or (player.has_method("is_grabbed") and player.is_grabbed()): return
	_sample_timer -= delta
	if _route_sample.is_empty() or _sample_timer <= 0.0:
		_sample_timer = 0.1
		_route_sample = RoutePressureSample.sample(generator.field, player.global_position)
	if not state.initialized:
		var origin := float(generator.field.stop(0).s)
		state.initialize(_route_sample.progress if _route_sample.progress_valid else origin, origin)
	if not _rng_initialized:
		rng.seed = generator.field.seed_for(0, "deviation_pressure")
		_rng_initialized = true
	var previous := state.active
	state.advance(delta, _route_sample)
	clock.set_deviation_fog(state.fog)
	if state.active and not previous:
		var interact := player.get_node_or_null("Camera3D/InteractRay")
		if interact != null and interact.has_method("show_feedback"):
			interact.show_feedback("濃霧逼近｜返回公路或步道" if state.reason == "forest" else "濃霧逼近｜沿公路繼續前進")
		print("PRESSURE_START reason=", state.reason, " highwater=", state.highwater, " progress=", _route_sample.progress)
	elif previous and not state.active:
		print("PRESSURE_RECOVERY fog=", state.fog)
	var spawn_sample := _route_sample.duplicate()
	spawn_sample.point = player.global_position
	var backwards: Vector3 = _route_sample.backward_direction
	var forest: Vector3 = _route_sample.forest_direction
	spawn_sample.danger_direction = forest if state.reason == "forest" else backwards
	if state.reason == "backtrack_forest": spawn_sample.danger_direction = (backwards + forest).normalized()
	if state.rakers_due():
		var emitted := 0
		while emitted < state.pending_rakers and PressureSpawns.raker_count(world) < 8:
			if not PressureSpawns.try_spawn(world, "raker", spawn_sample, rng): break
			emitted += 1
		state.resolve_raker_wave(emitted, PressureSpawns.raker_count(world) >= 8)
	if state.giant_due():
		state.resolve_giant(PressureSpawns.giant_present(world) or PressureSpawns.try_spawn(world, "giant", spawn_sample, rng))

func capture() -> Dictionary:
	return {"version": 1, "timing": state.capture(), "rng_initialized": _rng_initialized, "rng_state": rng.state}

static func valid_state(data: Variant) -> bool:
	return data is Dictionary and data.get("version") is int and data.version == 1 and RoutePressureState.valid_state(data.get("timing")) and data.get("rng_initialized") is bool and data.get("rng_state") is int

func restore(data: Dictionary) -> bool:
	if data.is_empty():
		state = RoutePressureState.new()
		_rng_initialized = false
	else:
		if not valid_state(data): return false
		state.restore(data.timing)
		_rng_initialized = data.rng_initialized
		rng.state = data.rng_state
	_route_sample.clear()
	_sample_timer = 0.0
	if is_node_ready(): _sync_fog()
	return true
