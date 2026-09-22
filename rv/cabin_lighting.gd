extends Node3D
## Each installed light strip follows the console request and energy grant.
var lamps: Array[SpotLight3D] = []
var lenses: Array[StandardMaterial3D] = []
func _ready() -> void:
	var light := SpotLight3D.new()
	light.position = Vector3(0, -0.045, 0)
	light.rotation.x = -PI * 0.5
	light.light_color = Color("efd3a2")
	light.light_energy = 2.0
	light.spot_range = 4.0
	light.spot_angle = 68.0
	light.shadow_enabled = true
	light.distance_fade_enabled = true
	light.distance_fade_begin = 15.0
	light.distance_fade_length = 10.0
	add_child(light)
	lamps.append(light)
	var lens := RoadsideKit.part(self, Vector3(1.12, 0.008, 0.08), Vector3(0, -0.034, 0), Color("ada58c"))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ada58c")
	mat.emission_enabled = true
	mat.emission = Color("efd3a2")
	lens.material_override = mat
	lenses.append(mat)

func _process(_delta: float) -> void:
	var strip := get_parent() as Equipment
	var rv := strip.get_connected_rv() as Chassis
	var powered: bool = rv != null and strip.can_operate() and rv.has_usable_power() and rv.interior_powered.cabin
	for lamp in lamps: lamp.visible = powered
	for lens in lenses: lens.emission_energy_multiplier = 0.65 if powered else 0.0
