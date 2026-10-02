extends Node3D
class_name TreeFall
## Light physical timber and falling foliage, retained until outside the camera.
const BREAK_HEIGHT := 0.75
const MAX_LOG_LENGTH := 3.2
const MIN_KEEP_SECONDS := 6.0
const OFFSCREEN_SECONDS := 2.0
const WOOD_MIN_KEEP_SECONDS := 8.0
const WOOD_SECONDS := 20.0
const WOOD_FADE_SECONDS := 2.0
const FALL_MATERIAL = preload("res://world/terrain/fallen_tree.gdshader")
const VEHICLE_AUDIO = preload("res://rv/vehicle_audio.gd")
static var prepared := false
static var preparing := false
static var mesh_arrays: Dictionary = {}
static var dust_mesh: QuadMesh
static var chip_mesh: BoxMesh
static var bark_material: StandardMaterial3D
static var cut_material: StandardMaterial3D
var crown := RigidBody3D.new()
var canopy := Node3D.new()
var stump: MeshInstance3D
var pieces: Array[Dictionary] = []
var crown_materials: Array[ShaderMaterial] = []
var canopy_materials: Array[ShaderMaterial] = []
var wood_bodies: Array[RigidBody3D] = []
var leaf_pieces: Array[Dictionary] = []
var visibility_meshes: Array[MeshInstance3D] = []
var wood_meshes: Array[MeshInstance3D] = []
var leaf_meshes: Array[MeshInstance3D] = []
var offscreen_elapsed := 0.0
var wood_offscreen_elapsed := 0.0
var wood_removed := false
var leaves_removed := false
var axis: Vector3
var direction: Vector3
var scatter_direction: Vector3
var elapsed := 0.0
var landed := false
var crown_height := 1.0
var ground_slope := 0.0
var ground_refresh := 0.0
var canopy_dispersed := false
var rng := RandomNumberGenerator.new()

static func prepare(parent: Node) -> void:
	if prepared: return
	while preparing:
		await parent.get_tree().process_frame
		if prepared: return
	preparing = true
	VEHICLE_AUDIO.synth("blocked")
	# Render real mesh layouts and materials during loading, including the
	# transparent dust and alpha-hashed leaf/shadow pipelines. A tiny isolated
	# viewport also warms Compatibility, without showing a fake tree in play.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(20, 12, 20)
	camera.look_at(Vector3(0, 5, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.shadow_enabled = true
	stage.add_child(light)
	for kind in range(6):
		var mesh := ForestMeshes.tree(kind)
		for surface in range(mesh.get_surface_count()): _surface_arrays(mesh, surface)
	var source := MeshInstance3D.new()
	source.mesh = ForestMeshes.tree(0)
	source.scale = Vector3(3, 14, 3)
	stage.add_child(source)
	var effect := spawn(source, Vector3.FORWARD * 8)
	effect.set_process(false)
	effect.set_physics_process(false)
	for body in effect.wood_bodies:
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	viewport.queue_free()
	prepared = true
	preparing = false

static func _surface_arrays(mesh: Mesh, surface: int) -> Array:
	if not mesh_arrays.has(mesh):
		# Source meshes are immutable shared forest/roadside resources. Bound
		# custom mesh retention too; the normal outdoor set uses fewer than 16.
		if mesh_arrays.size() >= 32: mesh_arrays.erase(mesh_arrays.keys()[0])
		mesh_arrays[mesh] = {}
	if not mesh_arrays[mesh].has(surface): mesh_arrays[mesh][surface] = mesh.surface_get_arrays(surface)
	return mesh_arrays[mesh][surface]

static func spawn(source: Node3D, velocity: Vector3, vehicle_position: Vector3 = Vector3.INF) -> TreeFall:
	var parent := source.get_parent() as Node3D
	var holder := parent.get_node_or_null("TreeDebris") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "TreeDebris"
		parent.add_child(holder)
	var effect := TreeFall.new()
	effect.set_process(false)
	effect.set_physics_process(false)
	holder.add_child(effect)
	effect.global_position = source.global_position + Vector3.UP * BREAK_HEIGHT
	effect.direction = velocity.slide(Vector3.UP).normalized()
	if effect.direction.is_zero_approx(): effect.direction = Vector3.FORWARD
	effect.axis = Vector3.UP.cross(effect.direction).normalized()
	var side := 1.0
	if vehicle_position.is_finite():
		side = signf((source.global_position - vehicle_position).dot(effect.axis))
		if is_zero_approx(side): side = 1.0
	effect.scatter_direction = effect.axis * side
	effect.rng.seed = hash(source.global_position)
	effect.add_child(effect.canopy)
	var radius := source.global_basis.get_scale().x * (0.1 if source is MeshInstance3D else 0.325)
	var meshes: Array[Node] = []
	if source is MeshInstance3D: meshes.append(source)
	else: meshes.assign(source.find_children("*", "MeshInstance3D", true, false))
	var height := 0.0
	for original: MeshInstance3D in meshes:
		if original.mesh == null: continue
		for surface in range(original.mesh.get_surface_count()):
			if _is_foliage(original.get_active_material(surface)): continue
			for vertex: Vector3 in _surface_arrays(original.mesh, surface)[Mesh.ARRAY_VERTEX]:
				height = maxf(height, (original.to_global(vertex) - effect.global_position).y)
	var offset := 0.0
	while offset < height:
		var body := effect.crown if effect.wood_bodies.is_empty() else RigidBody3D.new()
		body.name = "FallenTrunk%d" % effect.wood_bodies.size()
		body.freeze = true
		body.collision_layer = 1
		body.collision_mask = 1
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 16
		effect.add_child(body)
		body.position.y = offset
		effect.wood_bodies.append(body)
		var length := minf(MAX_LOG_LENGTH, height - offset)
		for original: MeshInstance3D in meshes:
			if original.mesh == null: continue
			var mesh := _cut_upper(original, effect.global_position.y + offset, effect.global_position.y + offset + length)
			effect._add_wood(original, mesh, body)
		effect._make_collision(body, radius * lerpf(1.0, 0.2, offset / height), length, velocity)
		offset += length
	effect.crown_height = height
	effect._make_stump(radius)
	for original: MeshInstance3D in meshes:
		if original.mesh != null: effect._make_leaves(original)
	effect._refresh_ground()
	effect._emit_chips()
	effect._emit_dust(Vector3.DOWN * BREAK_HEIGHT, 5, 0.6)
	source.hide()
	if source is MeshInstance3D: source.queue_free()
	effect.set_process(true)
	effect.set_physics_process(true)
	return effect

static func _is_foliage(material: Material) -> bool:
	var standard := material as StandardMaterial3D
	if standard == null: return false
	if standard.albedo_texture != null and standard.albedo_texture.resource_path.ends_with("bough.svg"): return true
	return standard.albedo_color.g > standard.albedo_color.r * 1.12

func _add_wood(original: MeshInstance3D, mesh: ArrayMesh, body: RigidBody3D) -> void:
	if mesh.get_surface_count() == 0: return
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	for surface in range(mesh.get_surface_count()):
		var original_material := mesh.surface_get_material(surface) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = FALL_MATERIAL
		if original_material != null:
			material.set_shader_parameter("surface_texture", original_material.albedo_texture)
			material.set_shader_parameter("tint", original_material.albedo_color)
			material.set_shader_parameter("use_vertex_color", original_material.vertex_color_use_as_albedo)
		visual.set_surface_override_material(surface, material)
		crown_materials.append(material)
	body.add_child(visual)
	visual.global_transform = original.global_transform
	visibility_meshes.append(visual)
	wood_meshes.append(visual)

func _make_collision(body: RigidBody3D, radius: float, length: float, velocity: Vector3) -> void:
	# The collision and mesh share the same moving rigid body. A yielded trunk
	# gets pushed by the vehicle instead of disabling collision under its mesh.
	var trunk := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = length
	trunk.shape = cylinder
	trunk.position.y = length * 0.5
	body.add_child(trunk)
	if cut_material == null:
		cut_material = StandardMaterial3D.new()
		cut_material.albedo_color = Color("a18b63")
		cut_material.roughness = 1.0
	for end in [0.02, length - 0.02]:
		var cut := MeshInstance3D.new()
		var cap := CylinderMesh.new()
		cap.top_radius = radius * (1.0 if end < 0.1 else 0.85)
		cap.bottom_radius = cap.top_radius
		cap.height = 0.035
		cap.radial_segments = 9
		cap.material = cut_material
		cut.mesh = cap
		cut.position.y = end
		body.add_child(cut)
		visibility_meshes.append(cut)
		wood_meshes.append(cut)
	body.mass = clampf(length * radius * 3, 2, 4)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.UP * length * 0.5
	body.linear_damp = 0.15
	body.angular_damp = 0.3
	var material := PhysicsMaterial.new()
	material.friction = 0.08
	material.bounce = 0.08
	body.physics_material_override = material
	body.freeze = false
	# Separate light sections preserve all timber without a long rigid bar
	# pinning the bumper against the next standing tree. Start at the old mesh.
	body.linear_velocity = direction * velocity.slide(Vector3.UP).length() * 0.65 + scatter_direction * 5.0 + Vector3.UP * 0.4
	body.angular_velocity = axis * 2.5

static func _cut_upper(source: MeshInstance3D, cut_y: float, top_y: float = INF) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in range(source.mesh.get_surface_count()):
		if _is_foliage(source.get_active_material(surface)): continue
		var arrays := _surface_arrays(source.mesh, surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var written := 0
		var pose := source.global_transform
		var height_axis := Vector3(pose.basis.x.y, pose.basis.y.y, pose.basis.z.y)
		for triangle in range(0, count, 3):
			var polygon: Array[Dictionary] = []
			for corner in range(3):
				var i := indices[triangle + corner] if not indices.is_empty() else triangle + corner
				polygon.append({"p": vertices[i], "h": height_axis.dot(vertices[i]) + pose.origin.y, "n": normals[i] if normals.size() == vertices.size() else Vector3.UP,
					"uv": uvs[i] if uvs.size() == vertices.size() else Vector2.ZERO,
					"color": colors[i] if colors.size() == vertices.size() else Color.WHITE})
			var clipped: Array[Dictionary] = []
			for i in range(3):
				var a: Dictionary = polygon[i]
				var b: Dictionary = polygon[(i + 1) % 3]
				if a.h >= cut_y: clipped.append(a)
				if (a.h >= cut_y) != (b.h >= cut_y):
					var t: float = (cut_y - a.h) / (b.h - a.h)
					clipped.append({"p": a.p.lerp(b.p, t), "h": cut_y, "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t), "color": a.color.lerp(b.color, t)})
			if is_finite(top_y):
				polygon = clipped
				clipped = []
				for i in range(polygon.size()):
					var a: Dictionary = polygon[i]
					var b: Dictionary = polygon[(i + 1) % polygon.size()]
					if a.h <= top_y: clipped.append(a)
					if (a.h <= top_y) != (b.h <= top_y):
						var t: float = (top_y - a.h) / (b.h - a.h)
						clipped.append({"p": a.p.lerp(b.p, t), "h": top_y, "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t), "color": a.color.lerp(b.color, t)})
			for i in range(1, clipped.size() - 1):
				for vertex: Dictionary in [clipped[0], clipped[i], clipped[i + 1]]:
					st.set_normal(vertex.n)
					st.set_uv(vertex.uv)
					st.set_color(vertex.color)
					st.add_vertex(vertex.p)
					written += 1
		if written > 0:
			st.set_material(source.get_active_material(surface))
			st.commit(result)
	return result

func _make_leaves(source: MeshInstance3D) -> void:
	for surface in range(source.mesh.get_surface_count()):
		var material := source.get_active_material(surface) as StandardMaterial3D
		if not _is_foliage(material): continue
		var arrays := _surface_arrays(source.mesh, surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var groups: Dictionary = {}
		var source_pose := global_transform.affine_inverse() * source.global_transform
		var normal_basis := source_pose.basis.inverse().transposed()
		for triangle in range(0, count, 3):
			var centre := Vector3.ZERO
			var points: Array[Dictionary] = []
			for corner in range(3):
				var i := indices[triangle + corner] if not indices.is_empty() else triangle + corner
				var point := source_pose * vertices[i]
				centre += point
				points.append({"p": point, "n": (normal_basis * normals[i]).normalized() if normals.size() == vertices.size() else Vector3.UP,
					"uv": uvs[i] if uvs.size() == vertices.size() else Vector2.ZERO, "color": colors[i] if colors.size() == vertices.size() else Color.WHITE})
			centre /= 3.0
			var key := Vector2i(floori(centre.y / 1.4), floori((atan2(centre.z, centre.x) + PI) / (TAU / 4)))
			if not groups.has(key): groups[key] = []
			groups[key].append_array(points)
		for key: Vector2i in groups:
			var points: Array = groups[key]
			var centre := Vector3.ZERO
			for point: Dictionary in points: centre += point.p
			centre /= points.size()
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for point: Dictionary in points:
				st.set_normal(point.n)
				st.set_uv(point.uv)
				st.set_color(point.color)
				st.add_vertex(point.p - centre)
			var leaf_material := ShaderMaterial.new()
			leaf_material.shader = FALL_MATERIAL
			leaf_material.set_shader_parameter("surface_texture", material.albedo_texture)
			leaf_material.set_shader_parameter("tint", material.albedo_color)
			leaf_material.set_shader_parameter("use_vertex_color", material.vertex_color_use_as_albedo)
			st.set_material(leaf_material)
			var visual := MeshInstance3D.new()
			visual.mesh = st.commit()
			canopy.add_child(visual)
			visual.position = centre
			visibility_meshes.append(visual)
			leaf_meshes.append(visual)
			canopy_materials.append(leaf_material)
			var leaf_velocity := direction * rng.randf_range(1.5, 3.0) + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(0.0, 1.0), rng.randf_range(-1.4, 1.4))
			var fall_time := sqrt(maxf(centre.y + BREAK_HEIGHT, 0) / 3.0)
			var ground := _ground_height(visual.global_position + leaf_velocity * fall_time)
			leaf_pieces.append({"node": visual, "start": centre, "velocity": leaf_velocity,
				"spin": Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.2, 1.2), rng.randf_range(-0.8, 0.8)), "ground": ground, "settled": false, "material": leaf_material})

func _step_leaves(delta: float) -> void:
	canopy_dispersed = true
	for piece: Dictionary in leaf_pieces:
		if piece.settled: continue
		canopy_dispersed = false
		var visual: MeshInstance3D = piece.node
		piece.velocity.y -= 6.0 * delta
		visual.position += piece.velocity * delta
		visual.rotation += piece.spin * delta
		# Sample the actual landing position, never the RV roof or loose timber.
		var world_bounds := visual.global_transform * visual.mesh.get_aabb()
		var ground: float = piece.ground
		if piece.velocity.y < 0 and world_bounds.position.y <= ground + 0.06:
			ground = _ground_height(visual.global_position)
			if world_bounds.position.y > ground + 0.06:
				piece.ground = ground
				continue
			piece.settled = true
			piece.ground = ground
			visual.rotation.x = 0
			visual.rotation.z = 0
			visual.scale.y = 0.08
			visual.global_position.y = ground + 0.08
			piece.material.set_shader_parameter("ground_origin", Vector3(0, ground, 0))
			piece.material.set_shader_parameter("compression", 1.0)

func _visible_to_camera(camera: Camera3D, meshes: Array[MeshInstance3D] = []) -> bool:
	if camera == null: return true
	var planes := camera.get_frustum()
	for visual: MeshInstance3D in visibility_meshes if meshes.is_empty() else meshes:
		if not is_instance_valid(visual) or not visual.visible: continue
		var bounds := visual.global_transform * visual.mesh.get_aabb()
		var outside := false
		for plane: Plane in planes:
			var all_outside := true
			for corner in range(8):
				if plane.distance_to(bounds.get_endpoint(corner)) <= 0:
					all_outside = false
					break
			if all_outside:
				outside = true
				break
		if not outside: return true
	return false

func _can_cleanup_leaves(camera: Camera3D, delta: float) -> bool:
	if leaves_removed: return false
	if leaf_meshes.is_empty(): return elapsed >= MIN_KEEP_SECONDS
	if camera == null or elapsed < MIN_KEEP_SECONDS or _visible_to_camera(camera, leaf_meshes):
		offscreen_elapsed = 0.0
		return false
	for piece: Dictionary in leaf_pieces:
		if not piece.settled:
			offscreen_elapsed = 0.0
			return false
	# Hysteresis prevents deletion on a quick glance away or frustum-edge flicker.
	offscreen_elapsed += delta
	return offscreen_elapsed >= OFFSCREEN_SECONDS

func _can_cleanup_wood(camera: Camera3D, delta: float) -> bool:
	if wood_removed: return false
	if elapsed >= WOOD_SECONDS + WOOD_FADE_SECONDS: return true
	if camera == null or elapsed < WOOD_MIN_KEEP_SECONDS or _visible_to_camera(camera, wood_meshes):
		wood_offscreen_elapsed = 0.0
		return false
	wood_offscreen_elapsed += delta
	return wood_offscreen_elapsed >= OFFSCREEN_SECONDS

func _cleanup_wood() -> void:
	wood_removed = true
	for body in wood_bodies:
		body.collision_layer = 0
		body.collision_mask = 0
		body.queue_free()
	if is_instance_valid(stump): stump.queue_free()
	for visual in wood_meshes: visibility_meshes.erase(visual)
	wood_bodies.clear()
	wood_meshes.clear()
	crown_materials.clear()
	crown = null
	stump = null

func _cleanup_leaves() -> void:
	leaves_removed = true
	for visual in leaf_meshes:
		visibility_meshes.erase(visual)
		visual.queue_free()
	leaf_meshes.clear()
	leaf_pieces.clear()
	canopy_materials.clear()
	canopy.hide()

func _make_stump(radius: float) -> void:
	if bark_material == null:
		bark_material = StandardMaterial3D.new()
		bark_material.albedo_color = Color("75614a")
		bark_material.albedo_texture = preload("res://assets/materials/style_sample/bark.svg")
		bark_material.roughness = 1.0
		cut_material = StandardMaterial3D.new()
		cut_material.albedo_color = Color("a18b63")
		cut_material.roughness = 1.0
	var sides := SurfaceTool.new()
	var cap := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []
	for i in range(9):
		var angle := i * TAU / 9
		rim.append(Vector3(cos(angle) * radius, rng.randf_range(-0.18, 0.08), sin(angle) * radius))
	for i in range(9):
		var a := rim[i]
		var b := rim[(i + 1) % 9]
		var bottom_a := Vector3(a.x, -BREAK_HEIGHT, a.z)
		var bottom_b := Vector3(b.x, -BREAK_HEIGHT, b.z)
		for point in [bottom_a, a, b, bottom_a, b, bottom_b]:
			sides.set_uv(Vector2(point.x + point.z, point.y))
			sides.add_vertex(point)
		for point in [Vector3(0, -0.1, 0), b, a]: cap.add_vertex(point)
	sides.generate_normals()
	cap.generate_normals()
	sides.set_material(bark_material)
	cap.set_material(cut_material)
	var mesh := sides.commit()
	cap.commit(mesh)
	stump = MeshInstance3D.new()
	stump.mesh = mesh
	add_child(stump)
	visibility_meshes.append(stump)
	wood_meshes.append(stump)

func _ground_height(point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * (crown_height + 8), point - Vector3.UP * 35, 1)
	var excluded_wood: Array[RID] = []
	for body in wood_bodies: excluded_wood.append(body.get_rid())
	query.exclude = excluded_wood
	var chunk := get_parent().get_parent()
	var trunks := chunk.get_node_or_null("ForestTrunks") as CollisionObject3D
	if trunks != null:
		var excluded_trunks := query.exclude
		excluded_trunks.append(trunks.get_rid())
		query.exclude = excluded_trunks
	for attempt in range(5):
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		var collider: Object = hit.collider
		if not collider is RigidBody3D and not collider is CharacterBody3D:
			return hit.position.y
		var excluded := query.exclude
		excluded.append(collider.get_rid())
		query.exclude = excluded
	return global_position.y - BREAK_HEIGHT

func _refresh_ground() -> void:
	var origin := crown.global_position
	origin.y = _ground_height(origin)
	var along := crown.global_basis.y.slide(Vector3.UP).normalized()
	if along.is_zero_approx(): along = direction
	ground_slope = (_ground_height(origin + along * crown_height) - origin.y) / crown_height
	for material in crown_materials:
		material.set_shader_parameter("ground_origin", origin)
		material.set_shader_parameter("fall_direction", along)
		material.set_shader_parameter("ground_slope", ground_slope)

func _physics_process(delta: float) -> void:
	if wood_removed: return
	ground_refresh -= delta
	if ground_refresh <= 0 and not crown.sleeping:
		ground_refresh = 0.25
		_refresh_ground()
	if landed: return
	var state := PhysicsServer3D.body_get_direct_state(crown.get_rid())
	if state == null: return
	for contact in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(contact)
		if collider is StaticBody3D and not collider is ForestTrunks and state.get_contact_local_normal(contact).y > 0.5:
			landed = true
			var at := state.get_contact_local_position(contact)
			_emit_dust(to_local(at), 9, 1.5)
			break

func _emit_chips() -> void:
	if chip_mesh == null:
		chip_mesh = BoxMesh.new()
		chip_mesh.size = Vector3(0.06, 0.23, 0.04)
		chip_mesh.material = cut_material
	for i in range(10):
		var chip := MeshInstance3D.new()
		chip.mesh = chip_mesh
		chip.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		add_child(chip)
		pieces.append({"node": chip, "start": Vector3.ZERO, "velocity": direction * rng.randf_range(1.4, 3.5) + Vector3(rng.randf_range(-1, 1), rng.randf_range(1.5, 3), rng.randf_range(-1, 1)), "born": elapsed, "life": 2.0, "dust": false})

func _emit_dust(at: Vector3, count: int, size: float) -> void:
	if dust_mesh == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0.5))
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1, 0.5)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = Color("8c806a")
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = false
		dust_mesh = QuadMesh.new()
		dust_mesh.material = material
	for i in range(count):
		var dust := MeshInstance3D.new()
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dust.mesh = dust_mesh
		dust.position = at + Vector3(rng.randf_range(-1, 1), 0.15, rng.randf_range(-1, 1)) * size
		dust.scale = Vector3.ONE * size
		add_child(dust)
		pieces.append({"node": dust, "start": dust.position, "velocity": Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.4, 0.8), rng.randf_range(-0.6, 0.6)), "born": elapsed, "life": 2.1, "dust": true, "size": size})

func _process(delta: float) -> void:
	elapsed += delta
	_step_leaves(delta)
	for i in range(pieces.size() - 1, -1, -1):
		var piece: Dictionary = pieces[i]
		var age: float = elapsed - piece.born
		var visual: MeshInstance3D = piece.node
		if age >= piece.life:
			visual.queue_free()
			pieces.remove_at(i)
			continue
		visual.position = piece.start + piece.velocity * age
		if piece.dust:
			visual.scale = Vector3.ONE * piece.size * (1.0 + age * 0.9)
		else:
			visual.position.y = maxf(-BREAK_HEIGHT + 0.08, visual.position.y - 4.9 * age * age)
			visual.rotate_x(delta * 5)
		visual.transparency = clampf(age / piece.life, 0, 1)
	var camera := get_viewport().get_camera_3d()
	if not wood_removed:
		var fade := clampf((elapsed - WOOD_SECONDS) / WOOD_FADE_SECONDS, 0.0, 1.0)
		for material in crown_materials: material.set_shader_parameter("fade", fade)
		for visual in wood_meshes:
			# Mesh transparency also covers the cut caps and stump.
			if not visual.get_active_material(0) is ShaderMaterial: visual.transparency = fade
		if _can_cleanup_wood(camera, delta): _cleanup_wood()
	if _can_cleanup_leaves(camera, delta): _cleanup_leaves()
	if wood_removed and leaves_removed: queue_free()
