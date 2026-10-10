extends RefCounted
## Test-only deadlines. These waits observe engine work without changing its rate.

static func until(tree: SceneTree, predicate: Callable, timeout_ms := 60000, physics := false) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(timeout_ms, 0)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		if physics:
			await tree.physics_frame
		else:
			await tree.process_frame
	return true

static func navigation_ready(tree: SceneTree, chunks: Array, timeout_ms := 60000) -> bool:
	return await until(tree, func() -> bool:
		for chunk in chunks:
			if not is_instance_valid(chunk) or not chunk.navigation_ready:
				return false
		return true, timeout_ms, true)

static func generator_idle(tree: SceneTree, generator: Node, timeout_ms := 60000) -> bool:
	return await until(tree, func() -> bool:
		if not is_instance_valid(generator) or generator.building:
			return false
		for entry in generator.active_chunks:
			if not is_instance_valid(entry.node) or not entry.node.navigation_ready:
				return false
		return not generator.active_chunks.is_empty(), timeout_ms, true)

static func navigation_bakes_finished(tree: SceneTree, owner: Node, timeout_ms := 60000) -> bool:
	return await until(tree, func() -> bool:
		if not is_instance_valid(owner): return true
		for region in owner.find_children("*", "NavigationRegion3D", true, false):
			var mesh: NavigationMesh = region.get_meta("pending_navigation_bake", region.navigation_mesh)
			if mesh != null and NavigationServer3D.is_baking_navigation_mesh(mesh):
				return false
		return true, timeout_ms)

static func retired_candidates(tree: SceneTree, checkpoint: Node, timeout_ms := 60000) -> bool:
	return await until(tree, func() -> bool:
		if not is_instance_valid(checkpoint): return true
		for child in checkpoint.get_children():
			if child is SubViewport: return false
		return true, timeout_ms)
