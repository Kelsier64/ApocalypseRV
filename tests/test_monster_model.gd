extends SceneTree
## Raker visual instances must keep damage feedback local to the injured actor.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)

func wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + ceili(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await process_frame
	return true

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
	check(skeleton != null, "Production Raker has a skeleton")
	if skeleton != null:
		for bone_name in ["spine_01", "spine_02", "spine_03", "neck_01", "neck_02", "head"]:
			check(skeleton.find_bone(bone_name) >= 0, "Face aiming and bite bone exists: " + bone_name)
		for side in ["L", "R"]:
			for bone_name in ["upper_arm", "forearm", "hand"]:
				check(skeleton.find_bone(bone_name + "_" + side) >= 0, "Grab arm bone exists: " + bone_name + "_" + side)
			for finger in ["index", "middle", "ring", "pinky"]:
				for segment in ["01", "02"]:
					check(skeleton.find_bone(finger + "_" + segment + "_" + side) >= 0, "Grab finger bone exists: " + finger + "_" + segment + "_" + side)
	check(mesh != null and mesh.skin != null, "Production Raker mesh keeps its skin")
	if mesh != null and mesh.skin != null and skeleton != null:
		check(mesh.get_node(mesh.skeleton) == skeleton, "Production Raker skin resolves to its skeleton")
		for bind in mesh.skin.get_bind_count():
			check(skeleton.find_bone(mesh.skin.get_bind_name(bind)) >= 0, "Production Raker skin binds resolve")
	check(animation.is_playing() and animation.current_animation.begins_with("game/"), "Production Raker plays a game animation")
	var original_transform := actor.transform
	actor.take_damage(2)
	check(is_equal_approx(actor.current_health, actor.max_health - 2), "Imported visual accepts damage")
	check(mesh.material_overlay != null and other_mesh.material_overlay == null, "Damage flash stays on one Raker instance")
	check(await wait_until(func(): return mesh.material_overlay == null, 1.0), "Damage flash clears before timeout")
	check(actor.transform == original_transform, "Damage flash does not move the physics actor")
	actor.loot_drops = {}
	actor.take_damage(actor.max_health)
	check(actor.is_dead, "Imported Raker can die")
	actor.set_physics_process(true)
	var actor_ref: WeakRef = weakref(actor)
	check(await wait_until(func(): return actor_ref.get_ref() == null, 3.0), "Death animation frees the visual and actor before timeout")
	world.free()
	if failures.is_empty(): print("PASS: Raker visual import, per-instance damage and death")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
