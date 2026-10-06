extends SceneTree
var failures: Array[String] = []
var gallery: Node3D
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok and failures.size() < 30: failures.append(note)

func walk(target: Vector3) -> void:
	var player: CharacterBody3D = gallery.player
	player.camera.rotation = Vector3.ZERO
	for frame in range(500):
		var delta := target - player.position
		delta.y = 0
		if delta.length() < 0.35:
			Input.action_release("move_forward")
			check(absf(player.position.y) < 0.5, "Player unsupported")
			return
		player.rotation.y = atan2(-delta.x, -delta.z)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	check(false, "Blocked route in %d at %s to %s" % [gallery.selected, player.position, target])

func run() -> void:
	gallery = load("res://tests/minor_poi_playground.tscn").instantiate()
	root.add_child(gallery)
	current_scene = gallery
	for i in range(600):
		await physics_frame
		if gallery.ready_for_play: break
	check(gallery.ready_for_play, "Gallery becomes playable")
	for variant in range(18):
		gallery.selected = variant
		await gallery.show_site()
		var id: String = MinorSites.definition_ids()[variant]
		var definition := POIConfig.definition(StringName(id))
		check(definition.validate_scene(gallery.site_node).is_empty(), "Valid asset " + id)
		var shape := CapsuleShape3D.new()
		shape.radius = 0.5
		shape.height = 2
		for marker in gallery.site_node.get_node("EnemySpawns").get_children():
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform.origin = marker.global_position + Vector3.UP
			query.collision_mask = 1
			# Actors deliberately excluded: test authored obstacle clearance.
			for actor in WorldEntities.get_container(gallery).get_children():
				if actor is CollisionObject3D: query.exclude.append(actor.get_rid())
			var hits := gallery.get_world_3d().direct_space_state.intersect_shape(query)
			check(hits.is_empty(), "Enemy starts in an obstacle " + id + "/" + str(marker.name))
		for actor in WorldEntities.get_container(gallery).get_children():
			if actor is Monster: actor.free()
		for frame in range(90): await physics_frame
		var props: Array[Node] = WorldEntities.get_container(gallery).get_children()
		check(props.size() >= 2 and props.size() <= 4, "2–4 physical supplies " + id)
		for prop in props: check(prop.position.y > -0.1, "Loot supported " + id)
		var navmap: RID = gallery.navigation.get_navigation_map()
		for local in [Vector3(-5,0,5.2), Vector3(-5,0,1.2), Vector3(5,0,1.2), Vector3(5,0,5.2)]:
			var path := NavigationServer3D.map_get_path(navmap, Vector3(0,0,8), local, true)
			check(path.size() >= 2 and path[-1].distance_to(local) < 0.8, "Navigation reaches supplies " + id)
			await walk(Vector3(0, 0, gallery.player.position.z))
			await walk(Vector3(0, 0, local.z))
			await walk(local)
		# Test a real fuel can in both fuel themes, regardless of this seed's draw.
		var item: Item = props[0]
		if variant / 3 == 0 or variant / 3 == 4:
			var pose := item.global_transform
			item.free()
			item = load("res://props/gas_can.tscn").instantiate()
			WorldEntities.get_container(gallery).add_child(item)
			item.global_transform = pose
			item.position.y = 0.85
			for frame in range(60): await physics_frame
		var approach: Vector3 = item.position + Vector3(0, 0, 1.2)
		await walk(Vector3(0, 0, gallery.player.position.z))
		await walk(Vector3(0, 0, approach.z))
		await walk(Vector3(approach.x, 0, approach.z))
		gallery.player.camera.look_at(item.global_position)
		for frame in range(10): await physics_frame
		var before: int = gallery.player.inventory.items.size()
		Input.action_press("interact")
		for frame in range(12): await physics_frame
		Input.action_release("interact")
		check(gallery.player.inventory.items.size() == before + 1, "E pickup " + id)
		await walk(Vector3(0, 0, 8))
		await walk(Vector3(-8, 0, 16))
		# Reset only the test inventory before the next independent layout.
		while gallery.player.inventory.consume_active(): pass
		print("MINOR_ASSET_CHECK ", id)
	gallery.free()
	if failures.is_empty(): print("PASS: all 18 layouts, real walking/pickup/return, fuel carrying, navigation and spawn clearance")
	for note in failures: push_error("FAIL: " + note)
	quit(0 if failures.is_empty() else 1)
