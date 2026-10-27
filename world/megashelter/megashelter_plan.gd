extends RefCounted
class_name MegashelterPlan
## Pure, versioned assembly. Physics, visuals and neighbour navigation share this data.
const PROFILE = preload("res://world/megashelter/megashelter_profile.gd")
const KINDS := ["wall", "rib_wall", "corner", "pier", "beam", "vent", "entrance", "roof"]

static func generate(seed_value: int, template_override: int = -1, profile: MegashelterProfile = null) -> Dictionary:
	var settings := profile if profile != null else MegashelterProfile.new()
	if not settings.validate().is_empty():
		push_error("Invalid megashelter exterior profile")
		return {}
	var rng := _rng(seed_value, "massing")
	var template := rng.randi_range(0, 2) if template_override < 0 else clampi(template_override, 0, 2)
	var width := float(settings.widths[rng.randi_range(0, settings.widths.size() - 1)])
	var depth := float(settings.depths[rng.randi_range(0, settings.depths.size() - 1)])
	var height := float(settings.heights[rng.randi_range(0, settings.heights.size() - 1)])
	var volumes: Array[AABB] = []
	# Every tier rests on the full preceding tier. No detached or hollow masses.
	var y := 0.0
	while y < height - 0.01:
		var tier_height := minf(PROFILE.BAND, height - y)
		var inset := 0.0
		if template == 2: inset = minf(8.0, floorf(y / 27.0) * 4.0)
		var tier_width := width - inset * 2.0
		var tier_depth := depth - inset
		if template == 1 and y >= height - PROFILE.BAND:
			tier_width -= 16.0
		volumes.append(AABB(Vector3(-tier_width * 0.5, y, -tier_depth * 0.5), Vector3(tier_width, tier_height, tier_depth)))
		y += tier_height
	var plan := {"version": PROFILE.CONTENT_VERSION, "seed": seed_value, "template": template,
		"width": width, "depth": depth, "height": height, "volumes": volumes,
		"modules": [], "collision_boxes": volumes.duplicate(),
		"access_point": Vector3(0, 0.05, depth * 0.5 + 8.0)}
	var facade := _rng(seed_value, "facade")
	for index in range(volumes.size()):
		_facade(plan, volumes[index], index, facade)
	# Continuous tall piers establish the vertical residential-megastructure rhythm.
	for x: float in [-width * 0.5 + 0.75, -width / 6.0, width / 6.0, width * 0.5 - 0.75]:
		var pier_height := height - PROFILE.BAND if template == 1 and absf(x) > width * 0.5 - 9.0 else height
		if template == 2:
			pier_height = minf(height, 27.0) if absf(x) > width * 0.5 - 8.0 else height
		var pier_z := depth * 0.5 + 0.42
		if template == 2 and pier_height > 27.0: continue
		_add(plan, "pier", Vector3(x, 0, pier_z), Vector3(1.25, pier_height, 0.85), 0, 0)
		plan.collision_boxes.append(AABB(Vector3(x - 0.625, 0, pier_z - 0.85), Vector3(1.25, pier_height, 0.85)))
	var front := depth * 0.5
	_add(plan, "entrance", Vector3(0, 0, front + 3.0), Vector3(12, 9, 3), 0, 0)
	# Portal posts and lintel protrude; the closed leaves meet the solid backing.
	var boxes: Array = plan.collision_boxes
	boxes.append(AABB(Vector3(-6, 0, front), Vector3(1, 9, 3)))
	boxes.append(AABB(Vector3(5, 0, front), Vector3(1, 9, 3)))
	boxes.append(AABB(Vector3(-5, 7.5, front), Vector3(10, 1.5, 3)))
	var bounds := AABB(Vector3(-width * 0.5, -0.5, -depth * 0.5), Vector3(width, height + 1.2, depth))
	for module: Dictionary in plan.modules:
		var local := AABB(Vector3(-module.size.x * 0.5, 0, -module.size.z), module.size)
		bounds = bounds.merge(module.transform * local)
	plan.building_bounds = bounds.grow(0.3)
	var physical_bounds: AABB = plan.building_bounds
	plan.site_bounds = AABB(Vector3(physical_bounds.position.x - 12, -1, physical_bounds.position.z - 12),
		Vector3(physical_bounds.size.x + 24, physical_bounds.end.y + 1, physical_bounds.size.z + 36))
	return plan

static func _facade(plan: Dictionary, volume: AABB, tier: int, rng: RandomNumberGenerator) -> void:
	var surfaces := [
		[Vector3(volume.position.x, volume.position.y, volume.end.z), 0.0, volume.size.x],
		[Vector3(volume.end.x, volume.position.y, volume.position.z), PI, volume.size.x],
		[Vector3(volume.end.x, volume.position.y, volume.end.z), PI * 0.5, volume.size.z],
		[Vector3(volume.position.x, volume.position.y, volume.position.z), -PI * 0.5, volume.size.z]]
	for side in range(surfaces.size()):
		var origin: Vector3 = surfaces[side][0]
		var angle: float = surfaces[side][1]
		var run: float = surfaces[side][2]
		var basis := Basis(Vector3.UP, angle)
		var group_variant := rng.randi_range(0, 3)
		for row in range(roundi(volume.size.y / PROFILE.FLOOR)):
			for column in range(roundi(run / PROFILE.BAY)):
				var position := origin + basis * Vector3((column + 0.5) * PROFILE.BAY, row * PROFILE.FLOOR, 0)
				var kind := "wall"
				if column % 4 == 0: kind = "rib_wall"
				if row == 0 and tier > 0 and column % 6 == 3: kind = "vent"
				_add(plan, kind, position, Vector3(PROFILE.BAY, PROFILE.FLOOR, 0.4), angle, group_variant)
		# Dark horizontal transfer bands remain opaque, with a concrete lip above.
		_add(plan, "beam", origin + basis * Vector3(run * 0.5, 0, 0.16), Vector3(run, 0.55, 0.7), angle, 2)
		_add(plan, "beam", origin + basis * Vector3(run * 0.5, volume.size.y - 0.35, 0.18), Vector3(run, 0.35, 0.75), angle, 0)
	# Roof caps close every exposed setback. Full slabs also close the wall joints.
	_add(plan, "roof", Vector3(volume.get_center().x, volume.end.y, volume.end.z), Vector3(volume.size.x, 0.35, volume.size.z), 0, 0)
	for corner in range(4):
		var point := [Vector3(volume.end.x, volume.position.y, volume.end.z), Vector3(volume.end.x, volume.position.y, volume.position.z),
			Vector3(volume.position.x, volume.position.y, volume.position.z), Vector3(volume.position.x, volume.position.y, volume.end.z)][corner] as Vector3
		_add(plan, "corner", point, Vector3(0.6, volume.size.y, 0.6), corner * PI * 0.5, 0)

static func _add(plan: Dictionary, kind: String, position: Vector3, size: Vector3, angle: float, variant: int) -> void:
	plan.modules.append({"id": "%s_%04d" % [kind, plan.modules.size()], "kind": kind,
		"transform": Transform3D(Basis(Vector3.UP, angle), position), "size": size, "variant": variant})

static func _rng(seed_value: int, domain: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter:%d:%d:%s" % [PROFILE.CONTENT_VERSION, seed_value, domain]).hash()
	return rng
