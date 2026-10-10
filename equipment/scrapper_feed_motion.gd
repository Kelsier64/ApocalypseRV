extends RefCounted
## Conservative full-size containment; cutting happens only below the roller plane.
const CUT_SHADER = preload("res://equipment/scrapper_cut.gdshader")
const HALF_OPENING := .435
var start_pose := Transform3D.IDENTITY
var pose := Transform3D.IDENTITY
var bounds := AABB()
var surfaces: Array[Dictionary] = []
var ready := false
var physical := false
var complete := true
var pieces: Array[Dictionary] = []
var section_feed: RefCounted
var initial_bones: Dictionary = {}
var initial_offsets: Dictionary = {}

static func geometry_bounds(prop: Node3D) -> AABB:
	var points: Array[Vector3] = []
	if prop is CorpseProp and prop.initialized:
		for bone: PhysicalBone3D in prop.bodies.values():
			for shape: CollisionShape3D in bone.find_children("*", "CollisionShape3D", true, false):
				_append_box(points, shape.shape.get_debug_mesh().get_aabb(), prop.global_transform.affine_inverse() * shape.global_transform)
	else:
		_collect_geometry(prop, Transform3D.IDENTITY, points)
	if points.is_empty(): return AABB(Vector3(-.05,-.05,-.05),Vector3(.1,.1,.1))
	var box := AABB(points[0], Vector3.ZERO)
	for point in points: box = box.expand(point)
	return box

static func _collect_geometry(node: Node, frame: Transform3D, points: Array[Vector3]) -> void:
	if node is MeshInstance3D and node.visible and node.mesh != null: _append_box(points, node.get_aabb(), frame)
	if node is CollisionShape3D and not node.disabled and node.shape != null: _append_box(points, node.shape.get_debug_mesh().get_aabb(), frame)
	for child in node.get_children():
		_collect_geometry(child, frame * child.transform if child is Node3D else frame, points)

static func _append_box(points: Array[Vector3], box: AABB, frame: Transform3D) -> void:
	for i in 8: points.append(frame * box.get_endpoint(i))

static func rotated_box(box: AABB, basis: Basis) -> AABB:
	var result := AABB(basis * box.get_endpoint(0), Vector3.ZERO)
	for i in 8: result = result.expand(basis * box.get_endpoint(i))
	return result

static func admissible(prop: Node3D, owner: Node3D) -> bool:
	var box := rotated_box(geometry_bounds(prop),owner.global_basis.inverse()*prop.global_basis)
	box.position += owner.to_local(prop.global_position)
	var center := box.get_center()
	if absf(center.x) > .30 or absf(center.z) > .30: return false
	var contained := box.position.x >= -HALF_OPENING and box.end.x <= HALF_OPENING and box.position.z >= -HALF_OPENING and box.end.z <= HALF_OPENING
	# An oversized object must approach from above; wall grazes keep physics.
	return contained or box.position.y >= .68

static func fits(prop: Node3D, owner: Node3D) -> bool:
	var box := geometry_bounds(prop)
	var basis := owner.global_basis.inverse() * prop.global_basis
	var size := rotated_box(box,basis).size
	return size.x <= HALF_OPENING * 2 and size.z <= HALF_OPENING * 2

func setup(prop: Node3D, owner: Node3D, saved: Dictionary = {}) -> bool:
	if prop is CorpseProp and not prop.initialized: return false
	bounds = geometry_bounds(prop)
	start_pose = owner.global_transform.affine_inverse() * prop.global_transform
	if not saved.is_empty(): start_pose = saved.start; pose = saved.pose
	else: pose = start_pose
	physical = prop is CorpseProp
	complete = not physical
	if physical:
		for key: String in prop.bodies:
			initial_bones[key] = owner.global_transform.affine_inverse()*prop.bodies[key].global_transform
			initial_offsets[key] = prop.bodies[key].body_offset.affine_inverse()
	else:
		var size := rotated_box(bounds, start_pose.basis).size
		if size.x > HALF_OPENING * 2 or size.z > HALF_OPENING * 2:
			var box := rotated_box(bounds,start_pose.basis)
			start_pose.origin.y += maxf(0,.87-start_pose.origin.y-box.position.y)
			pose = start_pose
			prop.global_transform = owner.global_transform*pose
			section_feed = load("res://equipment/scrapper_section_feed.gd").new()
			section_feed.setup(prop,owner,bounds,start_pose)
			pieces = section_feed.pieces
			section_feed.advance(owner,float(saved.get("progress",0)))
	if section_feed == null: surfaces = apply_cut(prop, owner)
	ready = true
	return true

func advance(prop: Node3D, owner: Node3D, progress: float, delta: float = 0.0) -> void:
	if section_feed != null:
		section_feed.advance(owner,progress)
		return
	if physical:
		if delta <= 0: return
		prop.begin_physical_feed()
		var swallowed: Array[String] = []
		complete = prop.bodies.is_empty()
		for bone: PhysicalBone3D in prop.bodies.values():
			var local := owner.to_local(bone.global_position)
			var contained := true
			var top := -INF
			var bottom := INF
			for shape: CollisionShape3D in bone.find_children("*","CollisionShape3D",true,false):
				var frame := owner.global_transform.affine_inverse()*shape.global_transform
				var box := shape.shape.get_debug_mesh().get_aabb()
				for i in 8:
					var point: Vector3 = frame*box.get_endpoint(i)
					contained = contained and absf(point.x) <= HALF_OPENING and absf(point.z) <= HALF_OPENING
					top = maxf(top,point.y)
					bottom = minf(bottom,point.y)
			# Only a bone fully inside the opening may pass through the teeth.
			if contained and bottom < .79:
				bone.collision_mask = 0
				bone.collision_layer = 0
				prop.sever_feed_segment.call_deferred(String(bone.bone_name))
			elif not contained:
				bone.collision_mask = 1
				bone.collision_layer = 128
			if contained and top < .705: swallowed.append(String(bone.bone_name))
			var target := owner.to_global(Vector3(0,.12,0) if contained else Vector3(0,1.55,0))
			var desired := ((target-bone.global_position)*4.0).limit_length(2.0)
			bone.linear_velocity = bone.linear_velocity.lerp(desired,1.0-exp(-12.0*delta))
			# Once the teeth sever a segment, turn its long collider axis down the
			# throat. A sideways shin otherwise balances across both rim edges.
			if bone.joint_type == PhysicalBone3D.JOINT_TYPE_NONE:
				var rotation := (owner.global_basis.orthonormalized()*bone.global_basis.orthonormalized().inverse()).get_rotation_quaternion().normalized()
				if rotation.w < 0: rotation = -rotation
				bone.angular_velocity = bone.angular_velocity.lerp(rotation.get_axis()*minf(rotation.get_angle()*5.0,4.0),1.0-exp(-10.0*delta))
		if not swallowed.is_empty(): prop.consume_feed_bones.call_deferred(swallowed)
		pose = owner.global_transform.affine_inverse()*prop.global_transform
		update_cut(surfaces,owner)
		return
	var amount := smoothstep(0.0,.9, progress)
	var rock := sin(progress * TAU * 2.5) * .22 * sin(progress * PI)
	var turn := Basis(Vector3.UP, progress * .85) * Basis(Vector3.FORWARD, rock) * Basis(Vector3.RIGHT, sin(progress * PI) * .18)
	var basis := turn * start_pose.basis
	# Reduce rotation until the full-sized transformed footprint fits the opening.
	for attempt in 8:
		var proposed := rotated_box(bounds,basis)
		if proposed.size.x <= HALF_OPENING*2 and proposed.size.z <= HALF_OPENING*2: break
		turn = Basis(Quaternion.IDENTITY.slerp(turn.get_rotation_quaternion(), .5))
		basis = turn * start_pose.basis
	var proposed := rotated_box(bounds,basis)
	if proposed.size.x > HALF_OPENING*2 or proposed.size.z > HALF_OPENING*2: basis = start_pose.basis
	var box := rotated_box(bounds,basis)
	var start_box := rotated_box(bounds,start_pose.basis)
	var center := start_pose.origin + start_box.get_center()
	center.x = lerpf(center.x, sin(progress * TAU * 3) * .022, amount)
	center.z = lerpf(center.z, cos(progress * TAU * 2) * .018, amount)
	center.x = clampf(center.x,-HALF_OPENING+box.size.x*.5,HALF_OPENING-box.size.x*.5)
	center.z = clampf(center.z,-HALF_OPENING+box.size.z*.5,HALF_OPENING-box.size.z*.5)
	# First the teeth catch and rock, then consume slices through a fixed plane.
	var feed := smoothstep(.12,1.0,progress)
	center.y = lerpf(center.y,.68-box.size.y*.5,feed)
	pose = Transform3D(basis,center-box.get_center())
	prop.global_transform = owner.global_transform * pose
	update_cut(surfaces,owner)

func release(prop: Node3D, owner: Node3D) -> void:
	# Restore the last unconsumed full-size pose before re-enabling colliders.
	if physical:
		for key: String in initial_bones:
			if prop.bodies.has(key): prop.bodies[key].global_transform = owner.global_transform*initial_bones[key]
			else: prop.fed_bones[key] = owner.global_transform*initial_bones[key]*initial_offsets[key]
	else: prop.global_transform = owner.global_transform * start_pose
	dispose()

func sync(owner: Node3D) -> void:
	if section_feed != null: section_feed.sync(owner)
	else: update_cut(surfaces,owner)

func dispose() -> void:
	restore_cut(surfaces)
	if section_feed != null: section_feed.dispose()

func capture() -> Dictionary:
	var result := {"start":start_pose,"pose":pose}
	if section_feed != null: result.progress = section_feed.progress
	return result

static func apply_cut(node: Node3D, owner: Node3D) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null or not mesh.visible: continue
		for surface in mesh.mesh.get_surface_count():
			var old := mesh.get_surface_override_material(surface)
			var material := mesh.get_active_material(surface)
			if material == null:
				material = StandardMaterial3D.new()
				mesh.mesh = mesh.mesh.duplicate()
				if mesh.mesh is PrimitiveMesh: mesh.mesh.material = material
				elif mesh.mesh is ArrayMesh: mesh.mesh.surface_set_material(surface,material)
			if not material is StandardMaterial3D: continue
			var cut := ShaderMaterial.new()
			cut.shader = CUT_SHADER
			cut.set_shader_parameter("tint",material.albedo_color)
			if material.albedo_texture != null: cut.set_shader_parameter("base_texture",material.albedo_texture)
			cut.set_shader_parameter("surface_roughness",material.roughness)
			cut.set_shader_parameter("surface_metallic",material.metallic)
			mesh.set_surface_override_material(surface,cut)
			records.append({"mesh":mesh,"surface":surface,"old":old,"base":material,"cut":cut})
	update_cut(records,owner)
	return records

static func update_cut(records: Array[Dictionary], owner: Node3D) -> void:
	for record in records: record.cut.set_shader_parameter("world_to_feed",owner.global_transform.affine_inverse())

static func restore_cut(records: Array[Dictionary]) -> void:
	for record in records:
		if is_instance_valid(record.mesh): record.mesh.set_surface_override_material(record.surface,record.old if record.old != null else record.base)
