extends Node3D
## Standalone, fog-free inspection of the production exterior.
@export var seed_value: int = 101
@export_enum("Random:-1", "T:0", "L:1", "U:2", "H:3", "Cross:4", "Z:5", "Comb:6", "Offset:7") var template_index: int = -1

@onready var camera: Camera3D = $Camera3D
@onready var status: Label = $Interface/Status
var building: Node3D
var plan: Dictionary
var target := Vector3.ZERO
var distance := 100.0
var yaw := 0.4
var pitch := 0.2

func _ready() -> void:
	get_window().title = "Megashelter Viewer"
	_rebuild()

func _rebuild() -> void:
	if is_instance_valid(building):
		remove_child(building)
		building.free()
	plan = MegashelterPlan.generate(seed_value, template_index)
	building = POIConfig.instantiate_site({"definition_id": "modular_megashelter", "seed": seed_value, "exterior_plan": plan})
	add_child(building)
	_overview()
	status.text = "MEGASHELTER / seed %d / %s\nRMB orbit | MMB pan | Wheel zoom\n1 overall | 2 entrance | 3 roof | F5 shape | F6 random seed" % [seed_value, MegashelterPlan.FOOTPRINT_NAMES[plan.template]]

func _overview() -> void:
	_set_view(Vector3(float(plan.width) * 0.95, float(plan.height) * 0.4, float(plan.depth) * 0.5 + float(plan.height) * 1.3), Vector3(0, float(plan.height) * 0.44, 0))

func _set_view(eye: Vector3, focus: Vector3) -> void:
	target = focus
	var offset := eye - focus
	distance = offset.length()
	yaw = atan2(offset.x, offset.z)
	pitch = asin(offset.y / distance)
	_update_camera()

func _update_camera() -> void:
	pitch = clampf(pitch, -1.45, 1.45)
	distance = clampf(distance, 1.5, 350.0)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.006
			pitch += event.relative.y * 0.006
			_update_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var scale_per_pixel := distance * 0.0015
			target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * scale_per_pixel
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance *= 0.85
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance /= 0.85
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _overview()
			KEY_2: _set_view(Vector3(plan.access_point.x+16, 5, float(plan.depth) * 0.5 + 26), Vector3(plan.access_point.x, 4.2, float(plan.depth) * 0.5+2.2))
			KEY_3: _set_view(Vector3(36, float(plan.height) + 30, 45), Vector3(0, float(plan.height), 0))
			KEY_F5:
				template_index = (int(plan.template) + 1) % 8
				_rebuild()
			KEY_F6:
				seed_value = randi_range(1, 2147483646)
				template_index = -1
				_rebuild()
