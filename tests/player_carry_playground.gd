extends Node3D
const ITEMS := ["flashlight", "scrap", "battery", "oil_barrel", "engine_standard", ""]
var actor: CharacterBody3D
var observer: Camera3D
var label: Label
var selected := 0
var moving := false
var phase := 0.0
var hand_closeup := false
var hand_angle := 0

func _ready() -> void:
	process_physics_priority = 2 # After locomotion, before the child carry overlay.
	DisplayServer.window_set_title("Player Carry Playground")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.18, .21, .25)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = PlaneMesh.new()
	mesh.mesh.size = Vector2(50, 50)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(.25, .28, .3)
	mesh.material_override = floor_material
	floor_body.add_child(mesh)
	add_child(floor_body)
	actor = preload("res://player/player.tscn").instantiate()
	add_child(actor)
	observer = Camera3D.new()
	observer.position = Vector3(2.1, 1.8, -2.8)
	add_child(observer)
	observer.look_at(Vector3(0, 1.15, 0))
	observer.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20, 160)
	canvas.add_child(label)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--item="):
			var index := ITEMS.find(argument.trim_prefix("--item="))
			if index >= 0: selected = index
		elif argument == "--hands": hand_closeup = true
	_equip()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _equip() -> void:
	actor.inventory.items.clear()
	actor.inventory.active_slot = 0
	var key: String = ITEMS[selected]
	if not key.is_empty(): actor.add_item(key, key in ["oil_barrel", "engine_standard"], "res://props/" + key + ".tscn")
	actor._equip_active_slot()
	label.text = "F1 View | F2 Item | F3 Walk | F4 Look pitch | F5 Hands | F6 Orbit\n" + (key if not key.is_empty() else "Empty hands")

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1:
			if observer.current: actor.camera.make_current()
			else: observer.make_current()
		KEY_F2:
			selected = (selected + 1) % ITEMS.size()
			_equip()
		KEY_F3: moving = not moving
		KEY_F4: actor.camera.rotation.x = -.4 if actor.camera.rotation.x > .3 else actor.camera.rotation.x + .4
		KEY_F5:
			hand_closeup = not hand_closeup
			observer.make_current()
			if not hand_closeup:
				observer.position = Vector3(2.1, 1.8, -2.8)
				observer.look_at(Vector3(0, 1.15, 0))
		KEY_F6: hand_angle = (hand_angle + 1) % 4

func _process(_delta: float) -> void:
	if not hand_closeup or not is_instance_valid(actor.held_item_node): return
	var carry: Node = actor.get_node("Visuals/Carry")
	var target: Vector3 = carry.grip_right
	if carry.left_weight > .5: target = (target + carry.grip_left) * .5
	var angle := hand_angle * PI / 2.0 + PI / 4.0
	observer.global_position = target + Vector3(cos(angle) * .6, .25, sin(angle) * .6)
	observer.look_at(target)

func _physics_process(delta: float) -> void:
	# In-place visual sampling keeps both views framed; gameplay movement is
	# covered separately by test_player_carry with real controller input.
	if moving:
		phase += delta
		var driver: Node = actor.get_node("Visuals/Locomotion")
		driver._select("jog_forward", 0)
		driver.animation.seek(fmod(phase, driver.animation.current_animation_length), true)
