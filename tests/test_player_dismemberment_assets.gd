extends SceneTree
## Geometry/pose/physics contract rather than implementation-shaped mocks.
const PLAYER = preload("res://player/player.tscn")
var failures: Array[String] = []
var arena: Node3D

func _init() -> void: run.call_deferred()
func check(ok: bool, reason: String) -> void:
	if not ok and reason not in failures: failures.append(reason)
func steps(count: int) -> void:
	for i in count: await physics_frame; await process_frame

func posed(mesh: Mesh, skin: Skin, sk: Skeleton3D, surface: int, index: int) -> Vector3:
	var data := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = data[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = data[Mesh.ARRAY_WEIGHTS]
	var point := Vector3.ZERO
	for j in 4:
		var offset := index * 4 + j
		var bind := bones[offset]
		var bone := sk.find_bone(skin.get_bind_name(bind))
		point += (sk.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * vertices[index]) * weights[offset]
	return sk.global_transform * point

func area(mesh: Mesh) -> float:
	var total := 0.0
	for surface in mesh.get_surface_count():
		var data := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			total += (vertices[indices[i+1]] - vertices[indices[i]]).cross(vertices[indices[i+2]] - vertices[indices[i]]).length() * .5
	return total

func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	arena.add_child(floor)
	var actor: CharacterBody3D = PLAYER.instantiate()
	arena.add_child(actor)
	await steps(3)
	var visual: PlayerModelVisual = actor.get_node("Visuals")
	var damage: Node = visual.dismemberment
	var triangles := 0
	var partition_area := 0.0
	var original_area := 0.0
	for mesh: MeshInstance3D in visual.source_meshes: original_area += area(mesh.mesh)
	for template: Dictionary in damage.templates:
		if template.role != "Part": continue
		var mesh: ArrayMesh = template.mesh
		partition_area += area(mesh)
		for surface in mesh.get_surface_count(): triangles += mesh.surface_get_array_index_len(surface) / 3
	check(absf(partition_area - original_area) / original_area < .00001, "Neck subdivision preserves surface area within glTF floating-point precision (0.001%)")
	print("PARTITION_TRIANGLES ", triangles, " AREA_DELTA ", absf(partition_area - original_area))
	check(visual.skeleton.get_bone_count() == 41, "Accepted production deform skeleton remains unchanged")
	for part: StringName in PlayerBodyState.PARTS:
		var caps: Array = damage.templates.filter(func(t: Dictionary): return t.part == String(part) and t.role == "Cap")
		var wounds: Array = damage.templates.filter(func(t: Dictionary): return t.part == String(part) and t.role == "Wound")
		check(not caps.is_empty() and caps.size() == wounds.size(), "Paired caps close both sides: " + part)
		for template: Dictionary in caps + wounds:
			check(template.mesh.get_surface_count() == 4, "Cloth, muscle, bone and marrow surfaces: " + part)
		if part == &"head":
			check(caps.size() == 1, "One closed neck surface replaces overlapping collar cap fans")
			for template: Dictionary in caps + wounds:
				for surface in template.mesh.get_surface_count():
					for vertex: Vector3 in template.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						check(absf(vertex.y - 1.36) <= .0031, "Neck cap stays inside its shallow cut plane, with no shoulder spikes")
	# A bent shoulder must keep its exact visible shape when exterior skin
	# influences are transferred to the independent limb's root bone.
	actor.set_physics_process(false)
	var driver: Node = visual.get_node("Locomotion")
	driver.set_physics_process(false)
	visual.get_node("Carry").set_physics_process(false)
	# Check actual evaluated joint geometry, not just the existence of tracks.
	# Omitted constant glTF channels must preserve segment lengths on retarget.
	var donor := preload("res://assets/models/player_dismemberment/player_injury_animations.glb").instantiate()
	arena.add_child(donor)
	var donor_skeleton := donor.find_child("Skeleton3D", true, false) as Skeleton3D
	var donor_animation := donor.get_node("AnimationPlayer") as AnimationPlayer
	donor_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in driver.animation.get_animation_library("injury").get_animation_list():
		for phase in [0.0, .25, .5, .75]:
			donor_skeleton.reset_bone_poses()
			donor_animation.play(clip, 0)
			donor_animation.seek(donor_animation.get_animation(clip).length * phase, true)
			driver.animation.play("injury/" + clip, 0)
			driver.animation.seek(driver.animation.get_animation("injury/" + clip).length * phase, true)
			donor_skeleton.force_update_all_bone_transforms()
			visual.skeleton.force_update_all_bone_transforms()
			for name in ["pelvis", "spine_02", "upper_arm_L", "forearm_L", "hand_L", "hand_R", "foot_L", "foot_R"]:
				var actual := visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone(name))
				var expected_pose := donor_skeleton.get_bone_global_pose(donor_skeleton.find_bone(name))
				check(actual.origin.distance_to(expected_pose.origin) < .001, "Crawl retarget preserves authored joint positions: " + clip + "/" + name)
			for side in ["L", "R"]:
				var wrist := visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("hand_" + side)).origin
				check(wrist.y > .045 and wrist.y < .15 and wrist.z > .19, "Crawl palms remain close to floor and forward of chest: " + clip)
	donor.free()
	driver.animation.play("locomotion/jog_left", 0)
	driver.animation.advance(.18)
	visual.skeleton.force_update_all_bone_transforms()
	var expected: Array[Dictionary] = []
	for t: Dictionary in damage.templates:
		if t.part == "left_arm" and t.role in ["Part", "Cap"]: expected.append(t)
	actor.sever_part(&"left_arm")
	var effect: Node = get_nodes_in_group("player_detached_parts").back()
	var meshes: Array[Node] = effect.skeleton.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == expected.size(), "Detached limb contains its exact visible pieces and end cap")
	var largest_error := 0.0
	for m in meshes.size():
		for surface in meshes[m].mesh.get_surface_count():
			var vertices: PackedVector3Array = meshes[m].mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for index in range(0, vertices.size(), 7):
				var before := posed(expected[m].mesh, expected[m].skin, visual.skeleton, surface, index)
				var after := posed(meshes[m].mesh, meshes[m].skin, effect.skeleton, surface, index)
				largest_error = maxf(largest_error, before.distance_to(after))
	check(largest_error < .0005, "Independent skin preserves current pose within 0.5 mm")
	await steps(4)
	check(effect.simulated and effect.builder.bodies.size() == 2, "Arm is a live two-body physics chain")
	check(effect.builder.bodies["upper_arm_L"].joint_type == PhysicalBone3D.JOINT_TYPE_NONE, "Detached root has no joint to an invisible torso")
	actor.take_damage(1000)
	await steps(4)
	check(actor.ragdoll_control.bodies.size() == 12 and not actor.ragdoll_control.bodies.has("upper_arm_L"), "Death does not recreate missing-arm physical bodies")
	await steps(130)
	# Repeat the reported case: a severed head must stay rigid after it lands.
	actor.sever_part(&"head")
	var head: Node = get_nodes_in_group("player_detached_parts").back()
	var head_meshes: Array[Node] = head.skeleton.find_children("*", "MeshInstance3D", true, false)
	var rigid_points: Array[Dictionary] = []
	var head_frame: Transform3D = head.skeleton.global_transform * head.skeleton.get_bone_global_pose(head.anchor_bone)
	for mesh: MeshInstance3D in head_meshes:
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for index in range(0, vertices.size(), 11):
				rigid_points.append({"mesh":mesh,"surface":surface,"index":index,"local":head_frame.affine_inverse()*posed(mesh.mesh,mesh.skin,head.skeleton,surface,index)})
	await steps(240)
	head_frame = head.skeleton.global_transform * head.skeleton.get_bone_global_pose(head.anchor_bone)
	var head_error := 0.0
	for point in rigid_points:
		var actual := posed(point.mesh.mesh, point.mesh.skin, head.skeleton, point.surface, point.index)
		head_error = maxf(head_error, actual.distance_to(head_frame * point.local))
	check(head.simulated and head.builder.bodies.size() == 1 and head_error < .0005, "Landed head keeps a rigid closed shape within 0.5 mm")
	print("LANDED_HEAD_RIGID_ERROR_M ", head_error)
	check(not get_nodes_in_group("player_blood_stains").is_empty(), "Severing creates surface blood")
	await steps(2900)
	check(get_nodes_in_group("player_blood_stains").is_empty(), "Blood shader opacity fades and stains are reclaimed within 48 seconds")
	print("DISMEMBERMENT_ASSET_POSE_ERROR_M ", largest_error)
	for failure in failures: push_error(failure)
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: complete partition, paired wound caps, exact posed detach and missing-limb physics")
	quit(0 if failures.is_empty() else 1)
