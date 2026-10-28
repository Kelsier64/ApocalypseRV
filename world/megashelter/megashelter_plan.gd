extends RefCounted
class_name MegashelterPlan
## One connected footprint grammar, independent structure and facade choices.
const PROFILE = preload("res://world/megashelter/megashelter_profile.gd")
const KINDS := ["wall", "rib_wall", "corner", "pier", "beam", "vent", "entrance", "roof", "roof_plant", "drain", "service_spine", "buttress"]
const FOOTPRINT_NAMES := ["T", "L", "U", "H", "Cross", "Z", "Comb", "Offset"]

static func generate(seed_value: int, template_override: int = -1, profile: MegashelterProfile = null) -> Dictionary:
	var settings := profile if profile != null else MegashelterProfile.new()
	if not settings.validate().is_empty(): return {}
	var dimensions := _rng(seed_value,"massing")
	dimensions.randi_range(0,2) # Preserve dimension choices of existing seeds.
	var width := float(settings.widths[dimensions.randi_range(0,settings.widths.size()-1)])
	var depth := float(settings.depths[dimensions.randi_range(0,settings.depths.size()-1)])
	var height := float(settings.heights[dimensions.randi_range(0,settings.heights.size()-1)])
	var rng := _rng(seed_value,"architecture")
	var layout := rng.randi_range(0,7) if template_override < 0 else clampi(template_override,0,7)
	var nx := int(width/4)
	var nz := int(depth/4)
	var grid := _footprint(nx,nz,height,layout,rng)
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
	var plan := {"version":PROFILE.CONTENT_VERSION,"seed":seed_value,"template":layout,
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
	var bounds: AABB = volumes[0]
	for volume: AABB in volumes: bounds = bounds.merge(volume)
	for module: Dictionary in plan.modules:
		var extent := module_bounds(module)
		bounds = bounds.merge(extent)
		if module.get("solid",false): boxes.append(extent)
	plan.building_bounds = bounds.grow(0.3)
	var physical: AABB = plan.building_bounds
	plan.site_bounds = AABB(Vector3(physical.position.x-12,-1,physical.position.z-12),Vector3(physical.size.x+24,physical.end.y+1,physical.size.z+36))
	return plan

static func _footprint(nx: int,nz: int,height: float,layout: int,rng: RandomNumberGenerator) -> PackedFloat32Array:
	var grid := PackedFloat32Array()
	grid.resize(nx*nz)
	var wx := rng.randi_range(4,5)
	var wz := rng.randi_range(3,4)
	var cx := rng.randi_range(wx/2,nx-wx+wx/2)
	var cz := rng.randi_range(wz/2,nz-wz+wz/2)
	var rects: Array[Rect2i] = []
	match layout:
		0: rects = [Rect2i(0,0,nx,wz),Rect2i(cx-wx/2,wz,wx,nz-wz)]
		1: rects = [Rect2i(0,0,wx,nz),Rect2i(wx,nz-wz,nx-wx,wz)]
		2: rects = [Rect2i(0,0,nx,wz),Rect2i(0,wz,4,nz-wz),Rect2i(nx-4,wz,4,nz-wz)]
		3: rects = [Rect2i(0,0,4,nz),Rect2i(nx-4,0,4,nz),Rect2i(4,cz-wz/2,nx-8,wz)]
		4: rects = [Rect2i(cx-wx/2,0,wx,nz),Rect2i(0,cz-wz/2,nx,wz)]
		5: rects = [Rect2i(0,0,nx-4,wz),Rect2i(cx-wx/2,0,wx,nz),Rect2i(4,nz-wz,nx-4,wz)]
		6: rects = [Rect2i(0,0,nx,wz),Rect2i(0,wz,4,nz-wz),Rect2i(nx-4,wz,4,nz-wz),Rect2i(nx/2-2,wz,4,maxi(1,nz-wz-2))]
		7: rects = [Rect2i(0,0,nx-4,nz-wz),Rect2i(4,nz-wz,nx-4,wz),Rect2i(cx-wx/2,0,wx,nz)]
	var tallest := rng.randi_range(0,rects.size()-1)
	for index in range(rects.size()):
		var rect: Rect2i = rects[index]
		var h := height if index == tallest else maxf(27,height-rng.randi_range(1,3)*13.5)
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): grid[z*nx+x] = maxf(grid[z*nx+x],h)
	# Mirror the full composition; its entrance is derived from the resulting front.
	if rng.randf() < 0.5:
		for z in range(nz):
			for x in range(nx/2):
				var opposite := z*nx+nx-1-x
				var old := grid[z*nx+x]
				grid[z*nx+x] = grid[opposite]
				grid[opposite] = old
	return grid

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
			if level < h: _add(plan,"beam",origin+basis*Vector3(run/2,level,0.9),Vector3(run,1.3,3),angle,0,true)
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

static func _add(plan: Dictionary,kind: String,position: Vector3,size: Vector3,angle: float,variant: int,solid: bool = false) -> void:
	plan.modules.append({"id":"%s_%04d" % [kind,plan.modules.size()],"kind":kind,"transform":Transform3D(Basis(Vector3.UP,angle),position),"size":size,"variant":variant,"solid":solid})

static func module_bounds(module: Dictionary) -> AABB:
	var result := AABB()
	var first := true
	for piece: Dictionary in MegashelterKit.pieces(module.kind,module.size,module.variant):
		var bounds: AABB = module.transform*AABB(piece.center-piece.size*0.5,piece.size)
		result = bounds if first else result.merge(bounds)
		first = false
	return result

static func _rng(seed_value: int,domain: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("megashelter:%d:%d:%s" % [1 if domain == "massing" else PROFILE.CONTENT_VERSION,seed_value,domain]).hash()
	return rng
