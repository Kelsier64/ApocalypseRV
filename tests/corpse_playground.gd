extends Node3D
## Small visible acceptance stage using production actors, props and recycler.
var player: CharacterBody3D
var observer: Camera3D
var status: Label
var replaying := false
var observing := false
var rv: Chassis

func _ready() -> void:
	set_meta("entity_domain", true)
	get_window().title = "ApocalypseRV - Corpse Carry Playground"
	get_window().size = Vector2i(1280, 800)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.12, .15, .19)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.8, .85, 1)
	environment.environment.ambient_light_energy = .7
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.shadow_enabled = true
	add_child(light)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(200, .3, 200)
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = shape.shape.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.26, .29, .3)
	mesh.material_override = material
	ground.add_child(mesh)
	ground.position.y = -.15
	add_child(ground)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(0, 0, 2)
	add_child(player)
	observer = Camera3D.new()
	add_child(observer)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(8, 0, 0)
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.current_power = 30
	var monster: Raker = load("res://enemies/raker.tscn").instantiate()
	monster.position = Vector3(0, -.25, -.5)
	monster.detection_range = 0
	monster.loot_drops = {}
	add_child(monster)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 140)
	status.add_theme_font_size_override("font_size", 20)
	canvas.add_child(status)
	await get_tree().physics_frame
	monster.take_damage(1000)
	print("CORPSE_PLAYGROUND_READY")
	if "--replay" in OS.get_cmdline_user_args(): _replay()

func _process(_delta: float) -> void:
	if player == null: return
	if observing:
		var target := player.global_position + Vector3.UP * 1.0
		observer.global_position = target + player.global_basis * Vector3(3, 1.1, -3.2)
		observer.look_at(target)
	status.text = "CORPSE / E pickup | G drop | WASD move\nF1 first person | F2 pickup nearby (test) | F3 observer | F4 movement replay\nF5 player death | F6 recycle held corpse | Esc close\nHeld: %s | recycled: %d" % [player.get_active_item_name(), rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)]

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_F1: observing = false; player.camera.make_current(); Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		KEY_F2: _pick_nearby()
		KEY_F3: observing = true; observer.make_current(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_F4: _replay()
		KEY_F5: player.damage_cooldown = 0; player.take_damage(1000)
		KEY_F6: _recycle()

func _pick_nearby() -> void:
	if not player.inventory.items.is_empty() or player.is_player_dead: return
	var nearest: CorpseProp
	for child in WorldEntities.get_container(self).get_children():
		if child is CorpseProp and not child.is_queued_for_deletion():
			if nearest == null or player.global_position.distance_to(child.global_position) < player.global_position.distance_to(nearest.global_position): nearest = child
	if nearest != null: nearest.interact(player)

func _recycle() -> void:
	if not player.held_item_node is CorpseProp: return
	var identity: String = player.inventory.active_item().state.id
	player.drop_item()
	await get_tree().physics_frame
	for child in WorldEntities.get_container(self).get_children():
		if child is CorpseProp and child.persistent_id == identity:
			var recycler: Equipment = rv.get_node("Scrapper")
			recycler.recycle_prop(child)
			for frame in 100:
				rv.step_energy_system(0, 0, 0, 1.0 / 60.0)
				await get_tree().physics_frame
			print("CORPSE_RECYCLED materials=", rv.get_item_count(ItemNames.UNKNOWN_MATERIAL))

func _replay() -> void:
	if replaying: return
	replaying = true
	await get_tree().create_timer(1.0).timeout
	_pick_nearby()
	for frame in 300:
		Input.action_press("move_forward")
		player.rotation.y += .006 if frame > 90 else 0.0
		await get_tree().physics_frame
	Input.action_release("move_forward")
	replaying = false
	print("CORPSE_MOVEMENT_REPLAY_COMPLETE")
