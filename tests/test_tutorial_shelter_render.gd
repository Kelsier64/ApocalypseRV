extends SceneTree
## Native pixel regression: actual shelter geometry must occlude direct light.
const SHELTER := preload("res://world/tutorial_shelter/tutorial_shelter.tscn")
const OUTPUT := "res://.godot/tutorial-shelter-render/"
const SAMPLE := Rect2i(304, 164, 32, 32)
const MAX_BLOCKED_GAIN := 0.025
const MIN_OPEN_GAIN := 0.06
var failures: Array[String] = []
var viewport: SubViewport
var world: Node3D
var shelter: Node3D
var camera: Camera3D
var receiver: MeshInstance3D
var sun: DirectionalLight3D
var blockers: Array[Node3D] = []
var output_directory := OUTPUT

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func render_frame() -> Image:
	# Shadow atlas updates and the opaque pass must both reach the texture.
	for frame in 4: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func gain(before: Image, after: Image) -> float:
	var total := 0.0
	for y in range(SAMPLE.position.y, SAMPLE.end.y):
		for x in range(SAMPLE.position.x, SAMPLE.end.x):
			total += maxf(0.0, after.get_pixel(x, y).get_luminance() - before.get_pixel(x, y).get_luminance())
	return total / float(SAMPLE.size.x * SAMPLE.size.y)

func blockers_visible(value: bool) -> void:
	for blocker in blockers: blocker.visible = value

func aim(point: Vector3) -> void:
	receiver.position = point + Vector3(0, 0.09, 0)
	camera.position = point + Vector3(0, 4.7, -12)
	camera.look_at(receiver.position + Vector3(0, 0.05, 0))

func compare_light(label: String, light: Light3D) -> void:
	blockers_visible(true)
	light.visible = false
	var off := await render_frame()
	light.visible = true
	var blocked := await render_frame()
	blockers_visible(false)
	var open := await render_frame()
	blockers_visible(true)
	light.visible = false
	check(off != null and blocked != null and open != null and not off.is_empty() and not blocked.is_empty() and not open.is_empty(), label + " captures actual rendered images")
	if off == null or blocked == null or open == null or off.is_empty() or blocked.is_empty() or open.is_empty(): return
	var blocked_gain := gain(off, blocked)
	var open_gain := gain(off, open)
	print("TUTORIAL_SHELTER_RENDER label=%s blocked_gain=%.5f open_gain=%.5f renderer=%s" % [label, blocked_gain, open_gain, RenderingServer.get_current_rendering_method()])
	# Encoded image quantization/filtering may shift a few pixels; 0.025 mean
	# gain allows that noise but rejects a visibly illuminated white surface.
	check(open_gain >= MIN_OPEN_GAIN, label + " positive control receives real light when visual blockers are removed")
	check(blocked_gain <= MAX_BLOCKED_GAIN and blocked_gain <= open_gain * 0.15, label + " shelter blocks at least 85 percent of direct light")
	for entry in [["off", off], ["blocked", blocked], ["open", open]]:
		check(entry[1].save_png(output_directory + label + "-" + entry[0] + ".png") == OK, label + " saves " + entry[0] + " evidence")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.positional_shadow_atlas_size = 4096
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var holder := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	holder.environment = environment
	world.add_child(holder)
	shelter = SHELTER.instantiate() as Node3D
	world.add_child(shelter)
	for child in shelter.get_children():
		if child is Node3D and child.name in ["Visuals", "Furnishings", "Gates", "GarageGate", "GarageButton"]: blockers.append(child)
	var legacy := "--legacy-lighting" in OS.get_cmdline_user_args()
	for fixture: Light3D in shelter.find_children("*", "Light3D", true, false):
		if legacy: fixture.shadow_enabled = false
		check(fixture.shadow_enabled, "Authored fixture casts occluding shadows: " + str(fixture.name))
		fixture.visible = false
	if legacy:
		# Deliberate mutation verifies the regression without rewriting assets.
		for visual: MeshInstance3D in shelter.find_children("*", "MeshInstance3D", true, false):
			if visual.mesh is BoxMesh and visual.mesh.size.z > 100:
				var mesh := visual.mesh.duplicate() as BoxMesh
				mesh.subdivide_width = 0
				mesh.subdivide_height = 0
				mesh.subdivide_depth = 0
				visual.mesh = mesh
	receiver = MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(4, 0.1, 4)
	receiver.mesh = plate
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.metallic_specular = 0.0
	receiver.material_override = material
	world.add_child(receiver)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 400.0
	world.add_child(camera)
	camera.current = true
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.light_energy = 1.0
	sun.visible = false
	world.add_child(sun)
	if DisplayServer.get_name() == "headless":
		print("SKIP: tutorial shelter pixels require a native display; headless validates authored fixture shadows only")
	else:
		output_directory = OUTPUT + RenderingServer.get_current_rendering_method() + ("/legacy/" if legacy else "/current/")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
		# Use the WorldClock's actual morning/noon/afternoon solar orbit.
		for bay in [["first", -200.0], ["middle", -104.0], ["final", 0.0]]:
			aim(Vector3(0, 0, bay[1]))
			for hour: float in [8.0, 12.0, 15.0]:
				var angle := (hour - 6.0) / 24.0 * TAU
				var direction := Vector3(cos(angle), sin(angle) * 0.85, sin(angle) * 0.526783).normalized()
				sun.basis = Basis.looking_at(-direction, Vector3.UP)
				await compare_light("sun-%s-%02d" % [bay[0], int(hour)], sun)
		# The real next-bay ceiling fixture reaches these floor patches only
		# if it leaks through the partition or the closed centre gate.
		var fixture := shelter.get_node("Lights/Bay02Light0_-1") as OmniLight3D
		# Stay inside the doorway but nearer the real lamp so the dimmed
		# production fixture still gives the unoccluded positive control.
		for probe in [["partition", -9.0], ["closed-gate", -1.5]]:
			aim(Vector3(probe[1], 0, -164.0))
			await compare_light("lamp-" + probe[0], fixture)
	viewport.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: tutorial shelter fixture shadow contracts; native sunlight and partition pixel cases run only with a display")
	quit(0 if failures.is_empty() else 1)
