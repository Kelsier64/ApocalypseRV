extends SceneTree
## Imported asset contract, animation drift, and per-instance damage feedback.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var scene := load("res://enemies/zombie.tscn") as PackedScene
	var actor: Monster = scene.instantiate()
	var other: Monster = scene.instantiate()
	world.add_child(actor)
	world.add_child(other)
	actor.set_physics_process(false)
	other.set_physics_process(false)
	var visual: Node3D = actor.get_node("BodyMesh")
	var model: Node3D = visual.get_node("Model")
	var skeleton: Skeleton3D = model.get_node("MONSTER_Rig/Skeleton3D")
	var mesh: MeshInstance3D = skeleton.get_node("MONSTER_Mesh")
	var animation: AnimationPlayer = model.get_node("AnimationPlayer")
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(skeleton.get_bone_count() == 45, "All 45 deform bones survive import")
	check(mesh.skin != null and mesh.mesh.get_surface_count() == 2, "Skin and both material surfaces survive import")
	check(absf(mesh.get_aabb().size.y - 2.18) < 0.001, "Source height remains 2.18 m")
	var bounds := model.transform * mesh.get_aabb()
	check(absf(bounds.size.y - 1.5) < 0.001, "Presentation fits the existing capsule height")
	check(absf(visual.position.y + bounds.position.y - 0.25) < 0.001, "Model feet align with capsule bottom")
	check((model.basis * Vector3.BACK).normalized().is_equal_approx(Vector3.FORWARD), "Source +Z faces actor -Z")
	var original_transform := actor.transform
	var root_bone := skeleton.find_bone("root")
	for frame in range(360):
		animation.advance(1.0 / 60.0)
		check(skeleton.get_bone_pose_position(root_bone).length() < 0.0001, "In-place loop has no root displacement")
	check(animation.is_playing() and animation.current_animation == "preview/idle", "Preview keeps looping past three cycles")
	check(actor.transform == original_transform, "Animation never moves the physics actor")
	var root_motion := animation.get_animation("TEST_RootMotion")
	var root_track := root_motion.find_track(NodePath("MONSTER_Rig/Skeleton3D:root"), Animation.TYPE_POSITION_3D)
	check(root_track >= 0, "Root-motion test remains available for future integration")
	if root_track >= 0:
		var start: Vector3 = root_motion.track_get_key_value(root_track, 0)
		var end: Vector3 = root_motion.track_get_key_value(root_track, root_motion.track_get_key_count(root_track) - 1)
		check((end - start).distance_to(Vector3.BACK) < 0.0001, "Root-motion clip preserves source 1 m displacement")
	var other_mesh: MeshInstance3D = other.get_node("BodyMesh/Model/MONSTER_Rig/Skeleton3D/MONSTER_Mesh")
	actor.take_damage(1)
	actor.take_damage(1)
	check(actor.current_health == actor.max_health - 2, "Imported visual still accepts repeated damage")
	check(mesh.material_overlay != null and other_mesh.material_overlay == null, "Damage flash stays on the damaged instance")
	await create_timer(0.25).timeout
	check(mesh.material_overlay == null, "Damage flash clears without altering source materials")
	actor.loot_drops = {}
	actor.take_damage(actor.max_health)
	check(actor.is_dead, "Imported actor still dies")
	await create_timer(0.4).timeout
	check(not is_instance_valid(actor), "Death cleans up the imported skeleton and visual")
	world.free()
	if failures.is_empty():
		print("PASS: monster model import, alignment, loop, root-motion data, damage and death")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
