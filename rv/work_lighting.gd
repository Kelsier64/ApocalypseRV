extends Node3D
var service_lamp: SpotLight3D
@onready var rv: Chassis = get_parent()
func _ready() -> void:
	service_lamp = lamp(self, Vector3(-0.48, 0.25, -5.87), 1.8, 3.0)
	service_lamp.basis = Basis.looking_at(Vector3(0, -0.03, -5.3) - service_lamp.position)
func lamp(parent: Node3D, at: Vector3, reach: float, energy: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position = at
	light.rotation.x = -PI / 2
	light.light_color = Color("efdbb0")
	light.light_energy = energy
	light.spot_range = reach
	light.spot_angle = 55
	light.shadow_enabled = true
	light.visible = false
	parent.add_child(light)
	return light
func _process(_delta: float) -> void:
	service_lamp.visible = rv.interior_powered.service and rv.engine_bay.hatch_open and rv.has_usable_power()
