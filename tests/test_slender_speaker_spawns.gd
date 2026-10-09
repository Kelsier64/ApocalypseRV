extends SceneTree
## Pure planner checks separate probability and geometry from runtime navigation.
class FlatField extends WorldField:
	func road_frame(s: float) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 0, -s))
	func road_query(x: float, z: float) -> Dictionary: return {"s": -z, "distance": absf(x), "height": 0.0, "width": 15.0, "frame": road_frame(-z)}
	func road_width(_s: float) -> float: return 15.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func sites_near_z(_z: float, _radius: float = 240.0) -> Array[Dictionary]: return []
class BlockedPoiField extends FlatField:
	func sites_near_z(_z: float, _radius: float = 240.0) -> Array[Dictionary]:
		return [{"bounds": AABB(Vector3(58, -1, -1602), Vector3(4, 5, 4))}]
	func court_distance(_x: float, _z: float, _site: Dictionary) -> float: return 100.0
class SteepField extends FlatField:
	func normal_at(_x: float, _z: float) -> Vector3: return Vector3(0.8, 0.6, 0.0)
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var profile := WorldProfile.new()
	profile.generation_version = 10
	var field := FlatField.new(42, profile)
	check(SlenderSpeakerSpawns.plan(field, 0).is_empty(), "First 1500m cannot plan a giant")
	var successes := 0
	for segment in range(1, 1001):
		var plan := SlenderSpeakerSpawns.plan(field, segment)
		check(plan == SlenderSpeakerSpawns.plan(field, segment), "Planning is deterministic")
		# Perturb unrelated generation streams. It must never move the giant.
		field.rng_for(segment, "road_spawns").randf()
		field.rng_for(segment, "dense_forest").randf()
		check(plan == SlenderSpeakerSpawns.plan(field, segment), "Independent RNG cannot consume encounter RNG")
		if plan.candidates.is_empty(): continue
		successes += 1
		for point: Vector3 in plan.candidates:
			check(-point.z >= segment * 1500 and -point.z < (segment + 1) * 1500, "Candidate stays in its segment")
			check(floori(-point.z / 150.0) == plan.band, "Retries stay in the originally chosen band")
			check(absf(point.x) - 7.5 >= 40 and absf(point.x) - 7.5 <= 100, "Forest placement is 40–100m off road edge")
	check(successes >= 200 and successes <= 300, "Independent 25% chance over 1000 segments")
	for version in range(2, 10):
		profile.generation_version = version
		check(SlenderSpeakerSpawns.plan(field, 1).is_empty(), "Old generation versions never receive giant plans")
	profile.generation_version = 10
	check(SlenderSpeakerSpawns.valid_ledger([1, 5, 999]), "Checkpoint segment ledger accepts visited segments")
	for invalid in [null, {}, [0], [1, 1], [1.0], [-1]]:
		check(not SlenderSpeakerSpawns.valid_ledger(invalid), "Checkpoint segment ledger rejects invalid/duplicate entries")
	var point := Vector3(60, 0, -1600)
	check(SlenderSpeakerSpawns.static_valid(field, point), "Open traversable forest position passes static filters")
	check(not SlenderSpeakerSpawns.static_valid(BlockedPoiField.new(42, profile), point), "POI occupied bounds exclude candidate even away from parking court")
	check(not SlenderSpeakerSpawns.static_valid(SteepField.new(42, profile), point), "Non-traversable steep ground excludes candidate")
	var trees: Array[Dictionary] = [{"point": point + Vector3(8, 0, 0)}, {"point": point + Vector3(0, 0, 8)}, {"point": point + Vector3(0, 0, -8)}]
	field.forest_cache[10] = trees
	check(SlenderSpeakerSpawns.forest_valid(field, point), "Candidate must be inside actual forest")
	field.forest_cache[10].append({"point": point + Vector3(0.5, 0, 0)})
	check(not SlenderSpeakerSpawns.forest_valid(field, point), "Candidate cannot overlap a trunk")
	if failures.is_empty(): print("PASS: Slender Speaker v10 independent segment rolls, exclusion, forest geometry and strict checkpoint ledger (successes=%d)" % successes)
	quit(0 if failures.is_empty() else 1)
