extends RefCounted
class_name ForestFog
## Local fog belongs to streamed terrain, with a separate appearance RNG.
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

static func plans(field: WorldField, band: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rng := field.rng_for(band, "forest_fog")
	var width := field.profile.terrain_half_width
	var columns := maxi(1, floori(width * 2.0 / 90.0))
	for row in range(2):
		for column in range(columns):
			var x := -width + (column + 0.5) * width * 2.0 / columns + rng.randf_range(-8, 8)
			var z := -(band + (row + 0.5) / 2.0) * field.profile.chunk_length
			var sample := field.surface(x, z)
			# Parking courts and road centers keep their open view; nearby fog fades in at edges.
			if sample.reserved or sample.road.distance < sample.road.width * 0.5 + 18.0: continue
			var low := float(sample.height)
			for offset in [Vector2(15, 0), Vector2(-15, 0), Vector2(0, 15), Vector2(0, -15)]:
				low = minf(low, field.height_at(x + offset.x, z + offset.y))
			result.append({"position": Vector3(x, low + 4.0, z), "size": Vector3(100, 14, 96)})
	# Authored raised trails can sit well above neighboring natural valleys.
	# Anchor their own pockets to route heights, once in the center's owning band.
	var first := maxi(0, floori(band * field.profile.chunk_length / field.profile.stop_spacing) - 2)
	for index in range(first, first + 5):
		var site := field.stop(index)
		if not site.has("route"): continue
		for i in range(2, site.route.size() - 2, 2):
			var point: Vector3 = site.route[i]
			if floori(-point.z / field.profile.chunk_length) != band: continue
			result.append({"position": point + Vector3.UP * 2.5, "size": Vector3(65, 11, 58)})
	return result

static func build(chunk: ChunkGenerator) -> void:
	if not supported(): return
	var holder := Node3D.new()
	holder.name = "ForestFog"
	chunk.add_child(holder)
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/terrain/forest_fog.gdshader")
	for plan in plans(chunk.field, chunk.band):
		var volume := FogVolume.new()
		volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		volume.size = plan.size
		volume.position = plan.position
		volume.material = material
		holder.add_child(volume)
