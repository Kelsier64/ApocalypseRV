extends SceneTree
## Native pixel regression for a real plume and production seated camera.
const EFFECT := preload("res://enemies/barrel_explosion_effect.gd")
const RV := preload("res://rv/new_rv.tscn")
const PLAYER := preload("res://player/player.tscn")
const OUTPUT := "res://.godot/barrel-blast-render/"
var failures: Array[String] = []
var viewport: SubViewport
var world: Node3D
var effect: Node3D
var driver_camera: Camera3D

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count := 3) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func render_frame() -> Image:
	# Let both opaque depth and transparent volumes reach the viewport texture.
	for frame in 3: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func solid(size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	world.add_child(mesh)
	mesh.position = position
	return mesh

func plume_age(age: float) -> void:
	effect.set("age",age)
	effect.call("_update_visuals")
	# Compare only the production volume rendering: flash lights, sparks and
	# solid debris cannot stand in for missing fire in the camera regression.
	for child in effect.get_children():
		if child is Node3D and child.name not in ["FuelFire","RollingSoot"]:
			child.visible = false

func volume_visible(value: bool) -> void:
	effect.get_node("FuelFire").visible = value
	effect.get_node("RollingSoot").visible = value

func compare_view(label: String, visible_fire: bool) -> void:
	volume_visible(visible_fire)
	effect.get_node("FuelFire").visible = false
	var before := await render_frame()
	volume_visible(true)
	var after := await render_frame()
	check(before != null and after != null and not before.is_empty() and not after.is_empty(),label + " captures actual rendered frames")
	if before == null or after == null or before.is_empty() or after.is_empty(): return
	var hot_pixels := 0
	var changed_pixels := 0
	for y in after.get_height():
		for x in after.get_width():
			var a := before.get_pixel(x,y)
			var b := after.get_pixel(x,y)
			if maxf(absf(b.r-a.r),maxf(absf(b.g-a.g),absf(b.b-a.b))) < .08: continue
			changed_pixels += 1
			if b.r-a.r > .08 and b.r > .3 and b.r > b.b * 1.35 and b.g > .08: hot_pixels += 1
	print("BARREL_BLAST_RENDER label=%s hot_pixels=%d changed_pixels=%d camera=%s" % [label,hot_pixels,changed_pixels,viewport.get_camera_3d().get_path()])
	if visible_fire: check(hot_pixels >= 12,label + " shows spatial fire rather than disappearing")
	else: check(changed_pixels <= 2,label + " opaque blocker completely occludes the plume")
	before.save_png(OUTPUT + label + "-before.png")
	after.save_png(OUTPUT + label + "-after.png")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = Node3D.new()
	world.set_meta("entity_domain",true)
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.03,.04,.05)
	world.add_child(environment)
	var shell := RV.instantiate() as Node3D
	world.add_child(shell)
	shell.position.y = 1.2
	var rv := shell.get_node("Chassis") as Chassis
	rv.freeze = true
	rv.set_physics_process(false)
	await steps()
	var seat := rv.get_node("DriverSeat")
	var player := PLAYER.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = rv.to_global(Vector3(0,.55,-3))
	seat.interact_hold(player)
	driver_camera = seat.seat_camera
	check(seat.current_driver == player and viewport.get_camera_3d() == driver_camera,"Production player enters the actual seat and selects its camera")
	effect = EFFECT.new()
	effect.position = Vector3(0,.5,-6.8)
	world.add_child(effect)
	effect.set_process(false)
	effect.set_physics_process(false)
	plume_age(.25)
	check(effect.find_children("*","CollisionObject3D",true,false).is_empty(),"Blast visuals add no gameplay collision")
	for volume_name in ["FuelFire","RollingSoot"]:
		var volume := effect.get_node(volume_name) as MeshInstance3D
		var bounds := volume.get_aabb()
		check(bounds.size.x > 0 and bounds.size.y > 0 and bounds.size.z > .1,volume_name + " bounds cover a spatial plume from every camera direction")
	if DisplayServer.get_name() == "headless":
		print("SKIP: barrel blast pixels require a native display; dummy headless checked seat ownership, spatial bounds and cosmetic collision only")
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		for sample in [Vector2(.10,0),Vector2(.25,-1.6),Vector2(.50,-2.5)]:
			shell.position.z = sample.y
			plume_age(sample.x)
			check(viewport.get_camera_3d() == driver_camera,"Driver camera stays current during plume crossing")
			await compare_view("driver-%03d" % roundi(sample.x * 1000),true)
		# Isolate inside/reverse views and opaque occlusion from cockpit geometry.
		shell.queue_free()
		player.queue_free()
		await steps()
		effect.position = Vector3(0,0,0)
		plume_age(.5)
		var camera := Camera3D.new()
		camera.near = .025
		camera.fov = 80
		world.add_child(camera)
		camera.current = true
		var fire := effect.get_node("FuelFire") as Node3D
		camera.position = fire.position + Vector3(0,0,8)
		camera.look_at(fire.global_position)
		await compare_view("outside",true)
		camera.position = fire.global_position
		camera.rotation = Vector3.ZERO
		await compare_view("inside-forward",true)
		camera.rotation.y = PI
		await compare_view("inside-reverse",true)
		camera.position = fire.global_position + Vector3(8,0,0)
		camera.look_at(fire.global_position)
		await compare_view("side",true)
		camera.position = fire.global_position + Vector3(0,0,12)
		camera.look_at(fire.global_position)
		solid(Vector3(40,40,.2),fire.global_position + Vector3(0,0,10),Color(.12,.15,.18))
		await compare_view("opaque-wall",false)
	viewport.queue_free()
	await steps()
	if failures.is_empty(): print("PASS: barrel blast seated camera and spatial contracts; native pixel cases run only with a display")
	quit(0 if failures.is_empty() else 1)
