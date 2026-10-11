extends SceneTree
## Planner and legacy forest identity invariants, independently of rendering.
class LegacyRearField extends WorldField:
	func _starting_shelter_surface(x: float, z: float, height: float) -> Dictionary:
		var result := super._starting_shelter_surface(x, z, height)
		var ridge := 1.0 - smoothstep(3.0, 16.0, absf(z - 20.0))
		if ridge > 0.0: result.height = lerpf(result.height, 8.0, ridge * smoothstep(25.0, 34.0, absf(x)))
		return result
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok: failures.append(detail); push_error("FAIL: " + detail)
func run() -> void:
	var profile := WorldProfile.new()
	profile.generation_version = 10
	var previous := {}
	for seed_value in [0, 1, 42, 99]:
		var field := WorldField.new(seed_value, profile)
		var legacy := LegacyRearField.new(seed_value, profile)
		var chunk := ChunkGenerator.new()
		chunk.field = field
		var old_chunk := ChunkGenerator.new()
		old_chunk.field = legacy
		for band in [-2, -1, 0]:
			await ForestScenery.prepare(chunk, band, false)
			await ForestScenery.prepare(old_chunk, band, false)
			check(ForestScenery.trees(field, band) == ForestScenery.trees(legacy, band), "v10 rear changes preserve every old forest index and transform")
		chunk.free(); old_chunk.free()
		check(not is_equal_approx(field.height_at(100, 20), 8.0) and is_equal_approx(legacy.height_at(100, 20), 8.0), "v10 removes only transverse berm height")
		var data := RearWreckLayout.plan(field)
		check(RearWreckLayout.valid_state(data) and data.placements.size() > 12 and data.placements.size() <= 28, "Valid bounded rear population for seed %d" % seed_value)
		check(data == RearWreckLayout.plan(field), "Independent slot/path RNG reproduces exact layout")
		if not previous.is_empty(): check(data != previous, "Different seeds change positions and directions")
		previous = data
		var directions := {}
		for placement in data.placements:
			var pose: Transform3D = placement.transform
			directions[roundi(pose.basis.get_euler().y * 10.0)] = true
			check(pose.origin.y - field.height_at(pose.origin.x, pose.origin.z) < 0.16, "Wreck rests on its sampled support")
			check(RearWreckLayout.clears_walkway(RoadSpawns._wreck_footprint(pose), data.walkway), "Whole rotated model clears continuous 1.5m corridor")
		check(directions.size() > 8, "Wrecks independently sample broad yaw range")
		var obstruction := AABB(Vector3(-24, -5, 10), Vector3(48, 20, 100))
		check(RearWreckLayout.plan(field, [obstruction]).placements.is_empty(), "Occupied restored area reduces vehicle count without moving actors")
		for mutation in [{"version": 2}, {"placements": "invalid"}, {"walkway": PackedVector3Array()}]:
			var bad := data.duplicate(true)
			bad.merge(mutation, true)
			check(not RearWreckLayout.valid_state(bad), "Malformed rear ledger rejected")
		var bad := data.duplicate(true)
		bad.placements.append(bad.placements[0].duplicate())
		check(not RearWreckLayout.valid_state(bad), "Duplicate ID and footprint rejected")
	for version in [7, 8, 9]:
		var old_profile := WorldProfile.new()
		old_profile.generation_version = version
		check(is_equal_approx(WorldField.new(42, old_profile).height_at(100, 20), 8.0), "v%d keeps rear berm" % version)
	if failures.is_empty(): print("PASS: rear wreck seed layout, rotated clearance, support, restored exclusions and legacy tree identities")
	quit(0 if failures.is_empty() else 1)
