extends RefCounted
## One connected body yields locally at the teeth. No pre-separated flying cells.
const FEED = preload("res://equipment/scrapper_feed_motion.gd")
const INTAKE_SHADER = preload("res://equipment/scrapper_intake.gdshader")
const EDGE_LENGTH := .11
var originals: Array[GeometryInstance3D] = []
var meshes: Array[MeshInstance3D] = []
var surfaces: Array[ShaderMaterial] = []
var source_points := PackedVector3Array()
var rest_bounds := AABB()
var body_pose := Transform3D.IDENTITY
var progress := 0.0
var grip := 0.0
var tooth_phase := 0.0
var flexibility := 0.0
var pivot := Vector3.ZERO
var lean_axis := Vector3.FORWARD

func setup(prop: Node3D, owner: Node3D, bounds: AABB, pose: Transform3D) -> void:
	rest_bounds = FEED.rotated_box(bounds,pose.basis)
	rest_bounds.position += pose.origin
	pivot = Vector3(rest_bounds.get_center().x,rest_bounds.position.y,rest_bounds.get_center().z)
	lean_axis = Vector3.RIGHT if rest_bounds.size.z > rest_bounds.size.x else Vector3.FORWARD
	flexibility = 1.0 if prop.scene_file_path == "res://props/wheel.tscn" else 0.0
	for source: MeshInstance3D in prop.find_children("*","MeshInstance3D",true,false):
		if source.mesh == null or not source.is_visible_in_tree(): continue
		var frame := owner.global_transform.affine_inverse()*source.global_transform
		var mesh := ArrayMesh.new()
		for surface in source.mesh.get_surface_count():
			if source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays := _tessellate(source.mesh.surface_get_arrays(surface),frame)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var material := _material(source.get_active_material(surface))
			mesh.surface_set_material(mesh.get_surface_count()-1,material)
			surfaces.append(material)
		if mesh.get_surface_count() == 0: continue
		var visual := MeshInstance3D.new()
		visual.name = "CrushingSurface"
		visual.mesh = mesh
		visual.cast_shadow = source.cast_shadow
		# Shader motion must not disappear from the CPU's original culling box.
		visual.custom_aabb = rest_bounds.merge(AABB(Vector3(-.5,.4,-.5),Vector3(1,1,1))).grow(.2)
		owner.add_child(visual)
		meshes.append(visual)
		originals.append(source)
	for label: Label3D in prop.find_children("*","Label3D",true,false):
		if label.is_visible_in_tree(): originals.append(label)
	for original in originals: original.hide()
	advance(owner,0)

func _material(base: Material) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = INTAKE_SHADER
	if base is StandardMaterial3D:
		result.set_shader_parameter("tint",base.albedo_color)
		result.set_shader_parameter("surface_roughness",base.roughness)
		result.set_shader_parameter("surface_metallic",base.metallic)
		result.set_shader_parameter("uv_scale",base.uv1_scale)
		result.set_shader_parameter("uv_offset",base.uv1_offset)
		if base.albedo_texture != null: result.set_shader_parameter("base_texture",base.albedo_texture)
		if base.normal_enabled and base.normal_texture != null:
			result.set_shader_parameter("has_normal_texture",true)
			result.set_shader_parameter("normal_texture",base.normal_texture)
			result.set_shader_parameter("normal_strength",base.normal_scale)
	result.set_shader_parameter("flexibility",flexibility)
	return result

func _tessellate(arrays: Array, frame: Transform3D) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var out_vertices: Array[Vector3] = []
	var out_normals: Array[Vector3] = []
	var out_uv: Array[Vector2] = []
	var normal_frame := frame.basis.inverse().transposed()
	for triangle in range(0,count,3):
		var points: Array[Vector3] = []
		var ns: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for corner in 3:
			var index := indices[triangle+corner] if not indices.is_empty() else triangle+corner
			points.append(frame*vertices[index])
			ns.append((normal_frame*normals[index]).normalized())
			uvs.append(uv[index] if not uv.is_empty() else Vector2.ZERO)
		_split_triangle(points,ns,uvs,out_vertices,out_normals,out_uv)
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = PackedVector3Array(out_vertices)
	result[Mesh.ARRAY_NORMAL] = PackedVector3Array(out_normals)
	result[Mesh.ARRAY_TEX_UV] = PackedVector2Array(out_uv)
	source_points.append_array(result[Mesh.ARRAY_VERTEX])
	var surface_tool := SurfaceTool.new()
	var temporary := ArrayMesh.new()
	temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,result)
	surface_tool.create_from(temporary,0)
	surface_tool.generate_tangents()
	return surface_tool.commit_to_arrays()

func _split_triangle(points: Array[Vector3], ns: Array[Vector3], uvs: Array[Vector2], out_vertices: Array[Vector3], out_normals: Array[Vector3], out_uv: Array[Vector2]) -> void:
	var edge := -1
	var longest := EDGE_LENGTH*EDGE_LENGTH
	for index in 3:
		var length := points[index].distance_squared_to(points[(index+1)%3])
		if length > longest:
			longest = length
			edge = index
	if edge == -1:
		out_vertices.append_array(points)
		out_normals.append_array(ns)
		out_uv.append_array(uvs)
		return
	# Bisect by shared edge length, never by a face's private subdivision count.
	# Adjacent faces therefore retain matching boundary vertices when folded.
	var a := edge
	var b := (edge+1)%3
	var c := (edge+2)%3
	var midpoint := (points[a]+points[b])*.5
	var normal := (ns[a]+ns[b]).normalized()
	var texture_uv := (uvs[a]+uvs[b])*.5
	_split_triangle([points[a],midpoint,points[c]],[ns[a],normal,ns[c]],[uvs[a],texture_uv,uvs[c]],out_vertices,out_normals,out_uv)
	_split_triangle([midpoint,points[b],points[c]],[normal,ns[b],ns[c]],[texture_uv,uvs[b],uvs[c]],out_vertices,out_normals,out_uv)


func advance(owner: Node3D, amount: float) -> void:
	progress = clampf(amount,0,1)
	var catch := smoothstep(0.0,.12,progress)
	var feeding := clampf((progress-.12)/.88,0,1)
	# Short holds and pulls give the teeth purchase without reversing the feed.
	var bites := 7.0
	var cycle := feeding*bites
	var draw := (floorf(cycle)+smoothstep(.18,.90,fmod(cycle,1.0)))/bites
	var descent := maxf(0,rest_bounds.position.y-.79)*catch+(rest_bounds.size.y+.20)*draw
	var load := sin(progress*PI)*catch
	var lean := (.08*draw+.32*load+sin(cycle*TAU)*.025*load)*(1.0-flexibility*.4)
	var basis := Basis(lean_axis,lean)*Basis(Vector3.UP,sin(cycle*PI)*.018*load)
	var origin := pivot-basis*pivot-Vector3(0,descent,0)
	origin.x -= pivot.x*smoothstep(0,.45,progress)
	origin.z -= pivot.z*smoothstep(0,.45,progress)
	body_pose = Transform3D(basis,origin)
	var lowest := FEED.rotated_box(rest_bounds,basis).position.y+origin.y
	grip = smoothstep(0,.025,maxf(0,.87-lowest))
	tooth_phase = progress*TAU*7.0
	sync(owner)

func deform_point(rest: Vector3) -> Vector3:
	# CPU counterpart for geometry/containment checks; keep paired with shader.
	var p := body_pose*rest
	var pinch := grip*(1-smoothstep(.76,1.08,p.y))
	var fold := grip*(1-smoothstep(.84,1.08,p.y))
	p.x = lerpf(p.x,clampf(p.x,-.105,.105),pinch)
	p.z = lerpf(p.z,clampf(p.z,-.36,.36),fold)
	var crease := pinch*(1-pinch)*(1-flexibility*.65)
	p.x += sin(p.y*67+p.z*19)*crease*.095
	p.z += sin(p.y*53-p.x*27)*crease*.06
	var throat := grip*(1-smoothstep(.84,1.0,p.y))
	p.x = lerpf(p.x,clampf(p.x,-.395,.395),throat)
	p.z = lerpf(p.z,clampf(p.z,-.395,.395),throat)
	var tear := grip*(1-smoothstep(.71,.82,p.y))
	p.x += sin(p.z*71+tooth_phase)*tear*.018
	return p

func sync(_owner: Node3D) -> void:
	var current_bounds := FEED.rotated_box(rest_bounds,body_pose.basis)
	current_bounds.position += body_pose.origin
	current_bounds = current_bounds.merge(AABB(Vector3(-.5,.4,-.5),Vector3(1,1,1))).grow(.08)
	for mesh in meshes: mesh.custom_aabb = current_bounds
	for material in surfaces:
		material.set_shader_parameter("body_pose",body_pose)
		material.set_shader_parameter("grip",grip)
		material.set_shader_parameter("tooth_phase",tooth_phase)

func dispose() -> void:
	for mesh in meshes:
		if is_instance_valid(mesh): mesh.queue_free()
	meshes.clear()
	surfaces.clear()
	for original in originals:
		if is_instance_valid(original): original.show()
	originals.clear()
