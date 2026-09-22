extends Node3D
var dirty := true
var station_lights: Array[Dictionary] = []
var service_lamp: SpotLight3D
@onready var rv: Chassis = get_parent()
func _ready() -> void:
	rv.equipment_changed.connect(func(): dirty = true)
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
	if dirty:
		for entry in station_lights:
			if is_instance_valid(entry.root): entry.root.queue_free()
		station_lights.clear()
		for device in rv.get_equipment():
			if device is CraftingStation:
				var fixture := Node3D.new()
				fixture.name = "WorkLight"
				device.add_child(fixture)
				var light := lamp(fixture, Vector3(0, 1.3, 0), 2.4, 1.8)
				RoadsideKit.part(fixture, Vector3(0.4, 0.03, 0.08), Vector3(0, 1.3, 0), Color("ada58c"))
				station_lights.append({"root": fixture, "device": weakref(device), "lamp": light})
		dirty = false
	for entry in station_lights:
		var device: Equipment = entry.device.get_ref()
		if is_instance_valid(device) and is_instance_valid(entry.lamp):
			entry.lamp.visible = device.can_operate() and device.get_connected_rv() == rv and rv.interior_powered.work and rv.has_usable_power()
	service_lamp.visible = rv.interior_powered.service and rv.engine_bay.hatch_open and rv.has_usable_power()
