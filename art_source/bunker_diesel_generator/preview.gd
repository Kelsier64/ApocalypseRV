extends SceneTree
## One-off source review: real power hall, existing lighting and wrapper collision.
## -- --capture saves three authored views and exits; otherwise F2 switches view, Esc exits.

var output: String
var camera: Camera3D
var flashlight: SpotLight3D
var view_index := 0
var failures: Array[String] = []
var manual := true
var deadline := 0

class ReviewControls extends Node:
	var review
	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F2:
				review.set_view(review.view_index + 1)
			elif event.keycode == KEY_ESCAPE:
				review.quit()

func _init() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error(detail)

func mesh_bounds(node: Node, transform_parent: Transform3D = Transform3D.IDENTITY) -> AABB:
	var pose := transform_parent
	if node is Node3D:
		pose *= node.transform
	var result := AABB()
	var initialized := false
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point := pose * vertex
				result = result.expand(point) if initialized else AABB(point, Vector3.ZERO)
				initialized = true
	for child in node.get_children():
		var other := mesh_bounds(child, pose)
		if other.size.length_squared() > 0.0:
			result = result.merge(other) if initialized else other
			initialized = true
	return result

func set_view(index: int) -> void:
	view_index = index % 3
	flashlight.visible = view_index == 2
	if view_index != 1:
		camera.position = Vector3(-1.45, 1.8, -3.7)
		camera.look_at(Vector3(-4.82, 0.86, -5.1))
	else:
		camera.position = Vector3(2.6, 1.7, 0.2)
		camera.look_at(Vector3(-3.0, 1.35, -5.25))
	DisplayServer.window_set_title("Diesel Generator Review | Power Hall | F2 view / Esc exit")

func _process(_delta: float) -> bool:
	if not manual or camera == null:
		return false
	if Time.get_ticks_msec() > deadline:
		quit()
	return false

func capture(name: String) -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Save " + name)

func run() -> void:
	manual = "--capture" not in OS.get_cmdline_user_args()
	deadline = Time.get_ticks_msec() + 300000
	output = "res://.godot/art-work/bunker_diesel_generator/capture_" + str(Time.get_unix_time_from_system()).replace(".", "_")
	DirAccess.make_dir_recursive_absolute(output)
	print("Generator capture output: ", output)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var hall: PoiRoom = load("res://world/poi_kit/rooms/bunker/v2/hall_02.tscn").instantiate()
	world.add_child(hall)
	var definition := InteriorLayout.PROFILE.room("hall_02", 2)
	BunkerLighting.apply(hall, definition, false)
	check(hall.validate().is_empty(), "Power hall authored interfaces validate")
	var generator: StaticBody3D = hall.get_node("Furnishings/diesel_generator_graybox_0")
	var model := generator.get_node("Visuals/Model/Generator")
	var bounds := mesh_bounds(model)
	var size_target := Vector3(3.2, 1.7, 1.2)
	check(bounds.size.distance_to(size_target) < 0.002, "Measured design dimensions within 2 mm")
	check(bounds.position.distance_to(Vector3(-1.6, 0, -0.6)) < 0.002, "Bottom-center origin within 2 mm")
	var collision: CollisionShape3D = generator.get_node("Collision")
	check(collision.shape is BoxShape3D and collision.shape.size == size_target, "Wrapper box collision unchanged")
	check(collision.position == Vector3(0, 0.85, 0) and not collision.disabled, "Wrapper collision pose/enabled unchanged")
	check(generator.collision_layer == 1 and generator.collision_mask == 1, "Wrapper collision layers unchanged")
	check(generator.get_node("Visuals/Model") is Node3D, "Model container preserved")
	check(generator.get_node("Visuals/Model/Blockout") is MeshInstance3D, "Blockout name/type preserved")
	check(generator.get_node("Visuals/Model/Cover") is MeshInstance3D, "Cover name/type preserved")
	check(generator.get_node("Visuals/Model/Stencil") is Label3D, "Stencil name/type preserved")
	for old_visual in ["Blockout", "Cover", "Stencil"]:
		check(not generator.get_node("Visuals/Model/" + old_visual).visible, "Old visual hidden: " + old_visual)
	check(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Generated visuals add no collision or actors")
	await physics_frame
	await physics_frame
	var service_direction := generator.global_basis * Vector3.FORWARD * -1
	var query := PhysicsRayQueryParameters3D.create(generator.global_position + Vector3.UP * 0.85 + service_direction * 2.0, generator.global_position + Vector3.UP * 0.85)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == generator, "Service-side ray still hits wrapper collision")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("111511")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("afb9a3")
	environment.environment.ambient_light_energy = BunkerLighting.AMBIENT_ENERGY
	world.add_child(environment)
	camera = Camera3D.new()
	camera.fov = 60
	camera.current = true
	world.add_child(camera)
	# Duplicate the production flashlight beam, not its item or physics behavior.
	var source_flashlight: Node3D = load("res://props/flashlight.tscn").instantiate()
	flashlight = source_flashlight.get_node("Beam").duplicate() as SpotLight3D
	source_flashlight.free()
	camera.add_child(flashlight)
	flashlight.position = Vector3(0.15, -0.08, -0.1)
	flashlight.rotation = Vector3.ZERO
	flashlight.visible = false
	var controls := ReviewControls.new()
	controls.review = self
	world.add_child(controls)
	root.size = Vector2i(1280, 720)
	var result := {"state": "PASS" if failures.is_empty() else "FAIL", "failures": failures,
		"measured_visual_aabb_position_m": [bounds.position.x, bounds.position.y, bounds.position.z],
		"measured_visual_size_m": [bounds.size.x, bounds.size.y, bounds.size.z], "tolerance_m": 0.002,
		"collision_size_m": [collision.shape.size.x, collision.shape.size.y, collision.shape.size.z],
		"service_face_world_direction": [service_direction.x, service_direction.y, service_direction.z],
		"environment": "PoiInterior v2 ambient + BunkerLighting.apply(lit hall); third view adds production flashlight Beam",
		"godot_version": Engine.get_version_info().string, "rendering_method": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(output.path_join("validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("GENERATOR_REVIEW " + JSON.stringify(result))
	set_view(0)
	if not manual:
		await capture("power_hall_close")
		set_view(1)
		await capture("power_hall_wide")
		set_view(2)
		await capture("power_hall_flashlight")
		quit(0 if failures.is_empty() else 1)
	elif not failures.is_empty():
		quit(1)
