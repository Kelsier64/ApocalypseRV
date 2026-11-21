extends SceneTree
## Sampled world-generation contracts: v14 landforms, world detail, off-road
## sites, building locators, the building kit and megashelter exteriors. Split from
## test_streaming_generation so each process stays well inside the runner timeout.
const TERRAIN_HOST = preload("res://tests/support/terrain_host.gd")
const V14_CONTRACTS = preload("res://tests/support/terrain_v14_contracts.gd")
const WORLD_DETAIL_CONTRACTS = preload("res://tests/support/world_detail_contracts.gd")
const OFFROAD_CONTRACTS = preload("res://tests/support/offroad_site_contracts.gd")
const MILE_END_CONTRACTS = preload("res://tests/support/mile_end_contracts.gd")
const BUILDING_LOCATOR_CONTRACTS = preload("res://tests/support/building_locator_contracts.gd")
const MEGASHELTER_CONTRACTS = preload("res://tests/support/megashelter_contracts.gd")
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	var world: Node3D = TERRAIN_HOST.new()
	root.add_child(world)
	current_scene = world
	await V14_CONTRACTS.run(self, world, check)
	await WORLD_DETAIL_CONTRACTS.run(self, world, check)
	await OFFROAD_CONTRACTS.run(self, world, check)
	await MILE_END_CONTRACTS.run(self, world, check)
	await preload("res://tests/support/orbit_plaza_contracts.gd").run(self, world, check)
	BUILDING_LOCATOR_CONTRACTS.run(check)
	await preload("res://tests/support/building_kit_contracts.gd").run(self, world, check)
	await MEGASHELTER_CONTRACTS.run(self, world, check)
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: v14 landforms, world detail, off-road sites, building locators and megashelter exteriors satisfy sampled contracts")
	quit(0 if failures.is_empty() else 1)
