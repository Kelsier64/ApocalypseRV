extends Node3D
## An independent, posed limb chain. Never writes back to the living skeleton.
var skeleton: Skeleton3D
var builder: Node
var captor: Node3D
var anchor_bone := -1
var held := 0.0
var lifetime := 0.0
var launch_velocity := Vector3.ZERO
var simulated := false
var meshes: Array[MeshInstance3D] = []
var view_shadows: Array[MeshInstance3D] = []

func setup(actor: CharacterBody3D, source: Skeleton3D, root_bone: String, templates: Array[Dictionary], context: Dictionary) -> void:
	global_transform = source.global_transform
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	for i in source.get_bone_count():
		skeleton.add_bone(source.get_bone_name(i))
		skeleton.set_bone_parent(i, source.get_bone_parent(i))
		skeleton.set_bone_rest(i, source.get_bone_rest(i))
		skeleton.set_bone_pose(i, source.get_bone_pose(i))
	anchor_bone = skeleton.find_bone(root_bone)
	var selected: Array[int] = [anchor_bone]
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		while parent >= 0:
			if parent == anchor_bone:
				selected.append(i)
				break
			parent = skeleton.get_bone_parent(parent)
	for data in templates:
		var mesh := MeshInstance3D.new()
		mesh.skin = data.skin
		mesh.mesh = _independent_mesh(data.mesh, data.skin, selected, anchor_bone)
		mesh.skeleton = NodePath("..")
		mesh.transform = data.transform
		skeleton.add_child(mesh)
		meshes.append(mesh)
	launch_velocity = actor.velocity
	if actor.locomotion_state == actor.LocomotionState.CLIMBING: launch_velocity = actor.climb_carrier_velocity
	elif is_instance_valid(actor.seated_in):
		var rv := ClimbMath.find_rv_ancestor(actor.seated_in)
		if rv is RigidBody3D: launch_velocity = rv.linear_velocity + rv.angular_velocity.cross(global_position - rv.global_position)
	elif is_instance_valid(actor.rv_support.rv): launch_velocity += actor.rv_support.carrier_velocity
	else: launch_velocity += Vector3(actor.released_carrier_velocity.x, 0, actor.released_carrier_velocity.z)
	# A multi-cut blast captures motion once before any cut changes seat/support.
	if context.get("launch_velocity") is Vector3 and context.launch_velocity.is_finite():
		launch_velocity = context.launch_velocity
	if context.get("blast_impulse") is Vector3 and context.blast_impulse.is_finite():
		launch_velocity += context.blast_impulse
	captor = context.get("captor")
	# Raker retains its brief mouth grip; crushing releases independent parts
	# directly at their posed location instead of using a Raker mouth solver.
	held = .25 if is_instance_valid(captor) and bool(context.get("hold_in_mouth", true)) else 0.0
	# Defer physical-body mutation if the bite arrived during physics queries.
	_prepare_physics.call_deferred(actor, root_bone)

func camera_anchor_position() -> Vector3:
	# Use the same collider center before and after the deferred physics setup.
	# The effect root stops moving once its independent physical bone takes over.
	if simulated and builder != null:
		return builder.bodies["head"].global_position
	var pose := skeleton.get_bone_global_pose(anchor_bone)
	var center := skeleton.get_bone_global_rest(anchor_bone).affine_inverse() * preload("res://player/player_ragdoll.gd").HEAD_CENTER
	return skeleton.global_transform * pose * center

func set_camera_hidden(hidden: bool) -> void:
	# Only the local first-person camera excludes layer 18. The head remains
	# visible to observers, and regains its normal layer when the player respawns.
	if hidden and view_shadows.is_empty():
		for mesh in meshes:
			var shadow := MeshInstance3D.new()
			shadow.mesh = mesh.mesh
			shadow.skin = mesh.skin
			shadow.skeleton = mesh.skeleton
			shadow.transform = mesh.transform
			shadow.layers = PlayerModelVisual.LOCAL_VIEW_LAYER
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			skeleton.add_child(shadow)
			view_shadows.append(shadow)
	for mesh in meshes: mesh.layers = PlayerModelVisual.FULL_BODY_LAYER if hidden else 1
	for shadow in view_shadows: shadow.visible = hidden

func _prepare_physics(actor: CharacterBody3D, root_bone: String) -> void:
	if not is_instance_valid(actor): queue_free(); return
	builder = preload("res://player/player_ragdoll.gd").new()
	builder.player = actor
	builder.skeleton = skeleton
	builder.simulator = PhysicalBoneSimulator3D.new()
	skeleton.add_child(builder.simulator)
	var selected: Array[String] = [root_bone]
	if root_bone.begins_with("upper_arm"): selected.append("forearm_" + root_bone.right(1))
	if root_bone.begins_with("thigh"): selected.append_array(["shin_" + root_bone.right(1), "foot_" + root_bone.right(1)])
	builder.allowed_bones.assign(selected)
	var pose: Array[Transform3D] = []
	for i in skeleton.get_bone_count(): pose.append(skeleton.get_bone_pose(i))
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	builder.build_bodies()
	builder.bodies[root_bone].joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	for body: PhysicalBone3D in builder.bodies.values(): body.collision_layer = 0; body.collision_mask = 0
	for i in skeleton.get_bone_count(): skeleton.set_bone_pose(i, pose[i])
	skeleton.force_update_all_bone_transforms()
	if held <= 0: _release()

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime >= 24.0: queue_free(); return
	if held > 0:
		held -= delta
		if is_instance_valid(captor) and WorldEntities.same_world(self, captor) and not captor.is_dead:
			var visuals: Node3D = captor.get_node("BodyMesh")
			# SkeletonModifier restores its input outside evaluation. Follow the
			# cached rendered mouth, not the unmodified animation's head position.
			var mouth: Vector3 = visuals.bone_world_position("mouth") if visuals.pose_modifier.world_positions.has("mouth") else visuals.skeleton.to_global(visuals.pose_modifier.mouth_position(visuals.skeleton))
			var anchor := skeleton.global_transform * skeleton.get_bone_global_pose(anchor_bone).origin
			global_position += mouth - anchor
		else: held = 0
		if held <= 0 and builder != null: _release()
	if lifetime > 22.0:
		for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false): mesh.transparency = (lifetime - 22.0) / 2.0

func _release() -> void:
	if simulated or builder == null: return
	simulated = true
	skeleton.force_update_all_bone_transforms()
	for body: PhysicalBone3D in builder.bodies.values():
		body.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(body.get_bone_id()) * body.body_offset
		body.collision_layer = 128
		body.collision_mask = 1 # Decorative limbs do not obstruct or push the player/RV.
	builder.simulator.physical_bones_start_simulation()
	for body: PhysicalBone3D in builder.bodies.values():
		body.linear_velocity = launch_velocity + Vector3(0, -.2, 0)
		body.angular_velocity = Vector3(.5, .3, -.4)

func _independent_mesh(source: Mesh, skin: Skin, selected: Array[int], fallback: int) -> ArrayMesh:
	var fallback_bind := 0
	var valid: Array[int] = []
	for i in skin.get_bind_count():
		var bone := skeleton.find_bone(skin.get_bind_name(i))
		if bone in selected: valid.append(i)
		if bone == fallback: fallback_bind = i
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for v in vertices.size():
			# Rebind exterior influences into the detached ancestor while retaining
			# their exact current posed position (no shoulder stretching or snap).
			var original := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
			var replacement := original
			for j in 4:
				var index := v * 4 + j
				var bind := bones[index]
				var bone := skeleton.find_bone(skin.get_bind_name(bind))
				var deformation := skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind)
				original.basis = Basis(original.basis.x + deformation.basis.x * weights[index], original.basis.y + deformation.basis.y * weights[index], original.basis.z + deformation.basis.z * weights[index])
				original.origin += deformation.origin * weights[index]
				if bind not in valid: bones[index] = fallback_bind
				var new_bone := skeleton.find_bone(skin.get_bind_name(bones[index]))
				deformation = skeleton.get_bone_global_pose(new_bone) * skin.get_bind_pose(bones[index])
				replacement.basis = Basis(replacement.basis.x + deformation.basis.x * weights[index], replacement.basis.y + deformation.basis.y * weights[index], replacement.basis.z + deformation.basis.z * weights[index])
				replacement.origin += deformation.origin * weights[index]
			var correction := replacement.affine_inverse() * original
			vertices[v] = correction * vertices[v]
			normals[v] = (correction.basis.inverse().transposed() * normals[v]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bones
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result

func _exit_tree() -> void:
	if is_instance_valid(builder): builder.free()
