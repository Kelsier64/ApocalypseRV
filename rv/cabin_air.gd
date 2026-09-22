extends Node3D
## Weather exclusion belongs to the roof, independently of lighting equipment.
var clear_air: FogVolume
func _ready() -> void:
	if not ForestFog.supported(): return
	clear_air = FogVolume.new()
	clear_air.size = Vector3(3.7, 2.6, 11.4)
	clear_air.position = Vector3(0, -1.35, 0)
	var air := FogMaterial.new()
	air.density = -1.0
	clear_air.material = air
	add_child(clear_air)
func _process(_delta: float) -> void:
	if is_instance_valid(clear_air): clear_air.visible = get_parent().can_operate()
