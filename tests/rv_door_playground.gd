extends "res://tests/rv_design_workshop.gd"
var crate: StaticBody3D

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Door and Socket Validation"
	rv.freeze = true
	rv.set_physics_process(false)
	for binding in [["interact", KEY_E], ["place_equipment", KEY_F]]:
		var key := InputEventKey.new()
		key.keycode = binding[1]
		InputMap.action_add_event(binding[0], key)
	await get_tree().physics_frame
	focus_door("RightMiddle", 0)

func focus_point(point: Vector3, offset: Vector3) -> void:
	if player.is_placing_equipment(): return
	player.set_physics_process(false)
	var camera: Camera3D = player.get_node("Camera3D")
	player.global_position = point + offset - Vector3.UP * camera.position.y
	camera.look_at(point)
	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func focus_door(name: String, leaf: int) -> void:
	var door := rv.get_node(name)
	var collider: Node3D = door.get_node("LeafCollision" + str(leaf))
	focus_point(collider.global_position, Vector3(2.5, 0, 0) if name == "RightMiddle" else Vector3(0, 0, 2.5))

func begin_door_move(name: String) -> void:
	if player.is_placing_equipment(): return
	var door := rv.get_node(name)
	focus_point(door.global_position, Vector3(2.5, 0, 0) if name == "RightMiddle" else Vector3(0, 0, 2.5))
	door.start_placement(player)
	player.placement.update_ghost(player)

func _process(_delta: float) -> void:
	instructions.text = "門與槽位驗收｜E 開關門；左鍵安裝／右鍵取消\nF2 側門  ·  F3 後門左扇  ·  F4 後門右扇  ·  F5 拆側門  ·  F6 障礙箱  ·  F7 拆後門\n%s" % player.placement.message

func _physics_process(_delta: float) -> void:
	if player and player.is_placing_equipment(): player.placement.update_ghost(player)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2: focus_door("RightMiddle", 0)
		KEY_F3: focus_door("RearDoor", 0)
		KEY_F4: focus_door("RearDoor", 1)
		KEY_F5: begin_door_move("RightMiddle")
		KEY_F7: begin_door_move("RearDoor")
		KEY_F6:
			if is_instance_valid(crate):
				crate.queue_free()
				crate = null
			else:
				crate = StaticBody3D.new()
				crate.name = "測試箱"
				var collision := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(0.35, 0.8, 0.5)
				collision.shape = shape
				crate.add_child(collision)
				var mesh := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = shape.size
				mesh.mesh = box
				mesh.material_override = load("res://rv/visuals/orange.tres")
				crate.add_child(mesh)
				add_child(crate)
				crate.global_position = rv.to_global(Vector3(2.0, 1.2, 0))
