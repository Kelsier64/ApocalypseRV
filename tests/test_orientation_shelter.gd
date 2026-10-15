extends SceneTree
## Stage-one building boundaries, real door collision and authored support.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func ray(building: Node3D, first: Vector3, last: Vector3) -> Dictionary:
	return building.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(building.to_global(first), building.to_global(last), 1))

func _run() -> void:
	var definition := POIConfig.definition(&"orientation_shelter")
	check(definition != null and definition.validate().is_empty(), "Dedicated v12 definition is valid")
	if definition == null: quit(1); return
	check(not "orientation_shelter" in POIConfig.GENERATION_IDS, "Opening is not part of random POI generation")
	var building: Node3D = load(definition.scene_path).instantiate()
	root.add_child(building)
	check(definition.validate_scene(building).is_empty(), "Two-room scene follows POI layer/bounds contract")
	check(building.get_node("Bays").get_child_count() == 2, "Exactly two rooms")
	for room in [1, 2]:
		var bay := building.get_node("Bays/Bay%02d" % room)
		check(is_equal_approx(bay.get_meta("end_z") - bay.get_meta("start_z"), 20.0 if room == 1 else 40.0), "Room %d has its specified length" % room)
	check(building.get_node("Gates").get_child_count() == 1 and not building.has_node("GarageButton"), "One inner gate; departure has no manual button")
	check(building.get_node("StarterEquipment").get_child_count() == 1 and building.get_node("StarterEquipment/TrainingTerminal") is Marker3D, "Only the wall-terminal spawn is authored")
	check(building.get_node("WorkshopEquipment").get_child_count() == 2 and building.get_node("WorkshopSupplies").get_child_count() == 14, "Workshop provides two loose machines and fourteen supplies including extra salvage and service stock")
	for category in ["WorkshopEquipment", "WorkshopSupplies"]:
		for marker: Marker3D in building.get_node(category).get_children():
			check(marker.position.z > -26.0 and marker.position.z < 14.0 and absf(marker.position.x) >= 4.0, "Workshop stock remains in the second room and outside the eight-metre vehicle lane")
	check(building.get_node("PlayerSpawn").position.z < -26.0 and building.get_node("RVSpawn").position.z > -26.0, "Player and RV belong to separate rooms")
	for index in range(5):
		var beam: MeshInstance3D = building.get_node("Visuals/CrossBeam%d" % index)
		for side in [-1, 1]:
			var housing: MeshInstance3D = building.get_node("Visuals/Lamp%d_%d/Housing" % [index, side])
			var beam_box: AABB = beam.transform * beam.get_aabb()
			var lamp_box: AABB = housing.get_parent().transform * housing.transform * housing.get_aabb()
			check(beam_box.grow(0.005).intersects(lamp_box), "Lamp housing touches its cross-beam")
	var paper: MeshInstance3D = building.get_node("Visuals/PosterPaper")
	check(paper.position.z < -45.8, "Poster is attached to the reception wall")
	var text: String = building.get_node("Visuals/PosterText").text
	check("training terminal" in text and not "Enter" in text and not "Hold" in text, "World poster names the terminal without key instructions")
	await physics_frame
	await physics_frame
	for point in [Vector3(-18, 2, -44), Vector3(0, 2, -35), Vector3(18, 2, 12)]:
		check(not ray(building, point, point - Vector3.UP * 4).is_empty(), "Both rooms have continuous floor collision")
	check(not ray(building, Vector3(0, 2, -35), Vector3(0, 2, -15)).is_empty(), "Closed partition conceals the workshop")
	check(not ray(building, Vector3(8, 2, -35), Vector3(8, 2, -15)).is_empty(), "Partition is solid beside doorway")
	var gate: ShelterGarageGate = building.get_node("Gates/Gate01")
	gate.move_to(true)
	for index in range(160): await physics_frame
	check(gate.is_open(), "Physical inner leaves finish opening")
	check(ray(building, Vector3(0, 2, -35), Vector3(0, 2, -15)).is_empty(), "Opening clears the central passage")
	for version in [10, 11, 12]:
		var profile := WorldProfile.new()
		profile.generation_version = version
		var field := WorldField.new(42, profile)
		var site := field.stop(0)
		var expected := "orientation_shelter" if version == 12 else ("tutorial_shelter" if version == 11 else "starting_shelter")
		check(site.definition_id == expected, "v%d preserves its own authored opening" % version)
		if version != 12: continue
		for x in [-32.0, -20.4, 0.0, 20.4, 32.0]:
			for z in [-58.0, -46.0, -35.0, -26.0, -10.0, 14.0, 44.0]:
				var point: Vector3 = site.building * Vector3(x, 0, z)
				check(field.surface(point.x, point.z).reserved, "Entire new depot excludes vegetation")
	building.free()
	if failures.is_empty(): print("PASS: two-room footprint, structural support, poster, real gate collision and generation isolation")
	quit(0 if failures.is_empty() else 1)
