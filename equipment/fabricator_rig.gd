@tool
extends Node3D
## Expanding mast sections and independent X/Z carriages (Y is Godot height).
const MAST = preload("res://assets/models/fabricator/fabricator_mast.glb")
var _sections: Array[Node3D] = []
var _collision_ready := false

func _ready() -> void:
	set_print_pose(0.75, 0.0, AABB(), false)

func set_print_pose(surface_height: float, elapsed: float, bounds: AABB, printing: bool) -> void:
	var beam_y := maxf(0.97, surface_height + 0.22)
	$Gantry.position.y = beam_y
	var length := beam_y - 0.50
	var count := maxi(1, ceili(length / 0.40))
	while _sections.size() < count * 2:
		var stage: Node3D = MAST.instantiate()
		$Masts.add_child(stage)
		_sections.append(stage)
	for index in _sections.size():
		var tier := index / 2
		var stage := _sections[index]
		stage.visible = tier < count
		if not stage.visible: continue
		stage.position = Vector3(-0.64 if index % 2 == 0 else 0.64, 0.50 + tier * 0.40, 0.58)
		stage.scale.y = minf(0.50, length - tier * 0.40 + 0.05) / 0.50
	var center := bounds.get_center()
	$Gantry/Carriage.position.z = center.z + sin(elapsed * 1.73) * minf(bounds.size.z * 0.45, 0.49) if printing else 0.55
	$Gantry/Carriage/Head.position.x = center.x + sin(elapsed * 5.1) * minf(bounds.size.x * 0.45, 0.53) if printing else 0.54
	# Each station owns its extending root shapes; previews own no physics.
	if Engine.is_editor_hint(): return
	for side in ["Left", "Right"]:
		var collider := get_parent().get_node_or_null("MastCollision" + side) as CollisionShape3D
		if collider == null: continue
		if not _collision_ready: collider.shape = collider.shape.duplicate()
		collider.position.y = (0.5 + beam_y) * 0.5
		(collider.shape as BoxShape3D).size.y = length
	_collision_ready = true
