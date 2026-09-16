extends Node3D
var rv: Node3D
var lamps: Dictionary = {}
func _ready() -> void:
	rv = get_parent()
	for side in [-1.0, 1.0]:
		_make_lamp("head" + str(side), Vector3(side * 1.53, 0.13, -6.02), Color(1, 0.96, 0.8), true, false)
		_make_lamp("tail" + str(side), Vector3(side * 1.72, 0.08, 6.03), Color(1, 0.08, 0.03), false, true)
		_make_lamp("reverse" + str(side), Vector3(side * 1.42, 0.08, 6.03), Color(0.95, 1, 1), false, true)
func _make_lamp(key: String, at: Vector3, tint: Color, beam: bool, rear: bool) -> void:
	var lens := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.16, 0.06)
	lens.mesh = mesh
	lens.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = tint * 0.25
	material.emission_enabled = true
	material.emission = tint
	lens.material_override = material
	add_child(lens)
	var light := SpotLight3D.new()
	light.position = at + Vector3(0, 0, 0.05 if rear else -0.05)
	light.rotation.y = PI if rear else 0.0
	light.spot_range = 32.0 if beam else 6.0
	light.spot_angle = 40.0 if beam else 65.0
	light.light_color = tint
	light.shadow_enabled = beam
	add_child(light)
	lamps[key] = {"material": material, "light": light}
func _process(_delta: float) -> void:
	for key in lamps:
		var strength := 0.0
		if rv.lamps_powered:
			if key.begins_with("head"): strength = 2.5 if rv.headlights_requested else 0.0
			elif key.begins_with("reverse"): strength = 1.5 if rv.gear < 0 else 0.0
			else: strength = 2.0 if rv.handbrake or rv.brake_input > 0.0 else (0.5 if rv.headlights_requested else 0.0)
		lamps[key].material.emission_energy_multiplier = strength
		lamps[key].light.light_energy = strength
		lamps[key].light.visible = strength > 0.0
