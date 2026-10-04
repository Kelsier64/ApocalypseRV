extends SceneTree
## Offline authoring of one damaged 4.8 x 3.4 x 0.46 m wall sample.
const OUTPUT := "res://world/art_samples/ruined_wall_study.tscn"
const NX := 240
const NY := 170
var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var scene_root: Node3D
var concrete: ShaderMaterial

func _init() -> void:
	build.call_deferred()

func sample(x: float, y: float, scale := 1.0) -> float:
	return noise.get_noise_2d(x * scale, y * scale)

func top(x: float) -> float:
	return 3.4 - 0.08 * (sample(x, 9, 9) + 1.0) - 0.55 * exp(-pow((x-1.85)/0.42,2)) - 0.22 * exp(-pow((x+1.7)/0.33,2))

func scar(x: float, y: float) -> float:
	var warped_x:=x+sample(x+7,y,1.8)*0.4
	var warped_y:=y+sample(x,y+3,2.2)*0.3
	var main := Vector2((warped_x+0.45)/1.4,(warped_y-1.62)/1.17).length() + sample(x,y,3)*0.23 + sample(x,y,11)*0.035
	var secondary := Vector2((warped_x-1.3)/1.0,(warped_y-0.35)/0.8).length()+sample(x,y,3)*0.25
	var bridge := Vector2((warped_x-0.4)/0.63,(warped_y-0.9)/0.8).length()+sample(x,y,5)*0.15
	return 1.0-smoothstep(0.83,1.06,minf(main,minf(secondary,bridge)))

func front(x: float, y: float) -> Vector3:
	var damage := scar(x,y)
	var depth := damage * (0.23 + sample(x,y,18)*0.013)
	depth += maxf(0.0, (y-top(x)+0.12)/0.12)*0.035
	return Vector3(x,y,0.14-depth+sample(x,y,23)*0.0008)

func hole_distance(x: float, y: float) -> float:
	return Vector2((x+0.68+sample(x,y,3)*0.12)/0.50,(y-1.65)/0.59).length()+sample(x,y,5)*0.20-1.0

func own(node: Node, parent: Node = null) -> void:
	if parent == null: parent = scene_root
	parent.add_child(node)
	node.owner=scene_root

func mesh_node(name_value: String, verts: PackedVector3Array, indices: PackedInt32Array, colors: PackedColorArray, material: Material) -> MeshInstance3D:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0,indices.size(),3):
		var a:=indices[i]; var b:=indices[i+1]; var c:=indices[i+2]
		var normal := (verts[c]-verts[a]).cross(verts[b]-verts[a]).normalized()
		for j in [a,b,c]: normals[j]+=normal
	for i in range(normals.size()): normals[i]=normals[i].normalized()
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	if colors.size()==verts.size(): arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new()
	node.name=name_value
	node.mesh=mesh
	node.material_override=material
	own(node)
	return node

func wall() -> void:
	var verts:=PackedVector3Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var edges: Dictionary={}
	var cut_vertices: Dictionary={}
	for iy in range(NY+1):
		for ix in range(NX+1):
			var x:float=-2.4+4.8*ix/NX
			var y:float=top(x)*iy/NY
			verts.append(front(x,y))
			colors.append(Color(scar(x,y),0,0))
	for iy in range(NY):
		for ix in range(NX):
			var a:=iy*(NX+1)+ix
			var b:=a+1
			var c:=a+NX+1
			var d:=c+1
			for tri in [[a,c,b],[b,c,d]]:
				# Clip at the actual contour instead of removing whole stair-stepped cells.
				var polygon: Array[int]=[]
				for j in range(3):
					var ia:int=tri[j]; var ib:int=tri[(j+1)%3]
					var pa:=verts[ia]; var pb:=verts[ib]
					var da:=hole_distance(pa.x,pa.y); var db:=hole_distance(pb.x,pb.y)
					if da>=0: polygon.append(ia)
					if (da>=0)!=(db>=0):
						var cut_key:=Vector2i(mini(ia,ib),maxi(ia,ib))
						if not cut_vertices.has(cut_key):
							var point:=pa.lerp(pb,da/(da-db))
							cut_vertices[cut_key]=verts.size()
							verts.append(front(point.x,point.y))
							colors.append(Color(scar(point.x,point.y),0,0))
						polygon.append(cut_vertices[cut_key])
				if polygon.size()<3: continue
				for j in range(1,polygon.size()-1): indices.append_array([polygon[0],polygon[j],polygon[j+1]])
				for j in range(polygon.size()):
					var e:=[polygon[j],polygon[(j+1)%polygon.size()]]
					var key:=Vector2i(mini(e[0],e[1]),maxi(e[0],e[1]))
					if edges.has(key): edges.erase(key)
					else: edges[key]=e
	var front_indices:=indices.duplicate()
	var count:=verts.size()
	for i in range(count):
		verts.append(Vector3(verts[i].x,verts[i].y,-0.32))
		colors.append(Color(0.25,0,0))
	for i in range(0,front_indices.size(),3):
		indices.append_array([front_indices[i+2]+count,front_indices[i+1]+count,front_indices[i]+count])
	var side_vertices: Dictionary={}
	for edge in edges.values():
		var a:int=edge[0]; var b:int=edge[1]
		# Sidewall normals are shared along the contour; the front lip remains sharp.
		for index in [a,b]:
			if not side_vertices.has(index):
				side_vertices[index]=verts.size()
				verts.append(verts[index]); colors.append(Color(1,0,0))
				verts.append(verts[index+count]); colors.append(Color(1,0,0))
		var sa:int=side_vertices[a]; var sb:int=side_vertices[b]
		indices.append_array([sb,sa,sa+1,sb,sa+1,sb+1])
	mesh_node("FracturedConcrete",verts,indices,colors,concrete)

func rebars() -> void:
	var verts:=PackedVector3Array()
	var indices:=PackedInt32Array()
	for rod in range(11):
		var vertical:=rod<7
		var start:=Vector3(-1.8+rod*0.43,0.35,-0.075) if vertical else Vector3(-2.05,0.75+(rod-7)*0.53,-0.115)
		var finish:=start+Vector3(0,2.75,0) if vertical else start+Vector3(3.35,0,0)
		var length:=start.distance_to(finish)
		var rings:=int(length/0.008)
		var axis:=(finish-start).normalized()
		var across:=Vector3.RIGHT if vertical else Vector3.UP
		var forward:=axis.cross(across)
		var first:=verts.size()
		for ring in range(rings+1):
			var t:=float(ring)/rings
			var center:=start.lerp(finish,t)
			center.z+=sin(t*PI)*0.022*sin(rod*1.7)
			for side in range(10):
				var angle:=TAU*side/10.0
				var rib:=pow(maxf(0,sin(t*length/0.026*TAU+angle*1.8)),6)
				var radius:=0.0105+0.0026*rib
				verts.append(center+(cos(angle)*across+sin(angle)*forward)*radius)
				if ring<rings:
					var a:=first+ring*10+side
					var b:=first+ring*10+(side+1)%10
					indices.append_array([a,a+10,b,b,a+10,b+10])
	var rust:ShaderMaterial=load("res://world/starting_shelter/materials/aged_metal.tres").duplicate()
	rust.set_shader_parameter("metal_color",Color("514039"))
	rust.set_shader_parameter("corrosion",1.0)
	mesh_node("ExposedRibbedRebar",verts,indices,PackedColorArray(),rust)

func rubble() -> void:
	var verts:=PackedVector3Array()
	var indices:=PackedInt32Array()
	var colors:=PackedColorArray()
	for piece in range(32):
		var sphere:=SphereMesh.new()
		sphere.radial_segments=7
		sphere.rings=3
		var arrays:=sphere.get_mesh_arrays()
		var raw:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var raw_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var size:=Vector3(rng.randf_range(0.09,0.38),rng.randf_range(0.035,0.12),rng.randf_range(0.08,0.3))
		var origin:=Vector3(rng.randf_range(-2.2,1.95),size.y*0.55,rng.randf_range(0.2,1.1))
		var rotation:=Basis(Vector3.UP,rng.randf()*TAU)
		var offset:=verts.size()
		for p in raw:
			var jitter:=0.9+sample(p.x+piece,p.y+p.z,12)*0.25
			verts.append(origin+rotation*(p*size*jitter))
			colors.append(Color(0.8,0,0))
		for i in raw_indices: indices.append(offset+i)
	mesh_node("FallenConcrete",verts,indices,colors,concrete)

func cracks() -> void:
	var verts:=PackedVector3Array()
	var indices:=PackedInt32Array()
	var paths: Array=[
		[Vector2(0.72,2.47),Vector2(0.95,2.69),Vector2(1.08,2.74),Vector2(1.02,2.88),Vector2(1.28,3.01),Vector2(1.4,3.23)],
		[Vector2(1.04,2.77),Vector2(1.27,2.72),Vector2(1.43,2.8),Vector2(1.7,2.75)],
		[Vector2(-1.61,1.25),Vector2(-1.92,1.04),Vector2(-1.87,0.82),Vector2(-2.03,0.62),Vector2(-1.98,0.36),Vector2(-2.17,0.05)],
		[Vector2(0.62,1.25),Vector2(0.91,1.09),Vector2(0.86,0.91),Vector2(1.1,0.8)],
		[Vector2(-1.51,2.22),Vector2(-1.76,2.52),Vector2(-1.83,2.72),Vector2(-2.06,2.83),Vector2(-2.15,3.15)]]
	for path in paths:
		for j in range(path.size()-1):
			var from:Vector2=path[j]; var to:Vector2=path[j+1]
			var steps:=int(from.distance_to(to)/0.015)+1
			for step in range(steps):
				var a:=from.lerp(to,float(step)/steps)
				var b:=from.lerp(to,float(step+1)/steps)
				var side:=(to-from).orthogonal().normalized()*(0.003+0.002*sample(a.x,a.y,33))
				var offset:=verts.size()
				for p in [a-side,a+side,b+side,b-side]: verts.append(front(p.x,p.y)+Vector3(0,0,0.0015))
				indices.append_array([offset,offset+2,offset+1,offset,offset+3,offset+2])
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("29251e")
	mat.roughness=1.0
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var node:=mesh_node("BranchingCracks",verts,indices,PackedColorArray(),mat)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func build() -> void:
	if "--write" not in OS.get_cmdline_user_args():
		print("Use -- --write to author the standalone ruined wall study")
		quit(); return
	noise.seed=812903
	noise.frequency=1.0
	noise.fractal_octaves=3
	rng.seed=81003
	scene_root=Node3D.new()
	scene_root.name="RuinedWallStudy"
	scene_root.set_script(load("res://world/art_samples/ruined_wall_study.gd"))
	concrete=ShaderMaterial.new()
	concrete.shader=load("res://assets/materials/ruined_wall/concrete.gdshader")
	concrete.set_shader_parameter("aggregate_texture",load("res://assets/materials/ruined_wall/aggregate_albedo.png"))
	concrete.set_shader_parameter("cement_texture",load("res://assets/materials/poi_kit/concrete_albedo.png"))
	wall(); rebars(); rubble(); cracks()
	var floor_node:=MeshInstance3D.new()
	floor_node.name="Ground"
	var floor_mesh:=PlaneMesh.new()
	floor_mesh.size=Vector2(200,200)
	floor_node.mesh=floor_mesh
	var floor_mat:=StandardMaterial3D.new()
	floor_mat.albedo_color=Color("20201e")
	floor_mat.roughness=0.98
	floor_node.material_override=floor_mat
	own(floor_node)
	var backdrop:=MeshInstance3D.new()
	backdrop.name="DarkBackdrop"
	var backdrop_mesh:=BoxMesh.new()
	backdrop_mesh.size=Vector3(40,16,0.2)
	backdrop.mesh=backdrop_mesh
	backdrop.position=Vector3(0,7.9,-4)
	backdrop.material_override=floor_mat
	own(backdrop)
	var environment:=WorldEnvironment.new()
	environment.name="Environment"
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("181b20")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("a7b6cc")
	environment.environment.ambient_light_energy=0.55
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_ACES
	environment.environment.ssao_enabled=true
	environment.environment.ssao_radius=0.12
	environment.environment.ssao_intensity=0.55
	own(environment)
	var key:=DirectionalLight3D.new()
	key.name="SoftSideLight"
	key.rotation_degrees=Vector3(-32,-36,0)
	key.light_color=Color("fff0db")
	key.light_energy=0.95
	key.shadow_enabled=true
	own(key)
	var fill:=OmniLight3D.new()
	fill.name="CoolFill"
	fill.position=Vector3(-3,3,4)
	fill.light_color=Color("adbed5")
	fill.light_energy=1.5
	fill.omni_range=10
	own(fill)
	for entry in [["Wide",Vector3(3,2.45,5.8),Vector3(0,1.6,0),44.0],["Detail",Vector3(0.5,2.0,3.0),Vector3(-0.5,1.7,-0.06),44.0]]:
		var camera:=Camera3D.new()
		camera.name=entry[0]
		camera.position=entry[1]
		camera.basis=Basis.looking_at(Vector3(entry[2])-camera.position)
		camera.fov=entry[3]
		camera.current=entry[0]=="Wide"
		own(camera)
	var packed:=PackedScene.new()
	var error:=packed.pack(scene_root)
	if error==OK: error=ResourceSaver.save(packed,OUTPUT)
	print("WALL_AUTHOR: ",OUTPUT," result=",error)
	scene_root.free()
	quit(0 if error==OK else 1)
