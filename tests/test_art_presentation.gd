extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	await physics_frame
	await physics_frame
	var roof: Equipment = rv.get_node("Ceiling")
	var cabin: Node3D = roof.get_node("CabinLighting")
	rv.current_power = 50
	await physics_frame
	await process_frame
	check(cabin.lamps.all(func(lamp): return lamp.visible), "Powered installed ceiling illuminates cabin")
	rv.current_power = 0
	await physics_frame
	await process_frame
	await process_frame
	check(cabin.lamps.all(func(lamp): return not lamp.visible), "Empty battery extinguishes cabin lamps")
	rv.current_power = 50
	roof.detach_from_support()
	await physics_frame
	await process_frame
	check(cabin.lamps.all(func(lamp): return not lamp.visible), "Detached ceiling never keeps powered lights")
	var panel: Equipment = rv.get_node("RightFront")
	var mesh: MeshInstance3D = panel.get_node("Lower")
	panel.current_health = panel.max_health
	await process_frame
	await process_frame
	var healthy: StandardMaterial3D = mesh.get_active_material(0)
	check(healthy.albedo_texture != null, "Healthy RV retains original worn paint texture")
	panel.current_health = panel.max_health * 0.2
	await process_frame
	await process_frame
	var damaged: StandardMaterial3D = mesh.get_active_material(0)
	check(damaged.detail_enabled and damaged.albedo_texture == healthy.albedo_texture and damaged.albedo_color != healthy.albedo_color, "Damage adds scuffs and darkening without erasing base paint")
	panel.current_health = panel.max_health
	await process_frame
	await process_frame
	check(not mesh.get_active_material(0).detail_enabled, "Repair restores healthy aged appearance")
	var indoor: StandardMaterial3D = load("res://world/poi_kit/materials/concrete.tres")
	var tint := indoor.albedo_color
	var texture := indoor.albedo_texture
	for kind in ExplorationSite.TYPES:
		var scene: Node3D = load("res://world/poi_kit/exteriors/%s.tscn" % kind).instantiate()
		world.add_child(scene)
		check(scene.has_node("Entrance") and scene.has_node("ReturnPoint"), "Entrance contract survives exterior art: " + kind)
		scene.queue_free()
	check(indoor.albedo_color == tint and indoor.albedo_texture == texture, "Exterior styling does not mutate shared interior material")
	# Pine cap normals must face upwards: backwards faces made the canopy look hollow.
	for kind in range(4):
		var arrays := ForestMeshes.tree(kind).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var highest := 0
		for i in range(vertices.size()):
			if vertices[i].y > vertices[highest].y: highest = i
		check(normals[highest].y > 0, "Pine crown faces outward: " + str(kind))
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: art materials, damage repair, powered/detached roof and preserved entrance contracts")
	quit(0 if failures.is_empty() else 1)
