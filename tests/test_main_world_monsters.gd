extends SceneTree
## Check the actual main scene, including production terrain spawning.
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	var generator = world.get_node("WorldGenerator")
	generator.world_seed = 1
	# The starting bands contain an entrance and a peaceful walk-in site.
	# Load the real v5 outdoor encounter at stop 2, as streaming would do.
	var field := WorldField.new(1)
	var encounter := field.stop(2)
	var band := floori(float(encounter.s) / field.profile.chunk_length)
	generator.restore_bands.assign(range(band - field.profile.chunks_behind, band + field.profile.chunks_ahead + 1))
	world.get_node("Player").position = encounter.road.origin + Vector3.UP * 2
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play(60000):
		push_error("FAIL: main world monster check timed out")
		world.free()
		quit(1)
		return
	var count := 0
	var valid := true
	for child in WorldEntities.get_container(world).get_children():
		if not child is Monster: continue
		count += 1
		if not child is Raker or child.scene_file_path != "res://enemies/raker.tscn":
			push_error("FAIL: main world still spawned legacy monster: " + child.scene_file_path)
			valid = false
			continue
		var model: MeshInstance3D = child.get_node("BodyMesh/Model").find_child("Raker_Mesh", true, false)
		if model == null or absf(model.get_aabb().size.y - 2.18) > .001:
			push_error("FAIL: main world Raker has the wrong model or height")
			valid = false
			continue
		for surface in model.mesh.get_surface_count():
			var material := model.get_active_material(surface) as StandardMaterial3D
			var oral_lining := material != null and material.resource_name == "Raker018_OralCavity" and material.albedo_color.get_luminance() < .2
			var nail_surface := material != null and material.resource_name == "Raker021_WornNails" and material.roughness >= .7
			if material == null or (material.albedo_texture == null and not oral_lining and not nail_surface):
				push_error("FAIL: main world Raker lost its refined skin texture")
				valid = false
		var skeleton: Skeleton3D = child.get_node("BodyMesh/Model").find_child("Skeleton3D",true,false)
		if skeleton.get_bone_count() != 54 or skeleton.find_bone("middle_03_L") < 0 or skeleton.find_bone("middle_03_R") < 0:
			push_error("FAIL: main world did not load the rebuilt three-phalange hands")
			valid = false
	if count == 0:
		push_error("FAIL: main world test did not encounter any generated monsters")
		valid = false
	if valid: print("PASS: main world spawned %d textured 2.18 m Rakers and no legacy monsters" % count)
	world.free()
	quit(0 if valid else 1)
