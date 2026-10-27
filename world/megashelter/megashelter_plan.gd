extends RefCounted
class_name MegashelterPlan
## Pure, versioned assembly. Physics, visuals and neighbour navigation share this data.
const PROFILE = preload("res://world/megashelter/megashelter_profile.gd")
const KINDS := ["wall", "rib_wall", "corner", "pier", "beam", "vent", "entrance", "roof", "roof_plant", "drain"]

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
	# Broad concrete spines, rather than narrow trim, define the reference silhouette.
	for x: float in [-width * 0.5 + 2.2, -width / 6.0, width / 6.0, width * 0.5 - 2.2]:
		var pier_height := 0.0
		for volume: AABB in volumes:
			if x >= volume.position.x and x <= volume.end.x: pier_height = maxf(pier_height, volume.end.y)
		_add(plan, "pier", Vector3(x,0,depth*0.5+2.4), Vector3(4.0,pier_height+1.4,6.4),0,0,true)
	for x: float in [-width*0.5+6.0,width*0.5-6.0]:
		_add(plan,"drain",Vector3(x,0,depth*0.5+0.3),Vector3(0.4,16.0,0.4),0,0,true)
	var front := depth * 0.5
	_add(plan, "entrance", Vector3(0, 0, front + 3.0), Vector3(12, 9, 3), 0, 0)
	# Portal posts and lintel protrude; the closed leaves meet the solid backing.
	var boxes: Array = plan.collision_boxes
	boxes.append(AABB(Vector3(-6.09,0,front-0.06),Vector3(1.18,9,3.12)))
	boxes.append(AABB(Vector3(4.91,0,front-0.06),Vector3(1.18,9,3.12)))
	boxes.append(AABB(Vector3(-5,7.45,front-0.06),Vector3(10,1.55,3.12)))
	boxes.append(AABB(Vector3(-5,0,front),Vector3(7.95,7.15,1.0)))
	boxes.append(AABB(Vector3(3,0,front),Vector3(1.8,3.0,0.9)))
	# Existing project equipment sits on proper plinths, clear of parapets.
	_add(plan,"roof_plant",Vector3(-8,height+0.27,-1.7),Vector3(6.6,2.5,4.6),0,0,true)
	_add(plan,"roof_plant",Vector3(8,height+0.27,6.8),Vector3(9.6,2.0,5.6),0,1,true)
	var bounds := AABB(Vector3(-width * 0.5, -0.5, -depth * 0.5), Vector3(width, height + 1.2, depth))
	for module: Dictionary in plan.modules:
		var extent := module_bounds(module)
		bounds = bounds.merge(extent)
		if module.get("solid",false): boxes.append(extent)
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
		var recess := 1.7 if tier > 0 else 0.0
		for column in range(roundi(run / PROFILE.BAY)):
			var position := origin + basis * Vector3((column+0.5)*PROFILE.BAY,recess,0)
			_add(plan,"rib_wall" if column%4 == 0 else "wall",position,Vector3(PROFILE.BAY,volume.size.y-recess,2.2),angle,group_variant)
		# A genuinely recessed, sealed service belt separates the large blocks.
		if recess > 0:
			_add(plan,"beam",origin+basis*Vector3(run*0.5,0,-1.65),Vector3(run,recess,0.5),angle,2)
			for column: int in [1,maxi(2,roundi(run/4)-2)]:
				_add(plan,"vent",origin+basis*Vector3((column+0.5)*4,0.2,-1.4),Vector3(3.0,1.25,0.4),angle,1)
		_add(plan,"beam",origin+basis*Vector3(run*0.5,recess,0.18),Vector3(run,0.55,2.45),angle,0)
		_add(plan,"beam",origin+basis*Vector3(run*0.5,volume.size.y-0.32,0.16),Vector3(run,0.32,2.4),angle,0)
	# Roof caps close every exposed setback. Full slabs also close the wall joints.
	_add(plan, "roof", Vector3(volume.get_center().x, volume.end.y, volume.end.z), Vector3(volume.size.x, 0.75, volume.size.z), 0, 0)
	for corner in range(4):
		var point := [Vector3(volume.end.x, volume.position.y, volume.end.z), Vector3(volume.end.x, volume.position.y, volume.position.z),
			Vector3(volume.position.x, volume.position.y, volume.position.z), Vector3(volume.position.x, volume.position.y, volume.end.z)][corner] as Vector3
		_add(plan, "corner", point, Vector3(1.0, volume.size.y, 1.0), corner * PI * 0.5, 0)

static func _add(plan: Dictionary, kind: String, position: Vector3, size: Vector3, angle: float, variant: int, solid: bool = false) -> void:
	plan.modules.append({"id": "%s_%04d" % [kind, plan.modules.size()], "kind": kind,
		"transform": Transform3D(Basis(Vector3.UP, angle), position), "size": size, "variant": variant,"solid":solid})

static func module_bounds(module: Dictionary) -> AABB:
	var result := AABB()
	var first := true
	for piece: Dictionary in MegashelterKit.pieces(module.kind,module.size,module.variant):
		var bounds: AABB = module.transform * AABB(piece.center-piece.size*0.5,piece.size)
		result = bounds if first else result.merge(bounds)
		first = false
	return result

static func _rng(seed_value: int, domain: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Art revisions do not reroll a previously selected silhouette or dimensions.
	rng.seed = ("megashelter:%d:%d:%s" % [1 if domain == "massing" else PROFILE.CONTENT_VERSION, seed_value, domain]).hash()
	return rng
