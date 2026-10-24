extends Item
## Loose, held and placement wheels share the mounted wheel's mesh and dimensions.

func _ready() -> void:
	super._ready()
	_update_geometry()

func _set_condition(value: float) -> void:
	super._set_condition(value)
	_update_geometry()

func _update_geometry() -> void:
	var visual := get_node_or_null("WheelMesh") as Node3D
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if visual == null or collision == null: return
	var flat := condition <= 0.0
	var radius := Chassis.WHEEL_RADIUS * (0.8 if flat else 1.0)
	var width := Chassis.WHEEL_WIDTH * (1.15 if flat else 1.0)
	visual.scale = TireDynamics.visual_scale(radius, width)
	visual.position.y = radius
	# Grip the visible front rim, within arm reach, at either handedness.
	for side: String in ["Right", "Left"]:
		var grip := get_node_or_null("Grip" + side) as Marker3D
		if grip != null: grip.position = visual.transform * Vector3(-.228, .035, .20 if side == "Right" else -.20)
	collision.position.y = radius
	var shape := collision.shape as CylinderShape3D
	shape.radius = radius
	shape.height = width
