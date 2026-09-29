extends SceneTree
## Raker visual instances must keep damage feedback local to the injured actor.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var scene := load("res://enemies/raker.tscn") as PackedScene
	var actor: Monster = scene.instantiate()
	var other: Monster = scene.instantiate()
	world.add_child(actor)
	world.add_child(other)
	actor.set_physics_process(false)
	other.set_physics_process(false)
	var visual: Node3D = actor.get_node("BodyMesh")
	var model: Node3D = visual.get_node("Model")
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var mesh: MeshInstance3D = model.find_child("Raker_Mesh", true, false)
	var other_mesh: MeshInstance3D = other.get_node("BodyMesh/Model").find_child("Raker_Mesh", true, false)
	var animation: AnimationPlayer = model.get_node("AnimationPlayer")
	check(skeleton != null and skeleton.get_bone_count() == 54, "Production Raker skeleton imports with 54 bones")
	check(mesh != null and mesh.skin != null, "Production Raker mesh keeps its skin")
	check(animation.is_playing() and animation.current_animation.begins_with("game/"), "Production Raker plays a game animation")
	var original_transform := actor.transform
	actor.take_damage(2)
	check(is_equal_approx(actor.current_health, actor.max_health - 2), "Imported visual accepts damage")
	check(mesh.material_overlay != null and other_mesh.material_overlay == null, "Damage flash stays on one Raker instance")
	await create_timer(0.25).timeout
	check(mesh.material_overlay == null and actor.transform == original_transform, "Flash clears without moving the physics actor")
	actor.loot_drops = {}
	actor.take_damage(actor.max_health)
	check(actor.is_dead, "Imported Raker can die")
	actor.set_physics_process(true)
	await create_timer(2.2).timeout
	check(not is_instance_valid(actor), "Death animation eventually frees the visual and actor")
	world.free()
	if failures.is_empty(): print("PASS: Raker visual import, per-instance damage and death")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
