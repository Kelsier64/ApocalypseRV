extends RefCounted
class_name ForestFog
## Local fog belongs to streamed terrain, with a separate appearance RNG.
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

static func plans(field: WorldField, band: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rng := field.rng_for(band, "white_ground_mist")
	for row in range(3):
		var s := (band + (row + 0.5) / 3.0) * field.profile.chunk_length
		var frame := field.road_frame(s)
		for side: float in [-1.0, 1.0]:
			for column in range(2):
				var point := frame * Vector3(side * (field.road_width(s) * 0.5 + 28.0 + column * 52.0 + rng.randf_range(-5.0, 5.0)), 0, rng.randf_range(-5.0, 5.0))
				var sample := field.surface(point.x, point.z)
				if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 12.0: continue
				var size := Vector3(70, 16, 78) if column == 0 else Vector3(100, 20, 100)
				if not _clear_of_courts(field, point, size): continue
				var low := float(sample.height)
				for offset: Vector2 in [Vector2(16, 0), Vector2(-16, 0), Vector2(0, 16), Vector2(0, -16)]:
					low = minf(low, field.height_at(point.x + offset.x, point.z + offset.y))
				point.y = low + 4.0
				result.append({"position": point, "size": size, "river": false})
	# River mist has one global owner and sits below the bridge's road surface.
	for plan in field.landforms.rivers_near(-(band + 0.5) * field.profile.chunk_length, 90.0):
		if floori(float(plan.s) / field.profile.chunk_length) != band: continue
		for lateral: float in [-100.0, 0.0, 100.0]:
			var x := float(plan.center_x) + lateral
			var point := Vector3(x, float(plan.water_height) + 3.0, field.landforms.river_z(plan, x))
			var size := Vector3(160, 18, 90)
			if _clear_of_courts(field, point, size): result.append({"position": point, "size": size, "river": true})
	return result

static func _clear_of_courts(field: WorldField, point: Vector3, size: Vector3) -> bool:
	var radius := Vector2(size.x, size.z).length() * 0.5 + 4.0
	for site in field.sites_near_z(point.z):
		if field.court_distance(point.x, point.z, site) < radius: return false
		if site.has("bounds"):
			var bounds: AABB = site.bounds.grow(4.0)
			if point.x + size.x * 0.5 > bounds.position.x and point.x - size.x * 0.5 < bounds.end.x and point.z + size.z * 0.5 > bounds.position.z and point.z - size.z * 0.5 < bounds.end.z: return false
	return true

static func build(chunk: ChunkGenerator) -> void:
	if not supported(): return
	var holder := Node3D.new()
	holder.name = "ForestFog"
	chunk.add_child(holder)
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/terrain/white_mist.gdshader")
	material.set_shader_parameter("wetness", chunk.field.landforms.material_weights(chunk.field.landforms.appearance_at((chunk.band + 0.5) * chunk.field.profile.chunk_length)).y)
	var ancestor: Node = chunk
	while ancestor != null and not ancestor.has_node("WorldClock"):
		ancestor = ancestor.get_parent()
	if ancestor != null:
		var clock := ancestor.get_node("WorldClock") as WorldClock
		clock.register_fog(material)
		holder.tree_exiting.connect(func() -> void:
			if is_instance_valid(clock): clock.unregister_fog(material))
	for plan in plans(chunk.field, chunk.band):
		var volume := FogVolume.new()
		volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		volume.size = plan.size
		volume.position = plan.position
		volume.material = material
		holder.add_child(volume)
