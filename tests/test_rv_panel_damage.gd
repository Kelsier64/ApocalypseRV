extends SceneTree
## Shell wear and cosmetic bursts must retain the existing structure contract.
var failures: Array[String] = []
var world: Node3D
var rv: Chassis

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count := 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func cosmetic_tree(node: Node) -> void:
	check(not node is CollisionObject3D and not node is CollisionShape3D and not node is Item, "Damage presentation has no gameplay body, shape or Item")
	for group in [Groups.ITEMS, Groups.MONSTERS, Groups.MONSTER_DAMAGEABLE]:
		check(not node.is_in_group(group), "Damage presentation does not register a gameplay entity")
	for child in node.get_children():
		cosmetic_tree(child)

func geometry(panel: RVStructurePanel) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in panel.find_children("*", "CollisionShape3D", true, false):
		result.append({"node": node, "shape": node.shape, "pose": node.transform})
	return result

func same_geometry(panel: RVStructurePanel, original: Array[Dictionary], detail: String) -> void:
	check(panel.find_children("*", "CollisionShape3D", true, false).size() == original.size(), detail + " retains all original collision pieces")
	for entry in original:
		check(is_instance_valid(entry.node) and entry.node.shape == entry.shape and entry.node.transform == entry.pose, detail + " retains collision resources and poses")

func _run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await steps(3)
	await _wear_and_restore()
	await _damage_lifecycle()
	await _realistic_debris()
	world.free()
	if failures.is_empty():
		print("PASS: RV shell wear and damage effects preserve HP, collision and restoration")
	quit(0 if failures.is_empty() else 1)

func _wear_and_restore() -> void:
	var wall: RVStructurePanel = rv.get_node("LeftFront")
	var neighbour: RVStructurePanel = rv.get_node("LeftRear")
	var painted: MeshInstance3D = wall.get_node("Lower")
	var neighbour_painted: MeshInstance3D = neighbour.get_node("Lower")
	var glass: MeshInstance3D = wall.get_node("Window-0.96")
	var source := painted.mesh.surface_get_material(0) as StandardMaterial3D
	var original_color := source.albedo_color
	var original_texture := source.albedo_texture
	var original_glass := glass.get_active_material(0) as StandardMaterial3D
	var original_glass_texture := original_glass.albedo_texture
	var collision := geometry(wall)
	wall.set_health(wall.max_health * 0.95)
	await steps()
	check((painted.get_active_material(0) as StandardMaterial3D).next_pass != null, "Small health loss already receives continuous visible wear")
	var early_wear: Node = wall.get_node("PanelWear")
	check(is_equal_approx(early_wear.severity, 0.05), "Wear severity follows the actual HP ratio before stage thresholds")
	wall.set_health(wall.max_health * 0.6)
	await steps()
	var worn := painted.get_active_material(0) as StandardMaterial3D
	check(worn != source and worn != neighbour_painted.get_active_material(0), "Each damaged panel owns isolated paint presentation")
	check(worn.albedo_color != original_color or worn.detail_enabled or worn.next_pass != null, "Declining health visibly changes paint")
	check(source.albedo_color == original_color and source.albedo_texture == original_texture, "Wear leaves shared source paint intact")
	check(neighbour.current_health == neighbour.max_health, "Wear has no neighbouring health owner")
	same_geometry(wall, collision, "Partial wall damage")
	for entry in collision:
		check(not entry.node.disabled, "Partial damage leaves solid wall collision enabled")
	wall.set_health(wall.max_health * 0.2)
	await steps()
	var severe := painted.get_active_material(0) as StandardMaterial3D
	var wear: Node = wall.get_node("PanelWear")
	check(wear.level == 2 and is_equal_approx(wear.severity, 0.8), "Severe damage advances the wear stage and health-driven severity")
	check(severe.next_pass != null, "Severe paint damage retains the wear overlay")
	var cracked := glass.get_active_material(0) as StandardMaterial3D
	var cracks := cracked.next_pass as ShaderMaterial
	check(cracked.albedo_texture == original_glass_texture and cracks != null, "Damaged glazing retains its original texture beneath cracks")
	if cracks:
		check(cracks.get_shader_parameter("glass") == true and is_equal_approx(float(cracks.get_shader_parameter("damage")), 0.8), "Glazing crack overlay follows the panel health")
	wall.set_health(wall.max_health)
	await steps()
	var restored := painted.get_active_material(0) as StandardMaterial3D
	check(restored.albedo_color == original_color and restored.albedo_texture == original_texture and restored.detail_enabled == source.detail_enabled, "Restoration returns the original paint")
	var clean_glass := glass.get_active_material(0) as StandardMaterial3D
	check(clean_glass.albedo_texture == original_glass_texture and clean_glass.next_pass == original_glass.next_pass, "Restoration removes glazing cracks")
	same_geometry(wall, collision, "Restored wall")
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var hatch := slots.replace_panel("roof_1", "rv_ceiling_hatch", 120.0)
	await steps()
	var hatch_geometry := geometry(hatch)
	check(hatch_geometry.size() == 4, "Roof hatch fixture retains its authored four-piece hole")
	hatch.set_health(hatch.max_health * 0.2)
	await steps()
	same_geometry(hatch, hatch_geometry, "Worn roof hatch")

func _damage_lifecycle() -> void:
	var wall: RVStructurePanel = rv.get_node("LeftFront")
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var effects_script: Script = load("res://rv/panel_damage_effect.gd")
	var group: String = effects_script.GROUP
	check(get_nodes_in_group(group).is_empty(), "Construction and restoration create no impact bursts")
	var before := wall.current_health
	for amount in [0.0, -2.0, NAN, INF]:
		wall.take_damage(amount)
	check(wall.current_health == before and get_nodes_in_group(group).is_empty(), "Invalid damage changes neither health nor effects")
	rv.linear_velocity = Vector3(20.0, 0.0, 0.0)
	rv.angular_velocity = Vector3(0.0, 0.4, 0.0)
	wall.take_damage(30.0)
	check(wall.current_health == before - 30.0, "Accepted damage decrements the single panel HP owner exactly once")
	var hits := get_nodes_in_group(group)
	check(hits.size() == 1, "Real damage emits one transient hit effect")
	if hits.is_empty(): return
	var hit := hits[0] as Node3D
	cosmetic_tree(hit)
	check(not hit.fragments.is_empty(), "Hit effect produces bounded visible fragments")
	for fragment in hit.fragments:
		var expected := ClimbMath.point_velocity(rv, fragment.node.global_position)
		check((fragment.velocity - expected).length() <= 6.0, "Moving vehicle fragments inherit real contact-point velocity plus bounded scatter")
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	check(hit.top_level and hit.get_parent() == rv, "Transient hit is owned by the vehicle outside the disappearing panel")
	var effect_pose := hit.global_transform
	var panel_pose := wall.global_transform
	rv.position += Vector3(6.0, 0.0, 0.0)
	check(hit.global_transform.is_equal_approx(effect_pose), "Detached cosmetic burst does not teleport with the moving chassis")
	check(wall.global_position.distance_to(panel_pose.origin + Vector3(6.0, 0.0, 0.0)) < 0.001, "Real structure continues to move with the chassis")
	wall.set_health(wall.max_health)
	check(get_nodes_in_group(group).size() == 1, "Direct restoration creates no fresh damage burst")
	var collision := geometry(wall)
	wall.take_damage(999.0)
	await steps()
	var bursts := get_nodes_in_group(group)
	check(bursts.size() == 2, "Destruction bypasses hit cooldown and emits its own burst")
	check(wall.is_destroyed and wall.current_health == 0.0 and not wall.visible and wall.collision_layer == 0, "Destruction retains HP ownership and removes the real shell")
	check(slots.panel(wall.mount_slot) == wall and slots.occupant(wall.mount_slot) == null, "Destroyed panel state survives while its construction slot becomes empty")
	same_geometry(wall, collision, "Destroyed wall")
	for entry in collision:
		check(entry.node.disabled, "Destruction disables original panel collision")
	for burst in bursts:
		cosmetic_tree(burst)
		check(burst.is_visible_in_tree(), "Destruction burst remains visible after the panel hides")
	wall.take_damage(1.0)
	check(get_nodes_in_group(group).size() == 2, "Already destroyed panel cannot emit repeated hits")
	wall.set_health(wall.max_health)
	await steps()
	check(get_nodes_in_group(group).size() == 2 and wall.visible and slots.occupant(wall.mount_slot) == wall, "Restoring a destroyed shell is silent and reactivates the same slot owner")
	for burst in bursts:
		burst._process(effects_script.LIFETIME + 0.1)
	await process_frame
	check(get_nodes_in_group(group).is_empty(), "Transient damage effects release all emitters and fragments at their lifetime")
	# Hits across many panel owners still share a bounded per-vehicle budget.
	for panel in rv.get_structures():
		panel.take_damage(1.0)
	await process_frame
	check(get_nodes_in_group(group).size() <= effects_script.MAX_ACTIVE_PER_VEHICLE, "One vehicle bounds simultaneous cosmetic damage effects")
	for burst in get_nodes_in_group(group):
		burst._process(effects_script.LIFETIME + 0.1)
	await process_frame
	var expected_health := wall.current_health
	var snapshot := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(snapshot), "Cosmetic damage activity adds no incompatible snapshot fields")
	check(VehicleSnapshot.apply(rv, snapshot), "Production structure snapshot restores worn health")
	await steps()
	check(get_nodes_in_group(group).is_empty(), "Checkpoint restoration never replays historical impact or destruction bursts")
	var restored_wall := slots.panel("left_0")
	check(is_equal_approx(restored_wall.current_health, expected_health), "Snapshot retains the original single panel health value")

func _realistic_debris() -> void:
	# Isolate cosmetic ground contact from the real RV and its collision contract.
	var ground := StaticBody3D.new()
	ground.position = Vector3(40.0, -0.25, 0.0)
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.5, 40.0)
	shape.shape = box
	ground.add_child(shape)
	world.add_child(ground)
	var hatch: RVStructurePanel = load("res://equipment/rv_ceiling_hatch.tscn").instantiate()
	hatch.position = Vector3(40.0, 4.0, 0.0)
	world.add_child(hatch)
	await steps()
	var paint := hatch.get_node("Visual/Right").get_active_material(0) as StandardMaterial3D
	var source_texture := paint.albedo_texture
	var collision := geometry(hatch)
	hatch.set_health(0.0)
	await steps()
	var effects_script: Script = load("res://rv/panel_damage_effect.gd")
	var effect: Node3D = effects_script.spawn(hatch, true)
	check(effect != null and not effect.fragments.is_empty(), "Destroyed hatch produces structural debris")
	if effect == null: return
	effect.set_process(false)
	effect.set_physics_process(false)
	cosmetic_tree(effect)
	var painted_chunks := 0
	var structural_chunks := 0
	for fragment in effect.fragments:
		if not fragment.structural: continue
		structural_chunks += 1
		var mesh: MeshInstance3D = fragment.node
		var bounds := mesh.mesh.get_aabb()
		check(bounds.size[bounds.size.min_axis_index()] > 0.005, "Structural debris retains finite panel thickness")
		var point := hatch.to_local(mesh.global_position)
		check(not (point.x > -1.78 and point.x < -0.37 and absf(point.z) < 0.78), "Hatch debris starts on authored solid pieces rather than filling the opening")
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material and material.albedo_texture == source_texture:
				painted_chunks += 1
				check(material.uv1_triplanar == paint.uv1_triplanar and material.uv1_scale == paint.uv1_scale, "Debris carries original paint texture projection")
				var arrays := mesh.mesh.surface_get_arrays(surface)
				check(not arrays[Mesh.ARRAY_TEX_UV].is_empty(), "Debris retains paint UV coordinates")
	check(structural_chunks > 0 and painted_chunks > 0, "Destruction releases actual painted shell chunks")
	# Use the production sweep against registered physics geometry, including a
	# fast downward step that would tunnel straight through the slab without it.
	for fragment in effect.fragments:
		fragment.velocity = Vector3(0.0, -35.0, 0.0)
		fragment.spin = Vector3.ZERO
	for frame in range(300):
		effect._physics_process(1.0 / 60.0)
	var settled_positions: Array[Vector3] = []
	for fragment in effect.fragments:
		check(fragment.settled, "Structural debris settles after sweeping into solid ground")
		var mesh: MeshInstance3D = fragment.node
		var world_bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		check(world_bounds.position.y >= -0.025, "Settled panel geometry remains above the ground surface")
		settled_positions.append(mesh.global_position)
	for frame in range(60):
		effect._physics_process(1.0 / 60.0)
	for index in range(effect.fragments.size()):
		check(effect.fragments[index].node.global_position.is_equal_approx(settled_positions[index]), "Settled cosmetic panels remain stationary on stable support")
	var support_motion := Vector3(0.4, 0.2, 0.0)
	ground.position += support_motion
	effect._physics_process(1.0 / 60.0)
	for index in range(effect.fragments.size()):
		check(effect.fragments[index].node.global_position.is_equal_approx(settled_positions[index] + support_motion), "Settled debris follows its actual moving support")
	ground.collision_layer = 0
	effect._physics_process(1.0 / 60.0)
	for fragment in effect.fragments:
		check(not fragment.settled and fragment.velocity.y < support_motion.y * 60.0, "Removing support releases debris with inherited movement and gravity")
	same_geometry(hatch, collision, "Destroyed hatch")
	check(hatch.is_destroyed and hatch.current_health == 0.0 and hatch.collision_layer == 0, "Cosmetic ground contact cannot revive or damage the original panel")
	effect._process(effects_script.LIFETIME + 0.1)
	await process_frame
	check(not is_instance_valid(effect), "Settled debris is released at the bounded effect lifetime")
	hatch.free()
	ground.free()
