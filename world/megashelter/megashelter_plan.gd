extends RefCounted
class_name MegashelterPlan
## Seeded frontier growth; no named or preselected building footprints.
const PROFILE = preload("res://world/megashelter/megashelter_profile.gd")
const KINDS := ["wall", "rib_wall", "corner", "pier", "beam", "vent", "entrance", "roof", "roof_plant", "drain", "service_spine", "buttress", "service_cabinet", "pipe_manifold", "intake_hood", "wall_salvage", "portal_canopy", "service_fan"]

static func generate(seed_value: int, profile: MegashelterProfile = null) -> Dictionary:
	var settings := profile if profile != null else MegashelterProfile.new()
	if not settings.validate().is_empty(): return {}
	var dimensions := _rng(seed_value,"massing")
	dimensions.randi_range(0,2) # Preserve dimension choices of existing seeds.
	var width := float(settings.widths[dimensions.randi_range(0,settings.widths.size()-1)])
	var depth := float(settings.depths[dimensions.randi_range(0,settings.depths.size()-1)])
	var height := float(settings.heights[dimensions.randi_range(0,settings.heights.size()-1)])
	var rng := _rng(seed_value,"architecture")
	var nx := int(width/4)
	var nz := int(depth/4)
	var growth := _grow(nx,nz,height,_rng(seed_value,"growth"))
	var grid: PackedFloat32Array = growth.grid
	var volumes := _rectangles(grid,nx,nz,width,depth)
	var entry_x := 0.0
	var best := 0
	var start := 0
	while start < nx:
		if grid[(nz-1)*nx+start] == 0: start += 1; continue
		var end := start
		while end < nx and grid[(nz-1)*nx+end] > 0: end += 1
		if end-start > best:
			best = end-start
			entry_x = -width/2 + (start+end)*2.0
		start = end
	var plan := {"version":PROFILE.CONTENT_VERSION,"seed":seed_value,"growth_steps":growth.steps,
		"width":width,"depth":depth,"height":height,"style":rng.randi_range(0,2),
		"structure":rng.randi_range(0,4),"rhythm":rng.randi_range(2,4),
		"volumes":volumes,"modules":[],"collision_boxes":volumes.duplicate(),
		"access_point":Vector3(entry_x,0.05,depth/2+10)}
	# Trace the exposed boundary at each band, including courtyard returns.
	var y := 0.0
	while y < height-0.01:
		var band_height := minf(PROFILE.BAND,height-y)
		for volume: AABB in volumes:
			if volume.end.y > y+0.01: band_height = minf(band_height,volume.end.y-y)
		for side in range(4):
			var across := nx if side < 2 else nz
			var rows := nz if side < 2 else nx
			for row in range(rows):
				var column := 0
				while column < across:
					if not _exposed(grid,nx,nz,side,row,column,y): column += 1; continue
					var first := column
					while column < across and _exposed(grid,nx,nz,side,row,column,y): column += 1
					var angle: float = [0.0,PI,PI*0.5,-PI*0.5][side]
					var origin: Vector3
					match side:
						0: origin = Vector3(first*4-width/2,y,(row+1)*4-depth/2)
						1: origin = Vector3(column*4-width/2,y,row*4-depth/2)
						2: origin = Vector3((row+1)*4-width/2,y,column*4-depth/2)
						_: origin = Vector3(row*4-width/2,y,first*4-depth/2)
					_facade_run(plan,origin,angle,(column-first)*4.0,band_height,y,rng)
		# Close convex corners where the two outward-offset facade runs stop.
		for gz in range(nz+1):
			for gx in range(nx+1):
				var occupied: Array[Vector2i] = []
				for offset: Vector2i in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(0,0)]:
					var cell := Vector2i(gx,gz)+offset
					if cell.x >= 0 and cell.y >= 0 and cell.x < nx and cell.y < nz and grid[cell.y*nx+cell.x] > y:
						occupied.append(offset)
				if occupied.size() == 1:
					var direction := Vector2(1 if occupied[0].x < 0 else -1,1 if occupied[0].y < 0 else -1)
					_add(plan,"pier",Vector3(gx*4-width/2+direction.x*1.05,y,gz*4-depth/2+direction.y*1.05+1.1),Vector3(2.2,band_height,2.2),0,0,true)
		y += band_height
	var roof_count := 0
	for volume: AABB in volumes:
		_add(plan,"roof",Vector3(volume.get_center().x,volume.end.y,volume.end.z),Vector3(volume.size.x,0.75,volume.size.z),0,0)
	for step: Dictionary in growth.steps:
		var rect: Rect2i = step.rect
		var volume := AABB(Vector3(rect.position.x*4-width/2,0,rect.position.y*4-depth/2),Vector3(rect.size.x*4,step.height,rect.size.y*4))
		# Leave >=3.3m around equipment for adjacent taller facade/structure returns.
		if volume.size.x >= 16 and volume.size.z >= 12 and roof_count < 4:
			var equipment := rng.randi_range(0,1) if volume.size.x >= 20 and volume.size.z >= 16 else 0
			var size := Vector3(6.6,2.5,4.6) if equipment == 0 else Vector3(9.6,2,5.6)
			_add(plan,"roof_plant",Vector3(volume.get_center().x,volume.end.y+0.27,volume.get_center().z+size.z/2),size,0,equipment,true)
			roof_count += 1
	var front := depth/2+2.2
	_add(plan,"entrance",Vector3(entry_x,0,front+3),Vector3(12,9,3),0,int(plan.style))
	var boxes: Array = plan.collision_boxes
	for box: AABB in [AABB(Vector3(-6.09,0,-0.06),Vector3(1.18,9,3.12)),AABB(Vector3(4.91,0,-0.06),Vector3(1.18,9,3.12)),AABB(Vector3(-5,7.45,-0.06),Vector3(10,1.55,3.12)),AABB(Vector3(-5,0,-2.25),Vector3(10,7.45,3.25))]:
		boxes.append(AABB(box.position+Vector3(entry_x,0,front),box.size))
	for x: float in [-7.0,7.0]:
		_add(plan,"drain",Vector3(entry_x+x,0,front+0.1),Vector3(0.4,12,0.4),0,0,true)
	_ground_details(plan)
	_repair_details(plan)
	var bounds: AABB = volumes[0]
	for volume: AABB in volumes: bounds = bounds.merge(volume)
	for module: Dictionary in plan.modules:
		var extent := module_bounds(module)
		bounds = bounds.merge(extent)
		if module.get("solid",false): boxes.append(extent)
	var forecourt_pose := Transform3D(Basis.IDENTITY,Vector3(entry_x,0,depth/2+5.2))
	for piece: Dictionary in MegashelterDetails.forecourt(seed_value):
		var pose := forecourt_pose*Transform3D(piece.get("basis",Basis.IDENTITY),piece.center)
		bounds = bounds.merge(pose*AABB(-piece.size/2,piece.size))
	plan.building_bounds = bounds.grow(0.3)
	var physical: AABB = plan.building_bounds
	plan.site_bounds = AABB(Vector3(-width/2-12,-1,-depth/2-12),Vector3(width+24,physical.end.y+1,depth+42)).merge(physical)
	return plan

static func _grow(nx: int,nz: int,height: float,rng: RandomNumberGenerator) -> Dictionary:
	var core_size := Vector2i(rng.randi_range(4,5),rng.randi_range(3,4))
	var core := Rect2i(rng.randi_range(0,nx-core_size.x),nz-core_size.y,core_size.x,core_size.y)
	var steps: Array[Dictionary] = [{"rect":core,"parent":-1,"height":0.0}]
	var area := core.get_area()
	var target_area := roundi(nx*nz*rng.randf_range(0.48,0.78))
	var target_count := rng.randi_range(4,10)
	# New rooms/wing sections attach to a random existing face. Their offsets,
	# aspect ratios and branching order are sampled; no complete plan is stored.
	for attempt in range(240):
		if steps.size() >= target_count or area >= target_area: break
		var parent := rng.randi_range(0,steps.size()-1)
		var anchor: Rect2i = steps[parent].rect
		var size := Vector2i(rng.randi_range(3,6),rng.randi_range(2,5))
		var candidate := Rect2i(Vector2i.ZERO,size)
		match rng.randi_range(0,3):
			0: candidate.position = Vector2i(anchor.end.x,rng.randi_range(anchor.position.y-size.y+2,anchor.end.y-2))
			1: candidate.position = Vector2i(anchor.position.x-size.x,rng.randi_range(anchor.position.y-size.y+2,anchor.end.y-2))
			2: candidate.position = Vector2i(rng.randi_range(anchor.position.x-size.x+2,anchor.end.x-2),anchor.position.y-size.y)
			3: candidate.position = Vector2i(rng.randi_range(anchor.position.x-size.x+2,anchor.end.x-2),anchor.end.y)
		if not Rect2i(0,0,nx,nz).encloses(candidate): continue
		if area+candidate.get_area() > nx*nz*0.85: continue
		var fits := true
		for step: Dictionary in steps:
			if candidate.intersects(step.rect): fits = false; break
		if not fits or not _clear_growth(steps,candidate,nx,nz): continue
		steps.append({"rect":candidate,"parent":parent,"height":0.0})
		area += candidate.get_area()
	# Masses have individual roof heights; every addition remains ground-supported.
	var tallest := rng.randi_range(0,steps.size()-1)
	var grid := PackedFloat32Array()
	grid.resize(nx*nz)
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		var parent_height := height if step.parent < 0 else float(steps[step.parent].height)
		var roof := clampf(parent_height+rng.randi_range(-2,1)*PROFILE.BAND,27,height)
		step.height = height if index == tallest else roof
		var rect: Rect2i = step.rect
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): grid[z*nx+x] = step.height
	return {"grid":grid,"steps":steps}

static func _clear_growth(steps: Array[Dictionary],candidate: Rect2i,nx: int,nz: int) -> bool:
	var mask := PackedByteArray()
	mask.resize(nx*nz)
	var rectangles: Array[Rect2i] = [candidate]
	for step: Dictionary in steps: rectangles.append(step.rect)
	for rect: Rect2i in rectangles:
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): mask[z*nx+x] = 1
	for z in range(nz):
		for x in range(nx):
			if mask[z*nx+x]: continue
			# A 4m slit cannot fit two projecting facades; retain >=8m recesses.
			if x > 0 and x < nx-1 and mask[z*nx+x-1] and mask[z*nx+x+1]: return false
			if z > 0 and z < nz-1 and mask[(z-1)*nx+x] and mask[(z+1)*nx+x]: return false
			# Point-only corner contacts would leave ambiguous contour junctions.
			if x < nx-1 and z < nz-1 and mask[(z+1)*nx+x+1] == 0 and mask[z*nx+x+1] and mask[(z+1)*nx+x]: return false
			if x > 0 and z < nz-1 and mask[(z+1)*nx+x-1] == 0 and mask[z*nx+x-1] and mask[(z+1)*nx+x]: return false
	return true

static func _rectangles(grid: PackedFloat32Array,nx: int,nz: int,width: float,depth: float) -> Array[AABB]:
	var used := PackedByteArray()
	used.resize(grid.size())
	var result: Array[AABB] = []
	for z in range(nz):
		for x in range(nx):
			var h := grid[z*nx+x]
			if h == 0 or used[z*nx+x]: continue
			var ex := x+1
			while ex < nx and grid[z*nx+ex] == h and not used[z*nx+ex]: ex += 1
			var ez := z+1
			while ez < nz:
				var valid := true
				for xx in range(x,ex):
					if grid[ez*nx+xx] != h or used[ez*nx+xx]: valid = false; break
				if not valid: break
				ez += 1
			for zz in range(z,ez):
				for xx in range(x,ex): used[zz*nx+xx] = 1
			result.append(AABB(Vector3(x*4-width/2,0,z*4-depth/2),Vector3((ex-x)*4,h,(ez-z)*4)))
	return result

static func _exposed(grid: PackedFloat32Array,nx: int,nz: int,side: int,row: int,column: int,y: float) -> bool:
	var x := column if side < 2 else row
	var z := row if side < 2 else column
	if grid[z*nx+x] <= y: return false
	var neighbor: Vector2i = [Vector2i(0,1),Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0)][side]
	x += neighbor.x
	z += neighbor.y
	return x < 0 or z < 0 or x >= nx or z >= nz or grid[z*nx+x] <= y

static func _facade_run(plan: Dictionary,edge: Vector3,angle: float,run: float,h: float,y: float,rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP,angle)
	var origin := edge+basis*Vector3(0,0,2.15)
	var recess := 1.4 if y > 0 else 0.0
	var rhythm := int(plan.rhythm)
	for column in range(roundi(run/4)):
		var position := origin+basis*Vector3((column+0.5)*4,recess,0)
		_add(plan,"rib_wall" if column%rhythm == 0 else "wall",position,Vector3(4,h-recess,2.2),angle,rng.randi_range(0,7))
		if recess > 0 and column%2 == 0:
			_add(plan,"vent",origin+basis*Vector3((column+0.5)*4,0.1,-1.35),Vector3(3,1.2,0.4),angle,int(plan.style))
	_add(plan,"beam",origin+basis*Vector3(run/2,0,-1.6),Vector3(run,maxf(recess,0.2),0.55),angle,2)
	_add(plan,"beam",origin+basis*Vector3(run/2,h-0.4,0.15),Vector3(run,0.4,2.4),angle,0)
	# A thin exterior collision strip covers facade thickness without filling courts.
	plan.collision_boxes.append(Transform3D(basis,origin)*AABB(Vector3(0,0,-2.2),Vector3(run,h,2.4)))
	var structure := int(plan.structure)
	if structure == 3:
		for level: float in [3.0,8.5]:
			if level < h: _reinforcement_beam(plan,Transform3D(basis,origin+basis*Vector3(0,level,0.9)),run,angle)
	for column in range(roundi(run/4)):
		if column%rhythm != 0: continue
		var p := origin+basis*Vector3((column+0.5)*4,0,0.8)
		if absf(p.x-plan.access_point.x) < 7.5 and p.z > float(plan.depth)/2-1: continue
		match structure:
			0: _add(plan,"pier",p,Vector3(2.4,h+0.35,3),angle,0,true)
			1: _add(plan,"buttress",p,Vector3(2.8,h,3.2),angle,0,true)
			2:
				for offset: float in [-1.0,1.0]: _add(plan,"pier",p+basis*Vector3(offset,0,0),Vector3(0.65,h,1.5),angle,1,true)
			3:
				_add(plan,"pier",p,Vector3(1.1,h,1.8),angle,2,true)
			4:
				_add(plan,"service_spine",p,Vector3(2.6,h,1),angle,int(plan.style)%2,true)
				_add(plan,"drain",p+basis*Vector3(1.5,0,0),Vector3(0.4,h,0.4),angle,0,true)

static func _reinforcement_beam(plan: Dictionary, pose: Transform3D, run: float, angle: float) -> void:
	# Reserve the whole authored 12m x 9m portal, including its frame, rather
	# than only the access marker. Work in facade coordinates for every facing.
	var portal := AABB(Vector3(plan.access_point.x-6.2,-0.1,float(plan.depth)/2+2.1),Vector3(12.4,9.2,3.2))
	var local_portal: AABB = pose.affine_inverse() * portal
	var sections: Array[Vector2] = [Vector2(0,run)]
	if AABB(Vector3(0,0,-3),Vector3(run,1.3,3)).intersects(local_portal):
		sections = [Vector2(0,clampf(local_portal.position.x-0.05,0,run)),
			Vector2(clampf(local_portal.end.x+0.05,0,run),run)]
	for section: Vector2 in sections:
		var length := section.y-section.x
		if length <= 0.01: continue
		# Each remaining segment owns matching visual geometry and solid bounds.
		_add(plan,"beam",pose*Vector3((section.x+section.y)/2,0,0),Vector3(length,1.3,3),angle,0,true)

static func _add(plan: Dictionary,kind: String,position: Vector3,size: Vector3,angle: float,variant: int,solid: bool = false) -> void:
	plan.modules.append({"id":"%s_%04d" % [kind,plan.modules.size()],"kind":kind,"transform":Transform3D(Basis(Vector3.UP,angle),position),"size":size,"variant":variant,"solid":solid})

static func _ground_details(plan: Dictionary) -> void:
	var rng := _rng(plan.seed,"ground_details")
	var obstacles: Array[AABB] = []
	for bounds: AABB in plan.collision_boxes:
		if bounds.position.y < 8.0: obstacles.append(bounds)
	var anchors: Array[Dictionary] = []
	for module: Dictionary in plan.modules:
		if module.get("solid",false) and module.transform.origin.y < 8.0: obstacles.append(module_bounds(module))
		if module.kind in ["wall","rib_wall"] and module.transform.origin.y < 0.01:
			anchors.append(module)
	# Shuffle ties, then favour the entrance-facing facade and its visible returns.
	for index in range(anchors.size()-1,0,-1):
		var other := rng.randi_range(0,index)
		var swap := anchors[index]
		anchors[index] = anchors[other]
		anchors[other] = swap
	anchors.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return a.transform.origin.distance_squared_to(plan.access_point) < b.transform.origin.distance_squared_to(plan.access_point))
	var portal := AABB(Vector3(plan.access_point.x-6.5,0,float(plan.depth)/2+1.9),Vector3(13,9.1,8.1))
	var placements: Array[Vector3] = []
	var reserved_approaches: Array[AABB] = []
	var kinds := ["service_cabinet","pipe_manifold","intake_hood","wall_salvage"]
	var sizes := [Vector3(3.2,6.0,1.3),Vector3(3.0,7.1,1.2),Vector3(3.5,5.7,1.4),Vector3(2.8,3.2,1.6)]
	if plan.structure == 3: sizes[0].y = 2.7
	var offset := rng.randi_range(0,kinds.size()-1)
	for anchor: Dictionary in anchors:
		if placements.size() >= 10: break
		var nearby := false
		for placed: Vector3 in placements:
			if placed.distance_to(anchor.transform.origin) < 7.5: nearby = true; break
		if nearby: continue
		# Try another assembly if a deep unit cannot fit a concave return.
		for attempt in range(kinds.size()):
			var choice := (offset+placements.size()+attempt)%kinds.size()
			var size: Vector3 = sizes[choice]
			var pose: Transform3D = anchor.transform * Transform3D(Basis.IDENTITY,Vector3(0,0,size.z+0.02))
			var candidate := {"id":"%s_%04d" % [kinds[choice],plan.modules.size()],"kind":kinds[choice],"transform":pose,"size":size,"variant":rng.randi_range(0,3),"solid":true,"decoration_anchor":anchor.id}
			var bounds := module_bounds(candidate)
			if bounds.intersects(portal): continue
			# Mounting plates may meet the facade skin. All projecting geometry
			# beyond its first 36cm must clear columns, returns and earlier fixtures.
			var local_bounds: AABB = pose.affine_inverse()*bounds
			var far_end := local_bounds.end.z
			local_bounds.position.z = maxf(local_bounds.position.z,-size.z+0.36)
			local_bounds.size.z = far_end-local_bounds.position.z
			var clearance: AABB = pose*local_bounds
			# Keep a visible, walk-up maintenance apron in front of each group.
			# This also avoids hiding focal machines deep in narrow courtyards.
			var approach: AABB = pose*AABB(Vector3(-size.x/2,0,0.2),Vector3(size.x,3.0,7.0))
			var blocked := false
			for reserved: AABB in reserved_approaches:
				if reserved.intersects(bounds): blocked = true; break
			for obstacle: AABB in obstacles:
				if clearance.grow(0.12).intersects(obstacle) or approach.intersects(obstacle): blocked = true; break
			if blocked: continue
			candidate["clearance_bounds"] = clearance
			candidate["approach_bounds"] = approach
			plan.modules.append(candidate)
			obstacles.append(bounds)
			reserved_approaches.append(approach)
			placements.append(anchor.transform.origin)
			# The dedicated service group replaces the old isolated cover below it.
			if anchor.variant >= 4 and anchor.variant != 7: anchor.variant = 0
			break
	# The portal itself carries a broad, ribbed rain canopy with dead downlights.
	_add(plan,"portal_canopy",Vector3(plan.access_point.x,9.02,float(plan.depth)/2+6.5),Vector3(11.8,0.9,4.5),0,0,true)

## Keep the original per-bay repair slots; choose new models independently.
static func _repair_details(plan: Dictionary) -> void:
	var obstacles: Array[AABB] = []
	obstacles.assign(plan.collision_boxes)
	for module: Dictionary in plan.modules:
		if module.get("solid",false): obstacles.append(module_bounds(module))
	for module: Dictionary in plan.modules:
		if module.kind not in ["wall","rib_wall"] or module.variant not in [4,5,6]: continue
		var code := posmod(("repair-model:%d:%s" % [plan.seed,module.id]).hash(),65521)
		var repair_variant := 8+code%1536
		var blocked := false
		var inverse: Transform3D = module.transform.affine_inverse()
		for piece: Dictionary in MegashelterDetails.wall_panels(module.size,repair_variant,module.variant):
			var pose: Transform3D = module.transform*Transform3D(piece.get("basis",Basis.IDENTITY),piece.center)
			var bounds: AABB = pose*AABB(-piece.size/2,piece.size)
			for obstacle: AABB in obstacles:
				if not bounds.grow(0.015).intersects(obstacle): continue
				# Flush fittings can occupy the backing wall's collision skin.
				var local: AABB = inverse*obstacle
				if absf(local.position.z+2.2) < 0.005 and absf(local.end.z-0.2) < 0.005 and local.has_point(Vector3(0,module.size.y/2,0)): continue
				blocked = true
				break
			if blocked: break
		# Retain the small original cover where a larger assembly cannot fit.
		if not blocked: module["repair_variant"] = repair_variant

static func module_bounds(module: Dictionary) -> AABB:
	var result := AABB()
	var first := true
	for piece: Dictionary in MegashelterKit.pieces(module.kind,module.size,module.variant,module.get("repair_variant",-1)):
		var pose: Transform3D = module.transform*Transform3D(piece.get("basis",Basis.IDENTITY),piece.center)
		var bounds: AABB = pose*AABB(-piece.size*0.5,piece.size)
		result = bounds if first else result.merge(bounds)
		first = false
	return result

static func _rng(seed_value: int,domain: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Dressing revisions never reroll approved silhouettes or roof layouts.
	var version := 1 if domain == "massing" else (5 if domain in ["growth","architecture"] else PROFILE.CONTENT_VERSION)
	rng.seed = ("megashelter:%d:%d:%s" % [version,seed_value,domain]).hash()
	return rng
