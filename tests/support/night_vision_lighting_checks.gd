extends SceneTree
## GPU regression: brightness-driven gray adaptation and native physical lighting.
## Run without --headless; this is not another default core test process.
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
var renderer: NightVisionEffect
var environment: Environment
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

func capture_frame(target: SubViewport = viewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return target.get_texture().get_image()

func image_difference(a: Image, b: Image) -> float:
	var difference := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			difference = maxf(difference, color_distance(a.get_pixel(x, y), b.get_pixel(x, y)))
	return difference

func diagnostic_capture(label: String, target: SubViewport = viewport, effect: NightVisionEffect = renderer) -> Image:
	var image := await capture(target)
	if not OS.get_cmdline_user_args().has("--diagnostics"): return image
	var directory := "res://.godot/dark-adaptation-probes"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix := directory.path_join(RenderingServer.get_current_rendering_method() + "-" + label)
	image.save_png(prefix + "-adapted.png")
	var reference_pixel := Color.TRANSPARENT
	for entry in effect._views:
		if entry.target.get_ref() != target: continue
		var reference_image: Image = entry.reference.get_texture().get_image()
		reference_image.save_png(prefix + "-reference.png")
		reference_pixel = pixel(reference_image)
		break
	var was_enabled := effect.enabled
	effect.enabled = false
	var native_image := await capture(target)
	native_image.save_png(prefix + "-native.png")
	effect.enabled = was_enabled
	await capture(target)
	print("PROBE ", label, " adapted=", pixel(image), " native=", pixel(native_image), " reference=", reference_pixel)
	return image

func color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func native_environment() -> Environment:
	var result := Environment.new()
	result.background_mode = Environment.BG_COLOR
	result.background_color = Color.BLACK
	result.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	result.ambient_light_color = Color.WHITE
	result.ambient_light_energy = 0.0
	result.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	return result

func environment_state(source: Environment) -> Dictionary:
	var result := {}
	for property in source.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			result[property.name] = source.get(property.name)
	return result

func add_renderer(owner_world: Node3D, curve: Curve) -> NightVisionEffect:
	var result := NightVisionEffect.new()
	result.name = "DarkAdaptation"
	# Test-local profile and curves must never mutate the authored resource.
	result.profile = result.profile.duplicate()
	result.profile.distance_begin = 0.0
	result.profile.distance_end = 60.0
	result.profile.curve = curve
	owner_world.add_child(result)
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dark adaptation checks require a GPU renderer; omit --headless")
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
	environment = native_environment()
	holder.environment = environment
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.light_energy = 0.0
	world.add_child(sun)
	camera = Camera3D.new()
	camera.cull_mask &= ~(1 << 10)
	camera.far = 200
	var original_camera_mask := camera.cull_mask
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
	renderer = add_renderer(world, constant_curve(1))
	var original_environment := environment_state(environment)
	var unlit := pixel(await capture())
	var reference: SubViewport = renderer._views[0].reference
	check(unlit.r > 0.03 and absf(unlit.r - unlit.g) < 0.02 and absf(unlit.g - unlit.b) < 0.02, "A clock-free dark world receives local gray adaptation")
	check(NightVisionEffect.find_for(panel) == renderer, "Renderer resolves from its owning World3D without a WorldClock")
	material.albedo_color = Color.BLACK
	if OS.get_cmdline_user_args().has("--diagnostics"):
		print("PROBE black-material albedo=", material.albedo_color, " metallic=", material.metallic, " specular=", material.metallic_specular, " emission_enabled=", material.emission_enabled)
	check(pixel(await diagnostic_capture("black-material")).r < 0.01, "Black material does not glow when reference luminance is zero")
	material.albedo_color = Color(0.8, 0.2, 0.05)
	renderer.profile.curve = constant_curve(0)
	check(pixel(await capture()).r < 0.01, "Curve zero removes only gray adaptation from an unlit surface")
	light = OmniLight3D.new()
	light.position = Vector3(1, 0, -2)
	light.light_energy = 2
	light.omni_range = 20
	light.light_color = Color(1, 0.75, 0.25)
	light.shadow_enabled = true
	world.add_child(light)
	var lit := pixel(await capture())
	check(lit.r > 0.1 and lit.r > lit.b * 2, "Physical light remains visible and colored at Curve zero")
	renderer.enabled = false
	var native_lit := pixel(await capture())
	check(color_distance(lit, native_lit) < 0.025, "Curve-zero composition preserves the native physical-light image")
	check(light.layers == 1 and (camera.cull_mask & NightVisionEffect.VIEW_MASK) == NightVisionEffect.VIEW_MASK, "Explicit disable restores original light and camera layers")
	renderer.enabled = true
	renderer.profile.curve = constant_curve(1)
	var lit_adapted := pixel(await capture())
	check(lit_adapted.r > lit_adapted.b * 2 and lit_adapted.r >= lit.r - 0.02, "Sufficient local illumination keeps native color and brightness")
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 2, 0.3)
	blocker.mesh = box
	blocker.position = Vector3(0.5, 0, -5)
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	world.add_child(blocker)
	var shadow := pixel(await capture())
	check(shadow.r < lit_adapted.r - 0.05 and absf(shadow.r - shadow.g) < 0.02, "Native occluder shadows retain gray adaptation underneath")
	blocker.queue_free()
	light.visible = false
	var switched_off := pixel(await capture())
	check(absf(switched_off.r - switched_off.g) < 0.02 and switched_off.r < lit_adapted.r - 0.05, "At the same time, switching a local light off restores gray adaptation")
	check(environment_state(environment) == original_environment, "Renderer never changes native Environment settings")
	var original_process_mode := world.process_mode
	world.process_mode = Node.PROCESS_MODE_DISABLED
	check(color_distance(pixel(await capture()), switched_off) < 0.015, "Pausing a world retains its last gray reference view")
	renderer.enabled = false
	check(pixel(await capture()).r < 0.01 and light.layers == 1 and camera.cull_mask == original_camera_mask, "Disabling adaptation while paused immediately restores native pixels and owned layers")
	world.process_mode = original_process_mode
	renderer.enabled = true

	# Production beam settings, rather than an oversized substitute test light.
	renderer.profile.curve = constant_curve(0)
	material.albedo_color = Color.WHITE
	var flashlight: Node3D = load("res://props/flashlight.tscn").instantiate()
	var beam := flashlight.get_node("Beam") as SpotLight3D
	flashlight.remove_child(beam)
	flashlight.free()
	world.add_child(beam)
	beam.position = Vector3(0, 0, -1)
	beam.look_at(panel.position)
	beam.visible = true
	var flashlight_pixel := pixel(await capture())
	check(flashlight_pixel.r > 0.1 and flashlight_pixel.r > flashlight_pixel.b, "Production flashlight retains its warm illumination at Curve zero")
	beam.visible = false
	var headlights := HeadlightRig.new()
	var lamp_factory := Node3D.new()
	lamp_factory.set_script(load("res://rv/vehicle_lights.gd"))
	headlights.add_child(lamp_factory)
	world.add_child(headlights)
	var headlight_pixel := pixel(await capture())
	check(headlight_pixel.r > 0.1 and headlight_pixel.r > headlight_pixel.b, "Production RV headlights retain warm illumination at Curve zero")
	headlights.lamps_powered = false
	check(pixel(await capture()).r < 0.01, "Turning production lamps off removes their physical illumination")
	headlights.queue_free()
	await check_native_rain_light(beam)
	panel.position.z = -80
	material.emission_enabled = true
	material.emission = Color.RED
	var emissive := pixel(await capture())
	check(emissive.r > 0.5 and emissive.g < 0.05, "Emissive material keeps its color beyond the adaptation range")
	material.emission_enabled = false

	# A bright sky must not globally turn off adaptation on a dark surface.
	panel.position.z = -8
	mesh.size = Vector2(4, 4)
	renderer.profile.curve = constant_curve(1)
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.2, 0.5, 0.9)
	sky_material.sky_horizon_color = Color(0.2, 0.5, 0.9)
	sky_material.ground_horizon_color = Color(0.2, 0.5, 0.9)
	sky.sky_material = sky_material
	environment.sky = sky
	var sky_state := environment_state(environment)
	var dark_under_sky := await capture()
	check(pixel(dark_under_sky).r > 0.03 and absf(pixel(dark_under_sky).r - pixel(dark_under_sky).g) < 0.02, "Bright sky does not suppress a separate dark surface's adaptation")
	renderer.enabled = false
	var native_sky := await capture()
	renderer.enabled = true
	var adapted_sky := await capture()
	check(color_distance(adapted_sky.get_pixel(5, 5), native_sky.get_pixel(5, 5)) < 0.025, "Sky pixels retain their native brightness and color")
	check(environment_state(environment) == sky_state, "Sky and native ambient settings remain untouched")
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.sky = null
	mesh.size = Vector2(20, 20)
	await check_fog_visibility()
	await check_independent_indoor_world()
	await check_vehicle_reference_motion()
	await check_ambient_gate()
	var local_gray := pixel(await capture())
	var local_transform := world.transform
	world.transform = Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), 1.2), Vector3(18000, 500, -24000))
	var remote_gray := pixel(await capture())
	check(remote_gray.r > 0.1 and color_distance(remote_gray, local_gray) < 0.02, "Translated and rotated worlds keep the view composite inside the camera frustum")
	world.transform = local_transform
	var camera_environment := native_environment()
	camera_environment.fog_enabled = true
	camera_environment.fog_mode = Environment.FOG_MODE_DEPTH
	camera_environment.fog_density = 1.0
	camera_environment.fog_depth_begin = 1.0
	camera_environment.fog_depth_end = 3.0
	camera_environment.fog_light_color = Color.BLACK
	var camera_environment_state := environment_state(camera_environment)
	camera.environment = camera_environment
	check(pixel(await capture()).r < 0.01 and environment_state(camera_environment) == camera_environment_state and not environment.fog_enabled, "A camera Environment override drives the reference instead of the shared World3D Environment")
	camera.environment = null

	# Changing clock time is not an activation input. Hold actual native light
	# and the same Environment fixed so legitimate sun changes cannot confound it.
	var stable_environment := environment
	var clock := WorldClock.new()
	clock.running = false
	clock.weather_running = false
	world.add_child(clock)
	var weather := clock.get_node_or_null("WeatherRain")
	if weather != null: weather.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(clock.label): clock.label.get_parent().hide()
	var stable_state := environment_state(stable_environment)
	clock.set_time(1, 12)
	holder.environment = stable_environment
	sun.light_energy = 0.0
	var noon := pixel(await capture())
	clock.set_time(1, 22)
	holder.environment = stable_environment
	sun.light_energy = 0.0
	var night := pixel(await capture())
	check(noon.r > 0.03 and color_distance(noon, night) < 0.015, "Identical native lighting produces the same adaptation at noon and night")
	check(environment_state(stable_environment) == stable_state, "Clock-independent renderer leaves the held native Environment unchanged")
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		holder.environment = clock.environment
		await check_light_history(clock.environment, beam)
		holder.environment = stable_environment
	clock.queue_free()
	await process_frame

	panel.position.z = -40
	var distance_curve := Curve.new()
	for point in [Vector2(0, 1), Vector2(0.2, 1), Vector2(0.5, 0), Vector2(1, 0)]:
		distance_curve.add_point(point, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	renderer.profile.curve = distance_curve
	var mirror := SubViewport.new()
	mirror.size = viewport.size
	mirror.world_3d = viewport.find_world_3d()
	mirror.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mirror)
	var mirror_camera := Camera3D.new()
	mirror_camera.position.z = -38
	mirror.add_child(mirror_camera)
	renderer.register_viewport(mirror)
	var distant := pixel(await capture())
	var nearby := pixel(await capture(mirror))
	check(distant.r < 0.01 and nearby.r > 0.1, "Shared-world mirror has its own matched distance and reference")
	distance_curve.set_point_value(2, 1)
	check(pixel(await capture()).r > 0.1, "Editing the assigned Curve applies without a clock")
	renderer.profile.distance_begin = 40.0
	renderer.profile.distance_end = 80.0
	check(pixel(await capture()).r > 0.1, "Editing profile distance remaps the authored Curve without time advancing")
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	var ui := ColorRect.new()
	ui.color = Color.GREEN
	ui.size = Vector2(20, 20)
	layer.add_child(ui)
	check((await capture()).get_pixel(5, 5).g > 0.95, "Canvas HUD keeps its original color")

	# Checkpoint transfer re-enters an existing hierarchy without another _ready.
	var destination := SubViewport.new()
	destination.size = viewport.size
	destination.own_world_3d = true
	destination.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(destination)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	WorldEntities.transfer(world, destination)
	viewport.queue_free()
	await process_frame
	world.process_mode = Node.PROCESS_MODE_INHERIT
	var restored := pixel(await capture(destination))
	check(restored.r > 0.1 and renderer._views[0].target.get_ref() == destination, "Staged transfer rebinds adaptation to the live viewport")
	check(reference.find_world_3d() == destination.find_world_3d(), "Transferred reference uses the destination World3D")
	check(FileAccess.get_sha256("res://world/night_vision_curve.tres") == authored_curve_hash, "Authored Curve points, tangents and file bytes remain untouched")
	renderer.queue_free()
	await process_frame
	await process_frame
	check(light.layers == 1, "Removing the effect restores physical-light visibility")
	mirror.queue_free()
	if is_instance_valid(viewport): viewport.queue_free()
	destination.queue_free()
	await process_frame
	print("DARK ADAPTATION GPU ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(1 if failures else 0)

func check_ambient_gate() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(128, 128)
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var scene := Node3D.new()
	target.add_child(scene)
	var holder := WorldEnvironment.new()
	var native := native_environment()
	native.ambient_light_energy = 0.1
	holder.environment = native
	scene.add_child(holder)
	var source := Camera3D.new()
	var original_mask := 1 | (1 << 2)
	source.cull_mask = original_mask
	scene.add_child(source)
	var receiver := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(20, 20)
	receiver.mesh = mesh
	receiver.position.z = -8
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	white.roughness = 1.0
	white.metallic_specular = 0.0
	receiver.material_override = white
	scene.add_child(receiver)
	var lamp := OmniLight3D.new()
	lamp.position.z = -2
	lamp.omni_range = 20
	lamp.light_energy = 3.0
	lamp.light_color = Color.RED
	lamp.layers = 1 << 2
	scene.add_child(lamp)
	var effect := add_renderer(scene, constant_curve(1))
	effect.profile.reference_energy = 0.4
	var scheduled := {"updates": 0}
	# Observe the scheduling decision before UPDATE_ONCE resets after rendering.
	var count_updates := func():
		for entry in effect._views:
			if entry.reference.render_target_update_mode != SubViewport.UPDATE_DISABLED: scheduled.updates += 1
	RenderingServer.frame_pre_draw.connect(count_updates)
	var native_state := environment_state(native)
	var bright := pixel(await capture(target))
	check(not effect._views[0].quad.visible and scheduled.updates == 0 and source.cull_mask == original_mask and lamp.layers == 1 << 2, "Bright ambient skips both reference rendering and composition and restores custom native layers")
	effect.enabled = false
	var native_bright := pixel(await capture(target))
	check(color_distance(bright, native_bright) < 0.015 and bright.r > bright.g + 0.05, "A dormant ambient gate preserves native colored physical lighting")
	effect.enabled = true
	lamp.visible = false
	mesh.size = Vector2(3, 4)
	await capture(target)
	source.transform = Transform3D(Basis.from_euler(Vector3(0.04, 0.2, 0.09)), Vector3(0.75, 0.15, 0))
	await capture(target)
	native.ambient_light_energy = 0.0
	var first_wake := await capture_frame(target)
	var settled_wake := await capture(target)
	var black := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	check(image_difference(first_wake, settled_wake) < 0.015 and image_difference(first_wake, black) > 0.1, "A dormant reference wakes with the camera's current silhouette in its first rendered frame")
	source.transform = Transform3D.IDENTITY
	mesh.size = Vector2(20, 20)
	native.ambient_light_energy = 0.1
	await capture(target)
	var metric := native_environment()
	metric.ambient_light_energy = 0.06
	check(is_zero_approx(effect._ambient_strength(metric)), "Ambient gate is fully off at its threshold")
	metric.ambient_light_energy = 0.04
	check(is_equal_approx(effect._ambient_strength(metric), 1.0), "Ambient gate is fully on below the transition band")
	metric.ambient_light_energy = 0.05
	check(absf(effect._ambient_strength(metric) - 0.5) < 0.0001, "Ambient gate has a smooth half-strength transition midpoint")
	metric.ambient_light_color = Color(0.5, 0.5, 0.5)
	metric.ambient_light_energy = 0.2
	var linear := metric.ambient_light_color.srgb_to_linear()
	var expected := 1.0 - smoothstep(0.04, 0.06, Vector3(linear.r, linear.g, linear.b).dot(Vector3(0.2126, 0.7152, 0.0722)) * 0.2)
	check(absf(effect._ambient_strength(metric) - expected) < 0.0001, "Ambient gate measures linear color luminance rather than raw sRGB components")
	effect.profile.ambient_threshold = 0.0
	metric.ambient_light_energy = 0.0
	check(is_zero_approx(effect._ambient_strength(metric)), "A zero ambient threshold safely disables adaptation even at zero brightness")
	effect.profile.ambient_threshold = 0.06
	effect.profile.ambient_transition = 0.0
	metric.ambient_light_color = Color.WHITE
	metric.ambient_light_energy = 0.059
	var below_step := effect._ambient_strength(metric)
	# Environment energy and Vector3 luminance use float32; straddle the edge.
	metric.ambient_light_energy = 0.061
	check(is_equal_approx(below_step, 1.0) and is_zero_approx(effect._ambient_strength(metric)), "A zero-width ambient transition uses a finite threshold step")
	for invalid in [NAN, INF, -INF]:
		effect.profile.ambient_threshold = invalid
		effect.profile.ambient_transition = invalid
	check(is_equal_approx(effect.profile.ambient_threshold, 0.06) and is_zero_approx(effect.profile.ambient_transition), "Ambient profile setters reject NaN and infinite values")
	effect.profile.ambient_transition = 0.02
	metric.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	check(is_equal_approx(effect._ambient_strength(metric), 1.0), "Disabled native ambient is treated as dark")
	metric.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	check(is_equal_approx(effect._ambient_strength(metric), 1.0) and is_equal_approx(effect._ambient_strength(null), 1.0), "Unknown sky or missing Environment conservatively keeps adaptation available")
	lamp.visible = false
	native.ambient_light_energy = 0.05
	effect.enabled = false
	var native_middle := pixel(await capture(target))
	effect.enabled = true
	effect.profile.ambient_gate_enabled = false
	var full_middle := pixel(await capture(target))
	effect.profile.ambient_gate_enabled = true
	var middle := pixel(await capture(target))
	check(middle.r > native_middle.r + 0.01 and middle.r < full_middle.r - 0.01, "Transition-band GPU fill lies between native and full adaptation")
	native.ambient_light_energy = 0.0
	var before_dark := int(scheduled.updates)
	check(pixel(await capture(target)).r > 0.1 and effect._views[0].quad.visible and scheduled.updates > before_dark, "Dark ambient wakes the reference renderer and visible gray fill")
	native.ambient_light_energy = 0.1
	lamp.visible = true
	var mirror := SubViewport.new()
	mirror.size = target.size
	mirror.world_3d = target.find_world_3d()
	mirror.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mirror)
	var mirror_camera := Camera3D.new()
	mirror_camera.cull_mask = original_mask
	var mirror_environment := native_environment()
	mirror_camera.environment = mirror_environment
	mirror.add_child(mirror_camera)
	effect.register_viewport(mirror)
	var mixed_bright := pixel(await capture(target))
	check(not effect._views[0].quad.visible and effect._views[1].quad.visible and (source.cull_mask & NightVisionEffect.VIEW_MASK) == 0 and (source.cull_mask & NightVisionEffect.LIGHT_LAYER) != 0, "A bright main view stays routed while its dark camera-override mirror adapts")
	check(color_distance(mixed_bright, native_bright) < 0.015 and lamp.layers == NightVisionEffect.LIGHT_LAYER, "Mixed views retain a custom-layer native lamp in the bright view")
	native.ambient_light_energy = 0.0
	mirror_environment.ambient_light_energy = 0.1
	var mixed_mirror := pixel(await capture(mirror))
	check(effect._views[0].quad.visible and not effect._views[1].quad.visible and (mirror_camera.cull_mask & NightVisionEffect.VIEW_MASK) == 0 and color_distance(mixed_mirror, native_bright) < 0.015, "Reversing dark and bright views switches routing without leaking another view's composite")
	native.ambient_light_energy = 0.1
	await capture(target)
	var before_bright := int(scheduled.updates)
	await capture(mirror)
	check(scheduled.updates == before_bright and source.cull_mask == original_mask and mirror_camera.cull_mask == original_mask and lamp.layers == 1 << 2, "Returning all views to bright ambient stops reference draws and restores original camera and light layers")
	effect.profile.ambient_gate_enabled = false
	var before_forced := int(scheduled.updates)
	await capture(target)
	check(effect._views[0].quad.visible and effect._views[1].quad.visible and scheduled.updates > before_forced, "Disabling the ambient gate restores always-on per-pixel adaptation")
	check(environment_state(native) == native_state, "Ambient gating leaves the native Environment unchanged")
	RenderingServer.frame_pre_draw.disconnect(count_updates)
	mirror.queue_free()
	target.queue_free()
	await process_frame

func check_vehicle_reference_motion() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(128, 128)
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var scene := Node3D.new()
	target.add_child(scene)
	var holder := WorldEnvironment.new()
	holder.environment = native_environment()
	scene.add_child(holder)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	white.roughness = 1.0
	white.metallic_specular = 0.0
	for at in [Vector3(-4, 2, -14), Vector3(0, 3, -20), Vector3(4, 1, -16)]:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2, 4, 2)
		box.mesh = mesh
		box.material_override = white
		box.position = at
		scene.add_child(box)
	var rig := HeadlightRig.new()
	scene.add_child(rig)
	var source := Camera3D.new()
	source.position = Vector3(0, 2, 0)
	rig.add_child(source)
	var lamps := Node3D.new()
	lamps.set_script(load("res://rv/vehicle_lights.gd"))
	rig.add_child(lamps)
	var effect := add_renderer(scene, constant_curve(1))
	var black := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	for powered in [false, true]:
		rig.lamps_powered = powered
		rig.transform = Transform3D.IDENTITY
		await capture(target)
		rig.transform = Transform3D(Basis.from_euler(Vector3(0.07, 0.12, -0.09)), Vector3(0.35, 0.15, -0.25))
		var first := await capture_frame(target)
		var settled := await capture(target)
		check(image_difference(first, settled) < 0.015, "Vehicle tilt, roll and translation keep the first gray-reference frame aligned (lamps %s)" % powered)
		check(image_difference(first, black) > 0.1, "Moving vehicle retains visible white silhouettes (lamps %s)" % powered)
	var mirror := SubViewport.new()
	mirror.size = target.size
	mirror.world_3d = target.find_world_3d()
	mirror.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mirror)
	var mirror_camera := Camera3D.new()
	mirror_camera.position = Vector3(-2, 3, 2)
	mirror.add_child(mirror_camera)
	effect.register_viewport(mirror)
	await capture(mirror)
	mirror_camera.rotation = Vector3(0.05, 0.2, -0.07)
	var mirror_first := await capture_frame(mirror)
	var mirror_settled := await capture(mirror)
	check(image_difference(mirror_first, mirror_settled) < 0.015 and image_difference(mirror_first, black) > 0.1, "A mirror camera step matches its current-frame reference without delayed silhouettes")
	var helpers_uninterpolated := true
	for entry in effect._views:
		helpers_uninterpolated = helpers_uninterpolated and entry.camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and entry.quad.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
	check(helpers_uninterpolated, "Render-driven reference cameras and quads disable their own physics interpolation")
	mirror.queue_free()
	target.queue_free()
	await process_frame

func check_light_history(native: Environment, beam: SpotLight3D) -> void:
	check(not native.volumetric_fog_temporal_reprojection_enabled, "Production fog uses current-frame light scattering without temporal beam trails")
	native.background_mode = Environment.BG_COLOR
	native.background_color = Color.BLACK
	native.ambient_light_energy = 0.0
	native.fog_enabled = false
	native.volumetric_fog_enabled = true
	native.volumetric_fog_density = 0.06
	native.volumetric_fog_albedo = Color.WHITE
	native.volumetric_fog_length = 32.0
	var previous_camera := camera.transform
	var previous_beam := beam.transform
	material.albedo_color = Color.BLACK
	beam.look_at(Vector3(-7, 0, -12))
	beam.visible = true
	for index in range(24): await capture_frame()
	var on := await capture_frame()
	var black := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	check(image_difference(on, black) > 0.05, "A real flashlight still illuminates the fog with temporal accumulation disabled")
	var reference_environment: Environment = renderer._views[0].camera.environment
	check(not reference_environment.volumetric_fog_temporal_reprojection_enabled, "Gray reference matches the production fog's current-frame mode")
	beam.look_at(Vector3(7, 0, -12))
	var first_move := await capture_frame()
	var settled_move := await capture()
	check(image_difference(first_move, settled_move) < 0.015, "Moving the flashlight leaves no previous beam in the first rendered frame")
	camera.rotation.y += 0.3
	var first_pan := await capture_frame()
	var settled_pan := await capture()
	check(image_difference(first_pan, settled_pan) < 0.015, "Turning the camera leaves no previous-frame lit fog")
	beam.visible = false
	var first_off := await capture_frame()
	check(image_difference(first_off, black) < 0.01, "Switching the flashlight off removes its fog light in the first rendered frame")
	beam.transform = previous_beam
	camera.transform = previous_camera
	material.albedo_color = Color.WHITE

func check_native_rain_light(beam: SpotLight3D) -> void:
	# Use the production transparent splash shader over a black receiver so a
	# brighter background cannot masquerade as physical light reaching the rain.
	material.albedo_color = Color.BLACK
	var splash := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(6, 6)
	splash.mesh = mesh
	splash.layers = NightVisionEffect.LIGHT_LAYER
	splash.position.z = -7
	var shader := ShaderMaterial.new()
	shader.shader = load("res://world/rain_splash.gdshader")
	splash.material_override = shader
	world.add_child(splash)
	var dark := await capture()
	beam.visible = true
	var lit := await capture()
	var maximum_gain := 0.0
	for y in range(lit.get_height()):
		for x in range(lit.get_width()):
			maximum_gain = maxf(maximum_gain, lit.get_pixel(x, y).r - dark.get_pixel(x, y).r)
	check(maximum_gain > 0.03, "Production transparent rain splash responds to a real flashlight without a clock")
	beam.visible = false
	splash.queue_free()
	material.albedo_color = Color.WHITE

func check_fog_visibility() -> void:
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_density = 1.0
	environment.fog_depth_begin = 1.0
	environment.fog_depth_end = 3.0
	environment.fog_light_color = Color.BLACK
	var depth_state := environment_state(environment)
	check(pixel(await diagnostic_capture("depth-fog")).r < 0.01, "Dense native depth fog is not undone by adaptation")
	check(environment_state(environment) == depth_state, "Renderer preserves native depth-fog settings")
	environment.fog_enabled = false
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 3.0
		environment.volumetric_fog_length = 32.0
		environment.volumetric_fog_albedo = Color.WHITE
		environment.volumetric_fog_emission = Color.BLACK
		environment.volumetric_fog_ambient_inject = 0.3
		environment.volumetric_fog_temporal_reprojection_enabled = false
		var global_state := environment_state(environment)
		check(pixel(await diagnostic_capture("global-volumetric-fog")).r < 0.015, "Dense global volumetric fog does not reveal the hidden surface")
		check(environment_state(environment) == global_state, "Renderer leaves native volumetric fog and ambient injection unchanged")
		environment.volumetric_fog_density = 0.0
		var volume := FogVolume.new()
		volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		volume.size = Vector3(20, 20, 10)
		volume.position.z = -4
		var fog_material := FogMaterial.new()
		fog_material.density = 3.0
		fog_material.albedo = Color.WHITE
		volume.material = fog_material
		world.add_child(volume)
		var local_state := environment_state(environment)
		check(pixel(await diagnostic_capture("local-volumetric-fog")).r < 0.015, "A dense local FogVolume still hides geometry from gray adaptation")
		check(environment_state(environment) == local_state and is_equal_approx(fog_material.density, 3.0), "Renderer does not rewrite native local-fog density")
		volume.queue_free()
		environment.volumetric_fog_enabled = false
	check(pixel(await capture()).r > 0.1, "The dark surface is readable again after native fog is removed")

func check_independent_indoor_world() -> void:
	var indoor := SubViewport.new()
	indoor.size = viewport.size
	indoor.own_world_3d = true
	indoor.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(indoor)
	var room := Node3D.new()
	indoor.add_child(room)
	var holder := WorldEnvironment.new()
	holder.environment = native_environment()
	room.add_child(holder)
	var indoor_camera := Camera3D.new()
	room.add_child(indoor_camera)
	var surface := MeshInstance3D.new()
	surface.mesh = panel.mesh
	surface.position.z = -8
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_color = Color(0.2, 0.8, 0.4)
	surface_material.roughness = 1.0
	surface_material.metallic_specular = 0.0
	surface.material_override = surface_material
	room.add_child(surface)
	var indoor_renderer := add_renderer(room, constant_curve(1))
	var indoor_state := environment_state(holder.environment)
	var gray := pixel(await capture(indoor))
	check(gray.r > 0.03 and absf(gray.r - gray.g) < 0.02, "An independent indoor World3D adapts without any WorldClock")
	check(NightVisionEffect.find_for(surface) == indoor_renderer and NightVisionEffect.find_for(panel) == renderer, "Indoor and outdoor geometry resolve different world-scoped renderers")
	renderer.enabled = false
	check(color_distance(pixel(await capture(indoor)), gray) < 0.015, "Disabling the outdoor renderer cannot disable indoor adaptation")
	renderer.enabled = true
	# A neutral receiver isolates lamp color from saturated material absorption.
	surface_material.albedo_color = Color.WHITE
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 0, -2)
	lamp.omni_range = 20
	lamp.light_color = Color.RED
	lamp.light_energy = 3.0
	room.add_child(lamp)
	if OS.get_cmdline_user_args().has("--diagnostics"):
		print("PROBE indoor-light receiver=", surface_material.albedo_color, " lamp_energy=", lamp.light_energy, " range=", lamp.omni_range, " receiver_distance=", lamp.global_position.distance_to(surface.global_position))
	var colored := pixel(await diagnostic_capture("indoor-red-light", indoor, indoor_renderer))
	check(colored.r > 0.1 and colored.r > colored.g * 2.0, "Indoor physical lighting remains colored independently of outdoor rendering")
	check(environment_state(holder.environment) == indoor_state, "Independent indoor native Environment stays unchanged")
	# Retain the outdoor owner's stale entry while the actual player camera moves.
	await capture()
	var native_camera_layers := int(camera.get_meta(NightVisionEffect.CAMERA_ORIGINAL_LAYERS))
	var outdoor_process_mode := renderer.process_mode
	var outdoor_enabled := renderer.enabled
	renderer.process_mode = Node.PROCESS_MODE_DISABLED
	camera.reparent(room)
	camera.make_current()
	await capture(indoor)
	var indoor_camera_layers := camera.cull_mask
	check(camera.get_meta(NightVisionEffect.CAMERA_OWNER, 0) == indoor_renderer.get_instance_id(), "A transferred player camera is claimed by its new world's renderer")
	renderer.enabled = false
	await capture(indoor)
	check(camera.cull_mask == indoor_camera_layers and camera.get_meta(NightVisionEffect.CAMERA_OWNER, 0) == indoor_renderer.get_instance_id(), "Paused outdoor cleanup cannot overwrite indoor camera ownership or layers")
	indoor_renderer.enabled = false
	await capture(indoor)
	check((camera.cull_mask & NightVisionEffect.OWNED_LAYERS) == native_camera_layers and not camera.has_meta(NightVisionEffect.CAMERA_OWNER), "Disabling the new camera owner restores the original native camera layers")
	camera.reparent(world)
	camera.make_current()
	renderer.process_mode = outdoor_process_mode
	renderer.enabled = outdoor_enabled
	indoor_renderer.enabled = true
	await capture()
	check(NightVisionEffect.find_for(camera) == renderer and camera.get_meta(NightVisionEffect.CAMERA_OWNER, 0) == renderer.get_instance_id(), "Returning the player camera resolves and reclaims its original world renderer")
	indoor.queue_free()
	await process_frame
