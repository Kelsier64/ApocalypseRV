extends RefCounted
## Navigation deliberately simplifies terrain height. Project in XZ so coverage
## checks cannot mistake the 3D closest point sliding along a slope for a hole.
static func point_at(chunks: Array[ChunkGenerator], point: Vector3, giant: bool = false) -> Vector3:
	var result := Vector3(INF, INF, INF)
	var nearest_height := INF
	for chunk: ChunkGenerator in chunks:
		var region := chunk.giant_navigation if giant else chunk.navigation
		if region == null or region.navigation_mesh == null: continue
		var mesh := region.navigation_mesh
		var vertices := mesh.get_vertices()
		for index in range(mesh.get_polygon_count()):
			var polygon := mesh.get_polygon(index)
			if polygon.size() < 3: continue
			var a: Vector3 = region.global_transform * vertices[polygon[0]]
			for corner in range(1, polygon.size() - 1):
				var b: Vector3 = region.global_transform * vertices[polygon[corner]]
				var c: Vector3 = region.global_transform * vertices[polygon[corner + 1]]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var ac := Vector2(c.x - a.x, c.z - a.z)
				var ap := Vector2(point.x - a.x, point.z - a.z)
				var denominator := ab.cross(ac)
				if absf(denominator) < 0.000001: continue
				var u := ap.cross(ac) / denominator
				var v := ab.cross(ap) / denominator
				if u < -0.000001 or v < -0.000001 or u + v > 1.000001: continue
				var height := a.y + u * (b.y - a.y) + v * (c.y - a.y)
				var difference := absf(height - point.y)
				if difference < nearest_height:
					nearest_height = difference
					result = Vector3(point.x, height, point.z)
	return result
