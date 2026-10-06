extends Node3D
## Native review of production tablet construction and independent structure loss.
var rv: Chassis
var player: CharacterBody3D
var tablet: Item
var observer: Camera3D
var status: Label

func _ready() -> void:
	DisplayServer.window_set_title("RV Structure Review")
	set_meta("entity_domain", true)
	var ground := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	var collider := CollisionShape3D.new()
	collider.shape = box
	ground.add_child(collider)
	var mesh := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = box.size
	mesh.mesh = ground_mesh
	ground.add_child(mesh)
	ground.position.y = -0.1
	add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("344858")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var vehicle := preload("res://rv/starter_rv.tscn").instantiate()
	add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.position.y = 1.2
	rv.freeze = true
	rv.set_physics_process(false)
	player = preload("res://player/player.tscn").instantiate()
	player.position = rv.to_global(Vector3(0, 0.51, 2.6))
	add_child(player)
	player.max_player_health = 10000.0
	player.current_player_health = 10000.0
	observer = Camera3D.new()
	add_child(observer)
	observer.position = rv.to_global(Vector3(12, 8, 13))
	observer.look_at(rv.to_global(Vector3(0, 1.3, 0)))
	observer.current = true
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 120)
	status.add_theme_font_size_override("font_size", 22)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(status)
	await get_tree().physics_frame
	await get_tree().physics_frame
	rv.energy.battery = rv.get_battery_socket().installed_battery
	rv.current_power = rv.max_power
	rv.storage.items["Metal Parts"] = 100
	tablet = rv.get_node("TabletScreen")
	rv.get_node("StructureSlots").panel("left_1").set_health(30)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	match event.keycode:
		KEY_F2:
			if is_instance_valid(tablet) and tablet.can_operate(): tablet.interact_hold(player)
		KEY_F3: slots.panel("left_1").take_damage(40)
		KEY_F4: slots.panel("right_0").take_damage(999)
		KEY_F5: slots.panel("roof_1").take_damage(999)
		KEY_F6: slots.panel("floor").take_damage(999)
		KEY_R: get_tree().reload_current_scene()
		_: return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not is_instance_valid(rv) or not is_instance_valid(status): return
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var roof := slots.panel("roof_1")
	var floor_panel := slots.panel("floor")
	status.text = "F2 平板｜F3 左中部件受擊｜F4 拆右前牆（平板掉落）\nF5 拆中段屋頂｜F6 拆地板｜R 重設\n地板：%s｜中段屋頂：%s｜玩家車內高度 %.2f｜材料 %d" % [
		"DESTROYED" if floor_panel and floor_panel.is_destroyed else "完整",
		"DESTROYED" if roof and roof.is_destroyed else "完整",
		rv.to_local(player.global_position).y, rv.get_item_count("Metal Parts")]
