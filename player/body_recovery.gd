extends CanvasLayer
## Owns one death's print order and the camera handoff. The station owns all work.
enum Phase { IDLE, DYING, WATCHING, WAKING }
const RECIPE := "printed_player"
const PlayerVisual = preload("res://player/player_model_visual.gd")
const OBSERVATION_DELAY := 1.0
const DEATH_FADE_SECONDS := 1.0
const CRASH_FADE_SECONDS := 0.075
const WAKE_SECONDS := 1.5
var phase := Phase.IDLE
var waking_in_printed_body := false
var station: CraftingStation
var job_id := ""
var observer: Camera3D
var exterior_layer: CanvasLayer
var exterior_shade: ColorRect
var exterior_status: Label
var interior: PoiInstanceManager
var attempted := false
var elapsed := 0.0
var _death_fade_seconds := DEATH_FADE_SECONDS
var shade := ColorRect.new()
var status := Label.new()
var breath := AudioStreamPlayer.new()
var stalled := false
var wake_pitch := 0.0
var hidden_hud: Viewport
@onready var player: CharacterBody3D = get_parent()
@onready var game_settings := get_node("/root/GameSettings")

func _ready() -> void:
	layer = 55
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.material = ShaderMaterial.new()
	shade.material.shader = preload("res://player/body_recovery.gdshader")
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status.offset_top = -76
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_constant_override("outline_size", 5)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	breath.volume_db = -12
	breath.bus = &"Effects"
	add_child(breath)
	hide()
	set_physics_process(false)

func begin(crash := false) -> void:
	reset()
	phase = Phase.DYING
	var lost_head: bool = not player.body_state.has_part(&"head")
	_death_fade_seconds = CRASH_FADE_SECONDS if crash else DEATH_FADE_SECONDS
	if lost_head: _death_fade_seconds = 0.0
	show()
	_hide_hud(get_viewport())
	_set_shade(1.0 if lost_head else 0.0)
	set_physics_process(true)

func try_queue() -> void:
	if attempted: return
	if phase == Phase.IDLE: begin()
	attempted = true
	var domain: Node3D = player
	var origin := player.global_position
	interior = player.get_viewport().get_parent() as PoiInstanceManager
	if interior != null and interior.recovery_home(player) != null:
		domain = interior.recovery_home(player)
		origin = interior.stream_anchor
	else:
		interior = null
	var closest := INF
	for candidate: CraftingStation in get_tree().get_nodes_in_group(Groups.CRAFTING_STATIONS):
		if candidate.is_queued_for_deletion() or not WorldEntities.same_world(domain, candidate): continue
		var distance := candidate.global_position.distance_squared_to(origin)
		if distance < closest and candidate.craft_rejection_reason(RECIPE).is_empty():
			station = candidate
			closest = distance
	if station != null:
		job_id = station.queue_recipe(RECIPE)
		if awaiting_print(): station.job_delivered.connect(_on_delivered)

func awaiting_print() -> bool:
	return not job_id.is_empty()

func _physics_process(delta: float) -> void:
	elapsed += delta
	match phase:
		Phase.DYING:
			if _death_fade_seconds > 0.0:
				_set_shade(smoothstep(0.0, _death_fade_seconds, elapsed))
			if elapsed >= OBSERVATION_DELAY and awaiting_print(): _start_watching()
		Phase.WATCHING:
			_update_watch()
		Phase.WAKING:
			_set_shade(1.0 - smoothstep(.12, WAKE_SECONDS, elapsed))
			if waking_in_printed_body:
				player.camera.rotation.x = lerpf(wake_pitch, -.06, smoothstep(.7, WAKE_SECONDS, elapsed))
			if elapsed >= WAKE_SECONDS: reset()

func _start_watching() -> void:
	if not is_instance_valid(station) or not station.is_inside_tree():
		_abandon_print()
		return
	observer = Camera3D.new()
	observer.fov = 64.0
	observer.near = .035
	observer.cull_mask = (player.camera.cull_mask | PlayerVisual.FULL_BODY_LAYER) & ~PlayerVisual.LOCAL_VIEW_LAYER
	station.add_child(observer)
	# Pick the clearest fixed side of the bed, including inside a narrow RV.
	var focus := station.spawn_marker.global_position + station.global_basis.y * .58
	var space := station.get_world_3d().direct_space_state
	var best_distance := -1.0
	for offset: Vector3 in [Vector3(1.1, .48, -2.25), Vector3(-1.1, .48, -2.25), Vector3(2.25, .42, -.65), Vector3(-2.25, .42, -.65), Vector3(1.3, .48, 2.1)]:
		var end := focus + station.global_basis * offset
		var ray := PhysicsRayQueryParameters3D.create(focus, end, 1, [station.get_rid()])
		var hit := space.intersect_ray(ray)
		var distance := focus.distance_to(hit.position if not hit.is_empty() else end)
		if distance > best_distance:
			best_distance = distance
			observer.global_position = focus + (end - focus).normalized() * maxf(.12, distance - .12)
		if hit.is_empty(): break
	observer.look_at(focus, station.global_basis.y)
	observer.make_current()
	if is_instance_valid(interior):
		exterior_layer = CanvasLayer.new()
		exterior_layer.layer = layer
		interior.add_child(exterior_layer)
		exterior_shade = shade.duplicate()
		exterior_status = status.duplicate()
		exterior_layer.add_child(exterior_shade)
		exterior_layer.add_child(exterior_status)
		_hide_hud(station.get_viewport())
		interior.show_recovery_camera(true)
	phase = Phase.WATCHING
	elapsed = 0.0

func _update_watch() -> void:
	if not is_instance_valid(station) or not station.is_inside_tree():
		_abandon_print()
		return
	var index := 0
	while index < station.jobs.size() and station.jobs[index].id != job_id: index += 1
	if index == station.jobs.size():
		_abandon_print()
		return
	var reason := station.work_blockage if station.can_operate() else "Workstation unavailable"
	stalled = not reason.is_empty()
	if stalled:
		status.text = reason + "   ·   [E] Revive near remains"
	elif index > 0:
		status.text = "Body queued   ·   %d ahead" % index
	else:
		status.text = ""
	if is_instance_valid(exterior_status): exterior_status.text = status.text
	var closing := 0.0
	if index == 0 and not stalled:
		closing = 1.0 - smoothstep(0.0, .35, station.jobs[0].remaining)
	_set_shade(maxf(1.0 - smoothstep(0.0, .45, elapsed), closing))

func _input(event: InputEvent) -> void:
	if phase == Phase.WATCHING and stalled and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_abandon_print()

func _abandon_print() -> void:
	_release_order()
	_end_observation()
	phase = Phase.DYING
	elapsed = _death_fade_seconds
	_set_shade(1.0)
	player.camera.make_current()

func _on_delivered(id: String, item: Item) -> void:
	if id != job_id or not item is PrintedPlayerBody: return
	var body := item as PrintedPlayerBody
	var target := body.controller_pose(player)
	var remote := not WorldEntities.same_world(player, body)
	if not player.is_player_dead or not player.ragdoll_control.active or (remote and (not is_instance_valid(interior) or interior.recovery_home(player) == null)) or not body._destination_clear(player, target):
		_abandon_print()
		return
	var manager := interior
	var nozzle := station.get_node("Details/Gantry/Carriage/Head") as Node3D
	var look_target := nozzle.global_position
	_release_order()
	_end_observation()
	player._leave_dead_body()
	if remote: manager.return_to_print_bed(player)
	body.collision_layer = 0
	body.collision_mask = 0
	body.hide()
	player.global_transform = target
	player._finish_respawn(body.crouching)
	waking_in_printed_body = true
	body.attach_controller_to_floor(player, target, body.linear_velocity)
	var direction: Vector3 = look_target - player.camera.global_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.camera.rotation.x = clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -.85, .85)
	wake_pitch = player.camera.rotation.x
	player.reset_physics_interpolation()
	body.queue_free()

func wake() -> void:
	_hide_hud(get_viewport())
	phase = Phase.WAKING
	elapsed = 0.0
	if DisplayServer.get_name() != "headless":
		breath.stream = preload("res://rv/vehicle_audio.gd").synth("inhale")
		breath.play()
	show()
	set_physics_process(true)
	_set_shade(1.0)

func _set_shade(closure: float) -> void:
	shade.visible = closure > .001
	if is_instance_valid(exterior_shade): exterior_shade.visible = shade.visible
	shade.material.set_shader_parameter("closure", closure)
	var sudden_blackout := phase == Phase.DYING and _death_fade_seconds == 0.0
	game_settings.set_temporary_master_mute(self, sudden_blackout)
	if DisplayServer.get_name() != "headless":
		player.injury_effects.set_consciousness_muffle(0.0 if sudden_blackout else closure)

func _release_order() -> void:
	if is_instance_valid(station):
		if station.job_delivered.is_connected(_on_delivered): station.job_delivered.disconnect(_on_delivered)
		if awaiting_print() and station.is_inside_tree() and not station.is_queued_for_deletion(): station.cancel_job(job_id)
	station = null
	job_id = ""

func _end_observation() -> void:
	if is_instance_valid(observer): observer.queue_free()
	observer = null
	if is_instance_valid(exterior_layer):
		exterior_layer.hide()
		exterior_layer.queue_free()
		exterior_layer = null
		exterior_shade = null
		exterior_status = null
		if is_instance_valid(interior): interior.show_recovery_camera(false)
		if is_inside_tree(): _hide_hud(get_viewport())
	interior = null
	stalled = false
	status.text = ""

func _hide_hud(view: Viewport) -> void:
	if hidden_hud == view: return
	if is_instance_valid(hidden_hud) and hidden_hud.is_inside_tree(): HUDVisibility.set_cinematic(hidden_hud, false)
	hidden_hud = view
	if view != null: HUDVisibility.set_cinematic(view, true)

func reset() -> void:
	_release_order()
	_end_observation()
	_hide_hud(null)
	if phase != Phase.IDLE and is_instance_valid(player.injury_effects):
		player.injury_effects.set_consciousness_muffle(0.0)
	game_settings.set_temporary_master_mute(self, false)
	breath.stop()
	phase = Phase.IDLE
	attempted = false
	waking_in_printed_body = false
	elapsed = 0.0
	hide()
	set_physics_process(false)

func _exit_tree() -> void:
	if phase != Phase.IDLE: reset()
