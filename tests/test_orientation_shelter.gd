extends SceneTree
## Building finish, world posters, real door collision and authored support.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func ray(building: Node3D, first: Vector3, last: Vector3) -> Dictionary:
	return building.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(building.to_global(first), building.to_global(last), 1))

func poster_copy_check(label: Label3D) -> void:
	var text := label.text
	var english := not text.strip_edges().is_empty()
	for index in text.length():
		var code := text.unicode_at(index)
		if code != 10 and code != 13 and code != 9 and (code < 32 or code > 126): english = false
	check(english, "%s uses readable English world copy" % label.name)
	var instruction := RegEx.new()
	instruction.compile("(?i)\\b(press|hold|enter|esc|space|ctrl|shift|f[1-9]|conditions|objectives|checklist)\\b|\\[[ xX]\\]|\\b(step|stage)\\s+[0-9]")
	check(instruction.search(text) == null, "%s has no key prompts or tutorial requirements" % label.name)
	check(label.font_size * label.pixel_size >= 0.06 and not label.no_depth_test, "%s remains physical readable wall text" % label.name)

func structural_mesh_check(building: Node3D) -> void:
	var large_axes := 0
	for visual: MeshInstance3D in building.get_node("Visuals").find_children("*", "MeshInstance3D", true, false):
		var box := visual.mesh as BoxMesh
		if box == null: continue
		var subdivisions := Vector3i(box.subdivide_width, box.subdivide_height, box.subdivide_depth)
		for axis in 3:
			if box.size[axis] < 20.0: continue
			large_axes += 1
			check(subdivisions[axis] > 0, "%s large mesh axis %d is subdivided for directional shadows" % [visual.name, axis])
	check(large_axes > 0, "Shadow subdivision checks cover the large building surfaces")

func model_bounds(model: Node3D, relative_to: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = relative_to.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	check(not first, "%s contains inspectable visual geometry" % model.name)
	return bounds

func building_finish_check(building: Node3D) -> void:
	var finish := building.get_node_or_null("Visuals/BuildingFinish") as Node3D
	check(finish != null, "The two-room building includes its authored finish")
	if finish == null: return
	check(not finish.find_children("*", "MeshInstance3D", true, false).is_empty(), "Building finish contains visible architecture")
	for index in 2:
		var plant: Node3D = finish.get_node("RoofPlant%d" % index)
		var plinth: MeshInstance3D = plant.get_node("Plinth")
		var roof: MeshInstance3D = finish.get_node("ServiceCoping-1" if index == 0 else "ServiceCoping1")
		var roof_box: AABB = roof.transform * roof.get_aabb()
		var plinth_box: AABB = building.global_transform.affine_inverse() * plinth.global_transform * plinth.get_aabb()
		check(roof_box.grow(0.005).intersects(plinth_box) and absf(plinth_box.position.y - roof_box.end.y) < 0.01, "Roof plant %d plinth rests on the service-wing roof" % index)
		var plant_box := model_bounds(plant.get_node("PlantModel"), plant)
		var base_box: AABB = plinth.transform * plinth.get_aabb()
		for side in [-1, 1]:
			var rail: MeshInstance3D = plant.get_node("Rail%d" % side)
			var rail_box: AABB = rail.transform * rail.get_aabb()
			check(base_box.grow(0.005).intersects(rail_box), "Roof plant %d rail %d touches its plinth" % [index, side])
			check(rail_box.grow(0.01).intersects(plant_box) and absf(plant_box.position.y - rail_box.end.y) < 0.02, "Roof plant %d model rests on rail %d" % [index, side])

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
	var workshop_poster := building.get_node_or_null("Visuals/WorkshopPoster") as Node3D
	check(workshop_poster != null and building.has_node("Visuals/WorkshopPoster/Text"), "The workshop has its second world poster")
	check(building.get_node("Visuals").find_children("*Poster", "", true, false).size() == 2, "Exactly two world poster assemblies are authored")
	if workshop_poster != null:
		check(workshop_poster.position.z > -26.0 and workshop_poster.position.z < 14.0 and absf(workshop_poster.position.x) >= 4.0, "Workshop poster stays in room two and outside the vehicle lane")
	for label: Label3D in building.get_node("Visuals").find_children("*", "Label3D", true, false): poster_copy_check(label)
	structural_mesh_check(building)
	building_finish_check(building)
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
	for x in [-3.4, 0.0, 3.4]:
		for y in [0.5, 2.0, 4.8]:
			check(ray(building, Vector3(x, y, -35), Vector3(x, y, 13)).is_empty(), "Open gate and workshop preserve the vehicle passage at x=%.1f y=%.1f" % [x, y])
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
	if failures.is_empty(): print("PASS: two-room footprint, building finish/support, two world posters, shadow subdivisions, real gate/lane collision and generation isolation")
	quit(0 if failures.is_empty() else 1)
