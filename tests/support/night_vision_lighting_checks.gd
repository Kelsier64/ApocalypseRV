extends SceneTree
## GPU regression: gray adaptation must coexist with native physical lighting.
## Run directly without --headless; this is not another default core process.
class HeadlightRig extends Node3D:
	var lamps_powered := true
	var headlights_requested := true
	var gear := 0
	var handbrake := false
	var brake_input := 0.0

var failures := 0
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var clock: WorldClock
var panel: MeshInstance3D
var material: StandardMaterial3D
var light: OmniLight3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func constant_curve(value: float) -> Curve:
	var result := Curve.new()
	result.add_point(Vector2(0, value))
	result.add_point(Vector2(1, value))
	return result

func capture(target: SubViewport = viewport) -> Image:
	for i in range(5):
		await process_frame
		await RenderingServer.frame_post_draw
	return target.get_texture().get_image()

func pixel(image: Image) -> Color:
	return image.get_pixel(64, 64)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Night lighting checks require a GPU renderer; omit --headless")
		quit(2)
		return
	var authored_curve_hash := FileAccess.get_sha256("res://world/night_vision_curve.tres")
	await process_frame
	viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.positional_shadow_atlas_size = 2048
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = Environment.new()
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	world.add_child(sun)
	camera = Camera3D.new()
	camera.cull_mask &= ~(1 << 10)
	camera.far = 200
	world.add_child(camera)
	panel = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(20, 20)
	panel.mesh = mesh
	panel.position.z = -8
	material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.2, 0.05)
	material.roughness = 1
	material.metallic_specular = 0
	panel.material_override = material
	world.add_child(panel)
	clock = WorldClock.new()
	clock.running = false
	clock.weather_running = false
	world.add_child(clock)
	clock.get_node("WeatherRain").process_mode = Node.PROCESS_MODE_DISABLED
	clock.label.get_parent().hide()
	clock.set_time(1, 22)
	clock.environment.fog_enabled = false
	clock.night_vision_curve = constant_curve(1)
	var unlit := pixel(await capture())
	var reference: SubViewport = clock.night_vision_effect._views[0].reference
	print("UNLIT=",unlit," REF=",pixel(reference.get_texture().get_image()))
	check(unlit.r > 0.03 and absf(unlit.r-unlit.g) < 0.02 and absf(unlit.g-unlit.b) < 0.02, "Unlit colored surfaces retain gray adaptation")
	clock.night_vision_curve = constant_curve(0)
	check(pixel(await capture()).r < 0.01, "Curve zero makes unlit surfaces black")
	light = OmniLight3D.new()
	light.position = Vector3(1, 0, -2)
	light.light_energy = 2
	light.omni_range = 20
	light.light_color = Color(1, 0.75, 0.25)
	light.shadow_enabled = true
	world.add_child(light)
	var lit := pixel(await capture())
	print("LIT curve0=",lit)
	check(lit.r > 0.1 and lit.r > lit.b * 2, "Physical light stays visible and colored when Curve is zero")
	clock.night_vision_effect.register_viewport(viewport, false)
	var native_lit := pixel(await capture())
	clock.night_vision_effect.register_viewport(viewport)
	check(Vector3(lit.r-native_lit.r,lit.g-native_lit.g,lit.b-native_lit.b).length()<0.025, "Curve-zero composition preserves the native physical-light image")
	clock.night_vision_curve = constant_curve(1)
	var lit_adapted := pixel(await capture())
	print("LIT curve1=",lit_adapted)
	check(lit_adapted.r > lit_adapted.b * 2 and lit_adapted.r >= lit.r - 0.02, "Gray adaptation preserves a lit surface's color and brightness")
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 2, 0.3)
	blocker.mesh = box
	blocker.position = Vector3(0.5, 0, -5)
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	world.add_child(blocker)
	var shadow := pixel(await capture())
	print("SHADOW=",shadow)
	check(shadow.r < lit_adapted.r - 0.05 and absf(shadow.r-shadow.g)<0.02, "Occluders preserve native shadows with gray adaptation underneath")
	blocker.queue_free()
	light.visible = false
	clock.night_vision_curve = constant_curve(0)
	material.albedo_color = Color.WHITE
	# Exercise the production flashlight's actual beam settings, not a brighter
	# test light that could conceal broken night-light composition.
	var flashlight: Node3D = load("res://props/flashlight.tscn").instantiate()
	var beam := flashlight.get_node("Beam") as SpotLight3D
	flashlight.remove_child(beam)
	flashlight.free()
	world.add_child(beam)
	beam.position = Vector3(0,0,-1)
	beam.look_at(panel.position)
	beam.visible = true
	var flashlight_pixel := pixel(await capture())
	check(flashlight_pixel.r>0.1 and flashlight_pixel.r>flashlight_pixel.b, "Production flashlight lights the surface with its warm color at Curve zero")
	beam.visible = false
	var headlights := HeadlightRig.new()
	var lamp_factory := Node3D.new()
	lamp_factory.set_script(load("res://rv/vehicle_lights.gd"))
	headlights.add_child(lamp_factory)
	world.add_child(headlights)
	var headlight_pixel := pixel(await capture())
	check(headlight_pixel.r>0.1 and headlight_pixel.r>headlight_pixel.b, "Production RV headlight beams keep their warm illumination at Curve zero")
	headlights.lamps_powered = false
	check(pixel(await capture()).r<0.01, "Turning native lamps off removes their illumination")
	headlights.queue_free()
	panel.position.z = -80
	material.emission_enabled = true
	material.emission = Color.RED
	var emissive := pixel(await capture())
	print("EMISSIVE=",emissive)
	check(emissive.r > 0.5 and emissive.g < 0.05, "Real emissive lights keep color beyond the adaptation range")
	material.emission_enabled = false
	material.albedo_color = Color.WHITE
	panel.position.z = -40
	var profile := Curve.new()
	for point in [Vector2(0,1),Vector2(0.2,1),Vector2(0.5,0),Vector2(1,0)]: profile.add_point(point,0,0,Curve.TANGENT_LINEAR,Curve.TANGENT_LINEAR)
	clock.night_vision_curve = profile
	var mirror := SubViewport.new()
	mirror.size = viewport.size
	mirror.world_3d = viewport.find_world_3d()
	mirror.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mirror)
	var mirror_camera := Camera3D.new()
	mirror_camera.position.z = -38
	mirror.add_child(mirror_camera)
	clock.night_vision_effect.register_viewport(mirror)
	var distant := pixel(await capture())
	var nearby := pixel(await capture(mirror))
	print("MAIN distant=",distant," MIRROR near=",nearby)
	check(distant.r < 0.01 and nearby.r > 0.1, "Shared-world mirror gets its own matched Curve distance and reference")
	profile.set_point_value(2,1)
	check(pixel(await capture()).r > 0.1, "Editing the assigned Curve applies with time stopped")
	clock.set_time(1,12)
	await capture()
	check(reference.render_target_update_mode == SubViewport.UPDATE_DISABLED and not clock.night_vision_effect._views[0].quad.visible, "Daylight disables reference rendering and gray composition")
	check(light.layers == 1 and (camera.cull_mask & NightVisionEffect.VIEW_MASK) == NightVisionEffect.VIEW_MASK, "Daylight restores original light and camera layers")
	clock.set_time(1,22)
	await capture()
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	var ui := ColorRect.new()
	ui.color = Color.GREEN
	ui.size = Vector2(20,20)
	layer.add_child(ui)
	check((await capture()).get_pixel(5,5).g > 0.95, "Canvas HUD keeps its original color")
	# A loaded checkpoint moves the existing hierarchy between World3Ds without
	# another _ready. Reconnect rendering, ownership and the primary viewport.
	var destination := SubViewport.new()
	destination.size = viewport.size
	destination.own_world_3d = true
	destination.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(destination)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	WorldEntities.transfer(world,destination)
	viewport.queue_free()
	await process_frame
	world.process_mode = Node.PROCESS_MODE_INHERIT
	var restored := pixel(await capture(destination))
	check(restored.r>0.1 and clock.night_vision_effect._views[0].target.get_ref()==destination, "Staged checkpoint transfer rebinds gray adaptation to the live viewport")
	check(reference.find_world_3d()==destination.find_world_3d(), "Checkpoint reference uses the destination World3D")
	check(FileAccess.get_sha256("res://world/night_vision_curve.tres")==authored_curve_hash, "Authored Curve points, tangents and file bytes remain untouched")
	clock.night_vision_effect.queue_free()
	await process_frame
	await process_frame
	check(light.layers == 1, "Removing the effect restores physical-light visibility")
	mirror.queue_free()
	if is_instance_valid(viewport): viewport.queue_free()
	destination.queue_free()
	await process_frame
	print("NIGHT LIGHTING GPU ","PASS" if failures == 0 else "FAIL"," failures=",failures)
	quit(1 if failures else 0)
