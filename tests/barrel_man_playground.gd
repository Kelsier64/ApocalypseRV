extends Node3D
## Production actors, real wheel power, and a separate authored-animation gallery.
const BARREL = preload("res://enemies/barrel_man.tscn")
const NORMAL_BARREL = preload("res://props/oil_barrel.tscn")
const PLAYER = preload("res://player/player.tscn")
const RV = preload("res://rv/new_rv.tscn")
var actors: Node3D
var camera: Camera3D
var hud: Label
var player: CharacterBody3D
var rv: Chassis
var monster: BarrelMan
var oil_barrel: OilBarrel
var gallery: Array[BarrelMan] = []
var mode := 1
var elapsed := 0.0
var ready_to_run := false
var health_before := 0.0
var exploded := false
var paused := false
var requested_capture := false
var capture_clock := 0.0
var mode_generation := 0
var headless_check := false
var check_completed := false
var player_start := Vector3.ZERO
var rv_start := Vector3.ZERO
var monster_start := Vector3.ZERO
var player_distance := 0.0
var vehicle_distance := 0.0
var monster_distance := 0.0
var chase_seen := false
var fastest_monster := 0.0
var route_target: CharacterBody3D
var route_index := 0
var route_points := PackedVector3Array([Vector3(12,0,-3.8), Vector3(12,.82,-9.6), Vector3(12,0,-13), Vector3(18,0,-13), Vector3(18,0,-2), Vector3(12,0,-2), Vector3(12,.82,-9.6), Vector3(12,0,-4), Vector3(8,0,-4), Vector3(8,0,3), Vector3(20,0,3), Vector3(20,0,-15)])
var uphill_seen := false
var downhill_seen := false
var falling_seen := false
var landing_seen := false
var terrain_air_time := 0.0
var terrain_previous_floor := true
var terrain_previous_yaw := 0.0
var left_turn := 0.0
var right_turn := 0.0
var milestone_index := 0
var blast_capture_time := -1.0
var blast_capture_index := 0
var capture_sequence := 0
var capture_folder := ""
var pre_blast_image: Image
var proximity_arm_time := -1.0
var proximity_blast_delay := -1.0

func _ready() -> void:
	get_window().title = "ApocalypseRV - Barrel Man"
	set_meta("entity_domain", true)
	actors = WorldEntities.get_container(self)
	actors.process_mode = Node.PROCESS_MODE_PAUSABLE
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("18252b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c7d9e5")
	environment.environment.ambient_light_energy = .7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)
	_solid(Vector3(0, -.1, -25), Vector3(80, .2, 150), Color("343d3d"))
	# A room with a real opening, plus a separate modest incline for manual play.
	_solid(Vector3(-12, 1.5, -6), Vector3(.25, 3, 10), Color("535b59"))
	_solid(Vector3(-6, 1.5, -11), Vector3(12, 3, .25), Color("535b59"))
	_solid(Vector3(-8, 1.5, -1), Vector3(8, 3, .25), Color("535b59"))
	_solid(Vector3(-.8, 1.5, -1), Vector3(1.6, 3, .25), Color("535b59"))
	_solid(Vector3(0, 1.5, -6), Vector3(.25, 3, 10), Color("535b59"))
	_solid(Vector3(-6, 3.1, -6), Vector3(12, .2, 10), Color("535b59"))
	var ramp := _solid(Vector3(12, .4, -7), Vector3(5, .2, 6), Color("485750"))
	ramp.rotation_degrees.x = 8
	var nav := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.agent_radius = .5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = .25
	nav.navigation_mesh = mesh
	add_child(nav)
	for child in get_children():
		if child is StaticBody3D: child.reparent(nav)
	nav.bake_navigation_mesh(false)
	camera = Camera3D.new()
	camera.fov = 48
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(18, 18)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	await get_tree().physics_frame
	var arguments := OS.get_cmdline_user_args()
	requested_capture = "--capture" in arguments
	headless_check = "--headless-check" in arguments
	await _select_mode(10 if "--oil-barrel-replay" in arguments else (8 if "--proximity-replay" in arguments else (7 if "--terrain-replay" in arguments else (4 if "--vehicle-replay" in arguments else (3 if "--replay" in arguments else (5 if "--chase-replay" in arguments else 1))))))

func _solid(point: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.position = point
	RoadsideKit.part(body, size, Vector3.ZERO, color)
	return body

func _spawn_barrel(at: Vector3) -> BarrelMan:
	var actor := BARREL.instantiate() as BarrelMan
	actors.add_child(actor)
	actor.position = at
	return actor

func _select_mode(next: int) -> void:
	mode_generation += 1
	var generation := mode_generation
	ready_to_run = false
	get_tree().paused = false
	for action in ["move_forward", "sprint"]: Input.action_release(action)
	player = null
	rv = null
	monster = null
	oil_barrel = null
	route_target = null
	gallery.clear()
	for child in actors.get_children(): child.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	if generation != mode_generation: return
	mode = next
	elapsed = 0
	capture_clock = 0
	exploded = false
	paused = false
	check_completed = false
	player_distance = 0.0
	vehicle_distance = 0.0
	monster_distance = 0.0
	chase_seen = false
	fastest_monster = 0.0
	route_index = 1
	uphill_seen = false
	downhill_seen = false
	falling_seen = false
	landing_seen = false
	terrain_air_time = 0.0
	terrain_previous_floor = true
	left_turn = 0.0
	right_turn = 0.0
	milestone_index = 0
	blast_capture_time = -1.0
	blast_capture_index = 0
	capture_sequence = 0
	pre_blast_image = null
	proximity_arm_time = -1.0
	proximity_blast_delay = -1.0
	capture_folder = "res://.godot/barrel-playground-captures/mode-%d-%d-%d" % [mode,roundi(Time.get_unix_time_from_system() * 1000),generation]
	if requested_capture and DisplayServer.get_name() != "headless": DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_folder))
	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if mode == 1:
		var ordinary := NORMAL_BARREL.instantiate() as Item
		actors.add_child(ordinary)
		ordinary.position = Vector3(-3.2,.5,0)
		ordinary.freeze = true
		for index in range(4):
			var actor := _spawn_barrel(Vector3(-1.5 + index*1.7,0,0))
			actor.set_physics_process(false)
			actor.get_node("BodyMesh").set_physics_process(false)
			actor.get_node("BodyMesh").ground_modifier.active = false
			gallery.append(actor)
		camera.position = Vector3(5,3.1,8)
		camera.look_at(Vector3(.1,.8,0))
	elif mode in [2,3,8]:
		player = PLAYER.instantiate() as CharacterBody3D
		actors.add_child(player)
		player.position = Vector3(2,0,3.4 if mode == 8 else 12.0)
		monster = _spawn_barrel(Vector3(2,0,0))
		var ordinary := NORMAL_BARREL.instantiate() as Item
		actors.add_child(ordinary)
		ordinary.position = Vector3(4,.5,0)
		if mode == 2:
			player.camera.current = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			camera.current = true
			camera.position = Vector3(9,4.5,8)
			camera.look_at(Vector3(2,1,3))
	elif mode == 7:
		route_target = CharacterBody3D.new()
		route_target.name = "AutomaticRouteTarget"
		route_target.collision_layer = 0
		route_target.collision_mask = 0
		actors.add_child(route_target)
		route_target.add_to_group(Groups.PLAYER)
		route_target.position = route_points[0]
		var marker := MeshInstance3D.new()
		marker.mesh = SphereMesh.new()
		marker.mesh.radius = .16
		marker.mesh.height = .32
		marker.position.y = .8
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ffd876")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = material
		route_target.add_child(marker)
		var label := Label3D.new()
		label.text = "自動路線目標（無碰撞）"
		label.position.y = 1.5
		label.font_size = 40
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		route_target.add_child(label)
		monster = _spawn_barrel(Vector3(12,0,1))
		# A deliberate fixture path exercises the drop edge rather than allowing
		# navigation to reroute downhill. Production acceleration/physics remain live.
		monster.nav_agent = null
		terrain_previous_yaw = monster.rotation.y
		camera.position = Vector3(24,7,8)
		camera.look_at(Vector3(12,1,-5))
	else:
		var shell := RV.instantiate() as Node3D
		actors.add_child(shell)
		shell.position = Vector3(5,1.8,14)
		rv = shell.get_node("Chassis") as Chassis
		rv.allow_test_controls = true
		rv.handbrake = true
		for tick in 100:
			await get_tree().physics_frame
			if generation != mode_generation: return
		health_before = rv.get_engine().health
		if mode == 10:
			oil_barrel = NORMAL_BARREL.instantiate() as OilBarrel
			oil_barrel.position = Vector3(5,.5,-8)
			actors.add_child(oil_barrel)
		else:
			monster = _spawn_barrel(Vector3(5,0,-8) if mode == 4 else Vector3(8,0,22))
		if mode == 4:
			# Isolate ramming a disguised barrel; the real chassis contact hook
			# remains live even when perception/movement are paused in this fixture.
			monster.set_physics_process(false)
		rv.gear = 2
		rv.set_engine_running(true)
		rv.handbrake = false
		camera.position = Vector3(18,8,3)
		camera.look_at(Vector3(5,1.5,-5))
	if is_instance_valid(player): player_start = player.global_position
	if is_instance_valid(rv): rv_start = rv.global_position
	if is_instance_valid(monster): monster_start = monster.global_position
	ready_to_run = true
	print("BARREL_PLAYGROUND mode=%d ready" % mode)

func _physics_process(delta: float) -> void:
	if not ready_to_run or paused: return
	elapsed += delta
	if is_instance_valid(player): player_distance = maxf(player_distance, player.global_position.distance_to(player_start))
	if is_instance_valid(rv): vehicle_distance = maxf(vehicle_distance, rv.global_position.distance_to(rv_start))
	if is_instance_valid(monster):
		monster_distance = maxf(monster_distance, monster.global_position.distance_to(monster_start))
		chase_seen = chase_seen or monster.phase == BarrelMan.Phase.CHASE
		fastest_monster = maxf(fastest_monster, monster.horizontal_speed)
		if proximity_arm_time < 0.0 and monster.proximity_fuse_remaining >= 0.0:
			proximity_arm_time = elapsed
			print("BARREL_PLAYGROUND fuse_armed mode=%d t=%.3f remaining=%.3f" % [mode,elapsed,monster.proximity_fuse_remaining])
	if mode == 1:
		for index in gallery.size():
			var visual = gallery[index].get_node("BodyMesh")
			var clip: String = ["disguised","rise","run","sprint"][index]
			var time := fmod(elapsed, 4.0)
			if index == 1:
				clip = "rise" if time < .8 else ("idle" if time < 2.4 else ("retract" if time < 3.2 else "disguised"))
			visual._play(clip, .0)
			visual.animation_player.advance(delta)
	elif mode == 3 and is_instance_valid(player):
		if elapsed < 3.0 and not player.is_player_dead and not player.is_crawling(): Input.action_press("move_forward")
		else: Input.action_release("move_forward")
	elif mode == 8 and is_instance_valid(player):
		# Continuous production movement stops on arming, before any collision.
		# The barrel keeps its normal AI and finishes the committed countdown.
		if proximity_arm_time < 0.0 and not exploded: Input.action_press("move_forward")
		else: Input.action_release("move_forward")
	elif mode == 7 and is_instance_valid(monster):
		_terrain_step(delta)
	elif mode in [4,5,10] and is_instance_valid(rv):
		var driving := elapsed < (20.0 if mode == 5 else 15.0) and not exploded
		var throttle := 1.0 if mode in [4,10] else clampf(.5 + (6.0-rv.road_speed())*.45, 0.0, 1.0)
		rv.control_override = {"throttle": throttle, "steering": 0.0} if driving else {"brake": 1.0}
		if not driving and rv.road_speed()<.2: rv.handbrake = true
		var focus := rv.global_position
		if is_instance_valid(monster): focus = focus.lerp(monster.global_position, .5)
		elif is_instance_valid(oil_barrel): focus = focus.lerp(oil_barrel.global_position, .5)
		camera.global_position = focus + (Vector3(13,5,-14) if mode == 10 else Vector3(17,10,20))
		camera.look_at(focus + Vector3.UP)
	var source_exploded := (not is_instance_valid(oil_barrel) or oil_barrel.is_destroyed) if mode == 10 else (not is_instance_valid(monster) or monster.is_dead)
	if mode != 1 and not exploded and source_exploded:
		exploded = true
		if proximity_arm_time >= 0.0:
			proximity_blast_delay = elapsed - proximity_arm_time
			print("BARREL_PLAYGROUND fuse_result delay=%.3f" % proximity_blast_delay)
		if requested_capture and DisplayServer.get_name() != "headless":
			blast_capture_time = elapsed
			if pre_blast_image != null: pre_blast_image.save_png(capture_folder + "/blast-before.png")
			_capture.call_deferred("blast+000")
		print("BARREL_PLAYGROUND explosion mode=%d t=%.2f player_hp=%s engine=%s" % [mode,elapsed,player.current_player_health if is_instance_valid(player) else "none",rv.get_engine().health if is_instance_valid(rv) else "none"])
		_report_after_blast.call_deferred()
	if headless_check and not check_completed and elapsed >= 18.0:
		_finish_headless_check()
	elif mode == 7 and not headless_check and not check_completed and elapsed >= 18.0:
		# Keep the completed review on the platform instead of eventually sending
		# its automatic target past the finite playground floor.
		check_completed = true
		paused = true
		get_tree().paused = true
		print("BARREL_PLAYGROUND terrain review complete; R restarts")

func _terrain_step(delta: float) -> void:
	var floor_now := monster.is_on_floor()
	var real_velocity := monster.get_real_velocity()
	var point := monster.global_position
	if absf(point.x - 12) < 2.5 and point.z < -4 and point.z > -10 and point.y > .3:
		uphill_seen = uphill_seen or (floor_now and real_velocity.y > .05)
		downhill_seen = downhill_seen or (floor_now and real_velocity.y < -.05)
	if monster.phase == BarrelMan.Phase.CHASE:
		if not floor_now:
			terrain_air_time += delta
			if terrain_air_time > .12: falling_seen = true
		elif not terrain_previous_floor:
			landing_seen = landing_seen or terrain_air_time > .12
			terrain_air_time = 0.0
		var yaw_delta := angle_difference(terrain_previous_yaw, monster.rotation.y)
		if yaw_delta > 0: left_turn += yaw_delta
		else: right_turn -= yaw_delta
		if point.distance_to(route_target.global_position) < 5.5:
			var goal := route_points[route_index] if route_index < route_points.size() else route_target.position + Vector3.FORWARD * 2
			route_target.position = route_target.position.move_toward(goal, 6.0 * delta)
			if route_index < route_points.size() and route_target.position.distance_to(goal) < .05:
				print("BARREL_PLAYGROUND terrain waypoint=%d position=%s" % [route_index, point])
				route_index += 1
	terrain_previous_floor = floor_now
	terrain_previous_yaw = monster.rotation.y
	camera.global_position = point + Vector3(3,1.8,3)
	camera.look_at(point + Vector3.UP * .85)

func _finish_headless_check() -> void:
	check_completed = true
	var valid := exploded
	if mode == 3: valid = valid and player_distance > 1.0 and is_instance_valid(player) and player.current_player_health < player.max_player_health
	elif mode == 8:
		valid = valid and proximity_arm_time >= 0.0 and proximity_blast_delay >= .499 and proximity_blast_delay <= .54 and player_distance > .5 and is_instance_valid(player) and player.current_player_health < player.max_player_health
	elif mode in [4,5,10]:
		valid = valid and vehicle_distance > 1.0 and is_instance_valid(rv) and rv.get_engine().health <= health_before - 59.99 and _broken_panels() > 0
		if mode == 5: valid = valid and chase_seen and monster_distance > 1.0 and fastest_monster <= 10.05
	elif mode == 7:
		valid = not exploded and monster_distance > 20.0 and fastest_monster >= 5.5 and fastest_monster <= 6.05 and uphill_seen and downhill_seen and falling_seen and landing_seen and left_turn > .4 and right_turn > .4
		print("BARREL_PLAYGROUND terrain_result waypoint=%d up=%s down=%s fall=%s land=%s left=%.2f right=%.2f" % [route_index,uphill_seen,downhill_seen,falling_seen,landing_seen,left_turn,right_turn])
	else: valid = false
	print("BARREL_PLAYGROUND check mode=%d player_distance=%.2f vehicle_distance=%.2f monster_distance=%.2f chase_seen=%s fastest_monster=%.2f" % [mode,player_distance,vehicle_distance,monster_distance,chase_seen,fastest_monster])
	if valid: print("PASS: bounded production barrel replay mode=%d" % mode)
	else: push_error("FAIL: production barrel replay mode=%d did not meet contact/movement/damage criteria" % mode)
	get_tree().quit(0 if valid else 1)

func _report_after_blast() -> void:
	var generation := mode_generation
	await get_tree().physics_frame
	await get_tree().physics_frame
	if generation != mode_generation: return
	if is_instance_valid(rv):
		print("BARREL_PLAYGROUND vehicle_result engine_before=%.2f after=%.2f broken_panels=%d speed=%.2f" % [health_before,rv.get_engine().health,_broken_panels(),rv.road_speed()])
	if is_instance_valid(player): print("BARREL_PLAYGROUND player_result hp=%.1f body=%s" % [player.current_player_health,player.body_state.capture()])

func _broken_panels() -> int:
	var count := 0
	if is_instance_valid(rv):
		for node in rv.find_children("*","RigidBody3D",true,false):
			if node is RVStructurePanel and node.is_destroyed: count += 1
	return count

func _process(delta: float) -> void:
	if hud == null: return
	var titles := {1:"外觀與動畫｜普通油桶 / 偽裝 / 起身收腿 / 6m/s / 10m/s",2:"手動步行接近",3:"連續步行輸入重播",4:"輪驅撞擊偽裝桶（固定偽裝以隔離碰撞）",5:"追車與輪驅行駛",7:"坡面／左右轉向／落地：無碰撞路線目標，直線引導",8:"近距離倒數：走進 1.5 m 後停步，等待 0.5 秒",10:"輪驅撞擊一般油桶（正式 Item）"}
	hud.text = "油桶人驗收場 — %s\nF1 外觀 · F2 步行 · F3 徒步重播 · F4 撞桶 · F5 追車\nF6 保存 · F7 坡面 · F8 倒數 · F9 恢復 · P 暫停 · R 重設 · Esc 滑鼠\n" % titles.get(mode,"")
	hud.text += "F10 車撞一般油桶\n"
	if is_instance_valid(monster): hud.text += "狀態 %s｜速度 %.2f m/s\n" % [BarrelMan.Phase.keys()[monster.phase],monster.horizontal_speed]
	if is_instance_valid(monster) and monster.proximity_fuse_remaining >= 0.0: hud.text += "爆炸倒數 %.2f 秒（接觸即爆）\n" % monster.proximity_fuse_remaining
	if proximity_blast_delay >= 0.0: hud.text += "啟動至爆炸 %.3f 秒\n" % proximity_blast_delay
	if is_instance_valid(player): hud.text += "玩家 HP %.0f｜%s\n" % [player.current_player_health,player.body_state.capture()]
	if is_instance_valid(rv): hud.text += "RV %.1f km/h｜引擎 %.0f → %.0f｜損毀車殼 %d\n" % [rv.road_speed()*3.6,health_before,rv.get_engine().health,_broken_panels()]
	if exploded: hud.text += "已爆炸；傷害與狀態詳見 log。"
	if mode == 7: hud.text += "上坡 %s｜下坡 %s｜落下 %s｜落地 %s｜路線 %d/%d\n" % [uphill_seen,downhill_seen,falling_seen,landing_seen,route_index,route_points.size()]
	if requested_capture and ready_to_run and DisplayServer.get_name() != "headless":
		capture_clock += delta
		var milestones := [1.0,2.0,2.5,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0,12.0,14.0,16.0] if mode == 7 else [.5,1.0,2.0,3.0,4.0]
		if milestone_index < milestones.size() and elapsed >= milestones[milestone_index]:
			_capture.call_deferred("milestone-%.1f" % milestones[milestone_index])
			milestone_index += 1
		if not exploded and mode in [2,3,4,5,8,10] and capture_clock >= .15:
			capture_clock = 0.0
			_capture.call_deferred("buffer", true)
		var blast_offsets := [.05,.15,.35,.65,1.1,2.0,3.4,4.0]
		if blast_capture_time >= 0.0 and blast_capture_index < blast_offsets.size() and elapsed - blast_capture_time >= blast_offsets[blast_capture_index]:
			_capture.call_deferred("blast+%03d" % roundi(blast_offsets[blast_capture_index] * 1000))
			blast_capture_index += 1

func _capture(label: String, buffer_only := false) -> void:
	var generation := mode_generation
	var capture_elapsed := elapsed
	var sequence := capture_sequence
	if not buffer_only: capture_sequence += 1
	await RenderingServer.frame_post_draw
	if generation != mode_generation: return
	var image := get_viewport().get_texture().get_image()
	if buffer_only:
		if not exploded: pre_blast_image = image
	else:
		var path := "%s/%02d-t%.3f-%s.png" % [capture_folder,sequence,capture_elapsed,label]
		image.save_png(path)
		print("BARREL_PLAYGROUND capture=%s" % path)

func _save_monsters() -> void:
	if not ready_to_run: return
	var records: Array = []
	for child in actors.get_children():
		if child is BarrelMan:
			var record := WorldActorSnapshot.capture(child)
			if not record.is_empty(): records.append(record)
	var file := FileAccess.open("user://barrel_man_playground.save", FileAccess.WRITE)
	if file == null: return
	file.store_var(records)
	print("BARREL_PLAYGROUND saved actors=%d" % records.size())

func _load_monsters() -> void:
	if not ready_to_run: return
	var generation := mode_generation
	if not FileAccess.file_exists("user://barrel_man_playground.save"): return
	var file := FileAccess.open("user://barrel_man_playground.save", FileAccess.READ)
	if file == null: return
	var records: Variant = file.get_var(false)
	if not records is Array: return
	for record in records:
		if not WorldActorSnapshot.validation_error(record, "playground").is_empty(): return
	for child in actors.get_children():
		if child is BarrelMan: child.queue_free()
	gallery.clear()
	await get_tree().physics_frame
	if generation != mode_generation: return
	for record in records:
		monster = WorldActorSnapshot.restore(record, actors)
		if mode == 1:
			monster.set_physics_process(false)
			var visual := monster.get_node("BodyMesh")
			visual.set_physics_process(false)
			visual.ground_modifier.active = false
			gallery.append(monster)
		elif mode == 4: monster.set_physics_process(false)
		elif mode == 7: monster.nav_agent = null
	print("BARREL_PLAYGROUND restored actors=%d" % records.size())

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode >= KEY_F1 and event.keycode <= KEY_F5: _select_mode.call_deferred(event.keycode - KEY_F1 + 1)
	elif event.keycode == KEY_R: _select_mode.call_deferred(mode)
	elif event.keycode == KEY_F6: _save_monsters()
	elif event.keycode == KEY_F7: _select_mode.call_deferred(7)
	elif event.keycode == KEY_F8: _select_mode.call_deferred(8)
	elif event.keycode == KEY_F9: _load_monsters.call_deferred()
	elif event.keycode == KEY_F10: _select_mode.call_deferred(10)
	elif event.keycode == KEY_P:
		paused = not paused
		get_tree().paused = paused
		Input.action_release("move_forward")
		if is_instance_valid(rv): rv.control_override = {"brake": 1.0}
	elif event.keycode == KEY_ESCAPE: Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _exit_tree() -> void:
	Input.action_release("move_forward")
	get_tree().paused = false
