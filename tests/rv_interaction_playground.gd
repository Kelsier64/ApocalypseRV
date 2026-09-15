extends Node3D
var rv: Chassis
var player: CharacterBody3D

func _ready() -> void:
	set_meta("entity_domain", true)
	# Computer-use synthesizes virtual keys; map them only inside this test fixture.
	for binding in [["interact", KEY_E], ["hotbar_1", KEY_1], ["hotbar_2", KEY_2]]:
		var key_event := InputEventKey.new()
		key_event.keycode = binding[1]
		InputMap.action_add_event(binding[0], key_event)
	get_window().title = "ApocalypseRV - Interaction Validation"
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(50, 0.2, 50)
	collision.shape = shape
	ground.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	ground.add_child(mesh)
	add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.25, 0.3)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 1.4
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.current_power = 42.0
	rv.current_fuel = 30.0
	rv.add_item(ItemNames.METAL_PARTS, 12)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(5, 1, 1.5)
	add_child(player)
	player.set_physics_process(false)
	player.add_item(ItemNames.BATTERY, false, "res://props/battery.tscn", {"battery": {"id": "validation-spare", "capacity": 100.0, "charge": 75.0, "weight": 15.0}})
	player.add_item(ItemNames.GAS_CAN, false, "res://props/gas_can.tscn")
	var layer := CanvasLayer.new()
	add_child(layer)
	var instructions := Label.new()
	instructions.position = Vector2(24, 90)
	instructions.add_theme_font_size_override("font_size", 22)
	instructions.text = "互動驗收｜F2 電池插槽／F3 駕駛座／F4 加油孔／F5 道具箱／F6 掉落電池\n1 電池／2 汽油罐｜測試固定玩家位置，使用正式射線與 E"
	layer.add_child(instructions)
	await get_tree().physics_frame
	focus(rv.get_node("BatterySocket"), Vector3(2, 0.5, 0))

func focus(target: Node3D, offset: Vector3) -> void:
	if player.in_ui_mode: return
	var camera: Camera3D = player.get_node("Camera3D")
	player.global_position = target.global_position + offset - Vector3.UP * camera.position.y
	camera.look_at(target.global_position, Vector3.UP)
	camera.current = true

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or player.in_ui_mode: return
	match event.keycode:
		KEY_F2: focus(rv.get_node("BatterySocket"), Vector3(2, 0.5, 0))
		KEY_F3: focus(rv.get_node("DriverSeat"), Vector3(0, 1.2, 1.3))
		KEY_F4: focus(rv.get_node("FuelPort"), Vector3(-0.5, 0.9, -1.2))
		KEY_F5: focus(rv.get_node("ItemBox"), Vector3(0.5, 0.9, -1.2))
		KEY_F6:
			var socket := rv.get_node_or_null("BatterySocket")
			if socket: socket.detach_from_support()
			var container := WorldEntities.get_container(self)
			for child in container.get_children():
				if child is Prop and child.item_name == ItemNames.BATTERY:
					focus(child, Vector3(2, 1, 0))
