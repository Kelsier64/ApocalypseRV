extends Node3D
@export var monster_scene: PackedScene = preload("res://enemies/zombie.tscn")
## Real actors and attack cooldowns; extra player health allows prolonged inspection.
var player: CharacterBody3D
var monster: Monster
var device: Equipment
var barrier: StaticBody3D
var status: Label

func box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	return visual

func solid(point: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.add_child(box_mesh(size, color))
	add_child(body)
	body.position = point
	return body

func _ready() -> void:
	DisplayServer.window_set_title("Monster Pursuit Validation")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.16, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	solid(Vector3(0, -0.1, 0), Vector3(30, 0.2, 20), Color(0.28, 0.32, 0.3))
	player = preload("res://player/player.tscn").instantiate()
	add_child(player)
	player.current_player_health = 10000
	player.in_ui_mode = true
	player.position = Vector3(4, -0.25, 0)
	var player_marker := box_mesh(Vector3(0.6, 1.6, 0.6), Color(0.2, 0.55, 0.95))
	player.add_child(player_marker)
	player_marker.position.y = 1.1
	monster = monster_scene.instantiate()
	add_child(monster)
	monster.position = Vector3(-4, -0.25, 0)
	monster.is_idle = true
	monster.idle_timer = 30
	device = Equipment.new()
	device.freeze = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	shape.shape = sphere
	device.add_child(shape)
	device.add_child(box_mesh(Vector3.ONE * 0.3, Color(0.9, 0.65, 0.2)))
	add_child(device)
	device.position = Vector3(2.5, 0.7, 0.7)
	device.current_health = 10000
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 7, 12)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(20, 110)
	status.add_theme_font_size_override("font_size", 22)
	canvas.add_child(status)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			if is_instance_valid(barrier): barrier.free()
			player.position = Vector3(4, -0.25, 0)
			monster.position = Vector3(2.5, -0.25, 0)
			monster.velocity = Vector3.ZERO
			monster.move_speed = 0
			barrier = solid(Vector3(3.25, 1.5, 0), Vector3(0.2, 3, 4), Color(0.3, 0.45, 0.65))
		if event.keycode == KEY_F4 and is_instance_valid(barrier): barrier.free()

func _process(_delta: float) -> void:
	status.text = "PRODUCTION ZOMBIE / PLAYER\nPlayer HP: %.0f | Device HP: %.0f\nAI: %s | Player damage cooldown: %.2f\nUI movement lock active; damage must keep ticking.\nF3: wall between actors (movement held) | F4: remove wall\nPlayer health boosted for inspection; attack damage/cooldowns unchanged." % [player.current_player_health, device.current_health, Monster.State.keys()[monster.ai_state], player.damage_cooldown]
