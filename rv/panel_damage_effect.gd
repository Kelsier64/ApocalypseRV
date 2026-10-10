extends Node3D
## Short-lived, non-colliding presentation. Detached world pose preserves moving RV motion.
const GROUP := "rv_panel_damage_effect"
const MAX_ACTIVE_PER_VEHICLE := 6
const LIFETIME := 2.4
static var _sounds: Dictionary = {}
var age := 0.0
var fragments: Array[Dictionary] = []
var dust: Array[Dictionary] = []
var dust_material: StandardMaterial3D
var dust_lifetime := 0.8

static func spawn(panel: RVStructurePanel, destroyed: bool) -> Node3D:
	var parent := panel.get_parent()
	if parent == null or not panel.is_inside_tree(): return null
	var active: Array[Node] = []
	for effect in panel.get_tree().get_nodes_in_group(GROUP):
		if effect.get_parent() == parent and not effect.is_queued_for_deletion(): active.append(effect)
	while active.size() >= MAX_ACTIVE_PER_VEHICLE:
		var oldest: Node = active.pop_front()
		oldest.hide()
		oldest.queue_free()
	var effect := Node3D.new()
	effect.set_script(load("res://rv/panel_damage_effect.gd"))
	effect.name = "PanelDamageBurst"
	effect.top_level = true
	parent.add_child(effect)
	effect.global_position = panel.global_position
	effect.add_to_group(GROUP)
	effect._build(panel, destroyed)
	return effect

func _build(panel: RVStructurePanel, destroyed: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces: Array[Dictionary] = []
	var area_total := 0.0
	# Sample the authored visible pieces rather than the panel's union bounds, preserving hatches.
	for mesh: MeshInstance3D in panel.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.visible: continue
		var bounds := mesh.mesh.get_aabb()
		var size := bounds.size * mesh.global_basis.get_scale().abs()
		var area := maxf(size.x * size.y, maxf(size.x * size.z, size.y * size.z))
		if area < 0.1: continue
		area_total += area
		pieces.append({"mesh": mesh, "bounds": bounds, "weight": area_total})
	if pieces.is_empty():
		queue_free()
		return
	var rv := panel.get_connected_rv()
	var count := 30 if destroyed else 7
	for index in range(count):
		var entry: Dictionary = pieces.back()
		var pick := rng.randf() * area_total
		for candidate in pieces:
			if candidate.weight >= pick:
				entry = candidate
				break
		var bounds: AABB = entry.bounds
		var surface: MeshInstance3D = entry.mesh
		var point := bounds.position + bounds.size * Vector3(rng.randf(), rng.randf(), rng.randf())
		var thin_axis := bounds.size.min_axis_index()
		var normal := Vector3.ZERO
		# Roof fragments lift; wall fragments scatter on either side of their real surface.
		normal[thin_axis] = 1.0 if panel.structure_kind == "roof" else (-1.0 if rng.randf() < 0.5 else 1.0)
		point[thin_axis] = bounds.get_center()[thin_axis] + normal[thin_axis] * bounds.size[thin_axis] * 0.52
		var world_point := surface.to_global(point)
		var outward := (surface.global_basis * normal).normalized()
		var source := surface.get_active_material(0) as StandardMaterial3D
		var glass := source != null and source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		var tint := source.albedo_color if source else Color("afb3ae")
		var shard := MeshInstance3D.new()
		shard.mesh = _shard_mesh(rng)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(tint.r, tint.g, tint.b, 1.0).lerp(Color("a2b0ad"), 0.5 if glass else 0.15)
		material.metallic = 0.3 if glass else 0.65
		material.roughness = 0.22 if glass else 0.7
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		shard.material_override = material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shard)
		shard.global_position = world_point
		shard.basis = surface.global_basis.orthonormalized()
		shard.rotate_object_local(Vector3.RIGHT, rng.randf_range(-PI, PI))
		var size := rng.randf_range(0.13, 0.42) if destroyed else rng.randf_range(0.025, 0.08)
		shard.scale = Vector3.ONE * size
		var velocity := ClimbMath.point_velocity(rv, world_point) + outward * rng.randf_range(0.6, 2.5)
		velocity += Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.6, 2.0), rng.randf_range(-0.8, 0.8))
		fragments.append({"node": shard, "velocity": velocity, "size": size,
			"spin": Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))})
		if index < (9 if destroyed else 3): _add_dust(world_point, velocity * 0.2, destroyed, rng)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _sound(destroyed)
	sound.unit_size = 5.0
	sound.max_distance = 45.0
	sound.volume_db = -8.0 if destroyed else -15.0
	sound.pitch_scale = rng.randf_range(0.92, 1.08)
	add_child(sound)
	sound.play()

static func _shard_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, -0.4, 0), Vector3(-0.3, 0.55, 0.08), Vector3(0.5, rng.randf_range(-0.4, 0.3), -0.04)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_dust(point: Vector3, velocity: Vector3, destroyed: bool, rng: RandomNumberGenerator) -> void:
	if dust_material == null:
		dust_material = StandardMaterial3D.new()
		dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dust_material.albedo_color = Color(0.46, 0.43, 0.36, 0.22)
		dust_material.roughness = 1.0
		dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 32
		texture.height = 32
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 1.0)
		dust_material.albedo_texture = texture
		dust_lifetime = 1.0 if destroyed else 0.55
	var cloud := MeshInstance3D.new()
	cloud.mesh = QuadMesh.new()
	cloud.material_override = dust_material
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud)
	cloud.global_position = point
	var size := rng.randf_range(0.25, 0.5) if destroyed else 0.12
	cloud.scale = Vector3.ONE * size
	dust.append({"node": cloud, "velocity": velocity + Vector3.UP * 0.3, "size": size})

func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	var shrink := 1.0 - smoothstep(1.4, LIFETIME, age)
	for fragment in fragments:
		fragment.velocity.y -= 7.5 * delta
		fragment.node.position += fragment.velocity * delta
		fragment.node.rotation += fragment.spin * delta
		fragment.node.scale = Vector3.ONE * fragment.size * shrink
	for cloud in dust:
		cloud.node.visible = age < dust_lifetime
		cloud.node.position += cloud.velocity * delta
		cloud.node.scale = Vector3.ONE * cloud.size * (1.0 + age * 2.5)
	if dust_material:
		dust_material.albedo_color.a = 0.22 * maxf(0.0, 1.0 - age / dust_lifetime)

static func _sound(destroyed: bool) -> AudioStreamWAV:
	if _sounds.has(destroyed): return _sounds[destroyed]
	# Original metallic ring + brief broadband crunch; no external samples.
	var duration := 0.7 if destroyed else 0.26
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(rate * duration) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8421
	for i in range(data.size() / 2):
		var t := float(i) / rate
		var ring := sin(t * TAU * 173.0) * 0.3 + sin(t * TAU * 397.0) * 0.18
		var crunch := rng.randf_range(-1.0, 1.0) * (0.65 if destroyed else 0.3) * exp(-t * 13.0)
		var value := (ring * exp(-t * 9.0) + crunch) * minf(t * 1000.0, 1.0) * (1.0 - t / duration)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	_sounds[destroyed] = stream
	return stream
