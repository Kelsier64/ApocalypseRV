extends SceneTree
## Pure observations exercise the encounter owner without loading the giant/RV.
const Encounter = preload("res://enemies/slender_speaker/slender_speaker_encounter.gd")
const Settings = preload("res://enemies/slender_speaker/slender_speaker_settings.gd")
class Survivor extends Node3D:
	var is_player_dead := false
var failures: Array[String] = []
var _nodes: Array[Node3D] = []
var settings := Settings.new()

func _init() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func actor(survivor := false) -> Node3D:
	var node: Node3D = Survivor.new() if survivor else Node3D.new()
	_nodes.append(node)
	return node

func sight(player: Node3D, vehicle: Node3D, speed_kmh := 0.0, visible := true, point := Vector3(2, 1, 3), frame := Transform3D.IDENTITY) -> Dictionary:
	return {"player": player, "vehicle": vehicle, "player_point": point,
		"vehicle_point": frame.origin, "vehicle_frame": frame,
		"road_speed": speed_kmh / 3.6, "vehicle_visible": visible and vehicle != null}

func run() -> void:
	_test_hysteresis()
	_test_same_vehicle_survivor_acquisition()
	_test_hidden_driver_pursuit()
	_test_identity_and_expiry()
	_test_independent_vehicle_sighting()
	_test_visible_roof_inspection()
	_test_expired_survivor_roof_fallback()
	_test_roof_fallback_visibility_gates()
	_test_roof_damage_progress()
	_test_observed_memory_and_disembark()
	_test_observed_search_lead()
	_test_single_sight_motion_lead()
	_test_locks()
	_test_suppression()
	_test_invalid_targets()
	for node in _nodes:
		if is_instance_valid(node): node.free()
	if failures.is_empty():
		print("PASS: Slender Speaker persistent encounter, hysteresis, observed memory, action locks, unknown roof fallback and expiry suppression")
	quit(0 if failures.is_empty() else 1)

func _test_hysteresis() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	check(is_equal_approx(settings.cabin_enter_speed * 3.6, 6.0) and is_equal_approx(settings.pursuit_enter_speed * 3.6, 10.0), "Default hysteresis boundaries are 6/10 km/h")
	var d := owner.update(sight(player, vehicle, 12), 0, settings)
	check(d.mode == "pursuit" and d.intent == "vehicle_assault", "Initial fast RV enters pursuit")
	var generation: int = d.generation
	d = owner.update(sight(player, vehicle, 6), 1, settings)
	check(d.mode == "pursuit", "Exactly 6 km/h retains pursuit without accumulating lower dwell")
	d = owner.update(sight(player, vehicle, 5.9), .49, settings)
	check(d.mode == "pursuit", "Below 6 km/h must sustain 0.5 seconds before cabin")
	d = owner.update(sight(player, vehicle, 6), .02, settings)
	check(d.mode == "pursuit", "Exactly 6 km/h resets a partial lower dwell")
	d = owner.update(sight(player, vehicle, 5.9), .49, settings)
	check(d.mode == "pursuit", "Interrupted lower dwell must restart its full delay")
	d = owner.update(sight(player, vehicle, 5.9), .02, settings)
	check(d.mode == "cabin" and d.generation > generation, "Sustained speed below 6 km/h enters cabin and changes generation")
	generation = d.generation
	d = owner.update(sight(player, vehicle, 8), 1, settings)
	check(d.mode == "cabin" and d.generation == generation, "Hysteresis band retains cabin without generation churn")
	d = owner.update(sight(player, vehicle, 11), .74, settings)
	check(d.mode == "cabin", "Fast burst shorter than .75 seconds retains cabin")
	d = owner.update(sight(player, vehicle, 10), 1, settings)
	check(d.mode == "cabin", "Exactly 10 km/h resets upper dwell and remains cabin")
	d = owner.update(sight(player, vehicle, 11), .76, settings)
	check(d.mode == "pursuit", "Sustained speed above 10 km/h resumes pursuit")
	d = owner.update(sight(player, vehicle, 8), 1, settings)
	check(d.mode == "pursuit", "Hysteresis band also retains pursuit")
	owner.reset()
	check(owner.decision.mode == "none" and owner.decision.generation == 0, "Reset clears encounter and generation")
	check(owner.update(sight(null, vehicle, 10), 0, settings).mode == "cabin", "Initial unknown RV at 10 km/h allows cabin inspection")

func _test_same_vehicle_survivor_acquisition() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	owner.update(sight(null, vehicle, 12), 0, settings)
	owner.update(sight(null, vehicle, 8), 1, settings)
	var d := owner.update(sight(player, vehicle, 8), 0, settings)
	check(d.mode == "pursuit" and d.player == player, "Revealing the same RV's driver within the hysteresis band cannot force pursuit into cabin")
	d = owner.update(sight(player, vehicle, 5.9), .49, settings)
	check(d.mode == "pursuit", "Same-RV survivor acquisition still requires full lower dwell")
	d = owner.update(sight(player, vehicle, 5.9), .02, settings)
	check(d.mode == "cabin", "Normal lower dwell still switches revealed survivor's RV to cabin")
	owner.reset()
	owner.update(sight(null, vehicle, 8), 0, settings)
	owner.update(sight(null, vehicle, 12), .4, settings)
	d = owner.update(sight(player, vehicle, 12), .34, settings)
	check(d.mode == "cabin", "Revealing driver during a fast burst cannot bypass upper dwell")
	d = owner.update(sight(player, vehicle, 12), .02, settings)
	check(d.mode == "pursuit", "Driver revelation preserves accumulated upper dwell instead of restarting it")

func _test_identity_and_expiry() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var other_player := actor(true)
	var vehicle := actor()
	var other_vehicle := actor()
	owner.update(sight(player, vehicle), 0, settings)
	var d := owner.update(sight(null, vehicle), 4, settings)
	check(d.player == player and d.vehicle == vehicle and d.intent == "search", "RV visibility preserves hidden survivor identity but cannot authorize cabin attack")
	d = owner.update(sight(other_player, other_vehicle), 3.9, settings)
	check(d.player == player and d.vehicle == vehicle and not d.player_visible and not d.vehicle_visible, "Another visible survivor/RV cannot replace retained encounter")
	d = owner.update(sight(null, vehicle), .11, settings)
	check(d.mode == "cabin" and d.player == null and d.vehicle == vehicle and d.intent == "cabin", "Matching visible RV starts unknown inspection when the known survivor's deadline expires")
	owner.reset()
	owner.update(sight(player, null), 0, settings)
	d = owner.update(sight(null, other_vehicle, 30), 4, settings)
	check(d.mode == "ground" and d.player == player and d.vehicle == null and d.intent == "search", "Ground survivor cannot fall back to unrelated RV")
	d = owner.update(sight(player, null), 3.9, settings)
	d = owner.update({}, 7.9, settings)
	check(d.player == player, "Seeing retained survivor refreshes the full search deadline")
	owner.reset()
	d = owner.update(sight(null, vehicle), 0, settings)
	check(d.intent == "cabin" and d.player == null, "Initial unknown-occupant RV receives roof inspection")
	d = owner.update(sight(null, vehicle), 7.9, settings)
	check(d.mode == "cabin", "Unknown RV inspection retains nearly eight seconds")
	d = owner.update(sight(null, vehicle), .11, settings)
	check(d.mode == "none", "Unknown RV inspection also expires despite continuous RV sight")

func _test_hidden_driver_pursuit() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	owner.update(sight(player, vehicle), 0, settings)
	var d := owner.update(sight(null, vehicle, 12), .74, settings)
	check(d.mode == "cabin" and d.intent == "search", "Hidden driver cannot authorize vehicle assault before upper dwell completes")
	d = owner.update(sight(null, vehicle, 12), .02, settings)
	check(d.mode == "pursuit" and d.intent == "vehicle_assault" and d.player == player, "Sustained fast visible RV resumes vehicle assault with hidden retained driver")
	d = owner.update(sight(null, vehicle, 12), 20, settings)
	check(d.mode == "pursuit" and d.intent == "vehicle_assault", "Visible escaping RV sustains pursuit beyond survivor's eight-second search window")
	d = owner.update({}, 7.9, settings)
	check(d.mode == "pursuit" and d.intent == "search", "Hidden RV pursuit searches from the last visible RV observation")
	d = owner.update(sight(null, vehicle, 3), .6, settings)
	check(d.mode == "cabin" and d.intent == "search", "Sustained slowdown enters cabin search with hidden driver")
	d = owner.update(sight(null, vehicle), 7.9, settings)
	check(d.mode == "cabin", "Pursuit-to-cabin transition gives hidden survivor a fresh eight-second search window")
	d = owner.update(sight(null, vehicle), .11, settings)
	check(d.mode == "cabin" and d.player == null and d.vehicle == vehicle and d.intent == "cabin", "Expired cabin memory becomes unknown inspection of the same slow visible RV")
	owner.reset()
	owner.update(sight(player, vehicle, 12), 0, settings)
	d = owner.update({}, 8.1, settings)
	check(d.mode == "none", "Pursuit expires eight seconds after RV itself disappears")

func _test_independent_vehicle_sighting() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var bystander := actor(true)
	var vehicle := actor()
	owner.update(sight(player, vehicle, 12), 0, settings)
	var observation := sight(bystander, vehicle, 12)
	observation.player_vehicle = null
	var d := owner.update(observation, 1, settings)
	check(d.player == player and d.vehicle == vehicle and not d.player_visible and d.vehicle_visible and d.intent == "vehicle_assault", "Unrelated visible ground survivor cannot hide independent sight of the retained escaping RV")
	observation.player = player
	d = owner.update(observation, 0, settings)
	check(d.player == player and d.vehicle == null and d.mode == "ground", "Explicit visible survivor association stays null despite independent sight of its old RV")
	var hidden_vehicle := actor()
	observation.player_vehicle = hidden_vehicle
	d = owner.update(observation, 0, settings)
	check(d.vehicle == hidden_vehicle and d.mode == "cabin" and not d.vehicle_visible, "A newly associated hidden RV cannot inherit another visible RV's pursuit speed")

func _test_visible_roof_inspection() -> void:
	var owner := Encounter.new()
	var vehicle := actor()
	var player := actor(true)
	var observation := sight(null, vehicle)
	observation.roof_visible = true
	owner.update(observation, 0, settings)
	var d := owner.update(observation, 20, settings)
	check(d.mode == "cabin" and d.intent == "cabin" and d.player == null and d.roof_inspection, "Visible physical roof sustains initial unknown-occupant inspection beyond approach time")
	observation.roof_visible = false
	d = owner.update(observation, 7.9, settings)
	check(d.mode == "cabin", "Unknown inspection retains eight seconds after its last visible roof disappears")
	d = owner.update(observation, .11, settings)
	check(d.mode == "none", "Roofless unknown RV expires instead of authorizing chassis fallback")
	owner.reset()
	owner.update(sight(player, vehicle), 0, settings)
	observation.roof_visible = true
	d = owner.update(observation, .1, settings)
	check(d.intent == "search" and d.roof_inspection, "Owner permits visible physical roof inspection during known-survivor search without changing its intent")
	d = owner.update(observation, 8.1, settings)
	check(d.mode == "cabin" and d.player == null and d.vehicle == vehicle and d.roof_inspection and d.intent == "cabin", "Visible roof preserves the RV inspection after known-survivor memory expires")
	owner.reset()
	owner.update(sight(null, vehicle), 0, settings)
	observation.vehicle_visible = false
	d = owner.update(observation, 8.1, settings)
	check(d.mode == "none", "Roof flag without matching visible RV cannot refresh unknown inspection")

func _test_expired_survivor_roof_fallback() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	var seen_frame := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var seen := sight(player, vehicle, 0, true, seen_frame * Vector3(2, 1, 3), seen_frame)
	seen.sample_time = 10.0
	seen.player_motion_local = Vector3(0, 0, 5)
	var d := owner.update(seen, 0, settings)
	var generation: int = d.generation
	var inspect_frame := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(20, 0, 0))
	var hidden := sight(null, vehicle, 0, true, Vector3(900, 900, 900), inspect_frame)
	hidden.roof_visible = true
	hidden.player_motion_local = Vector3(800, 800, 800)
	hidden.sample_time = 900.0
	d = owner.update(hidden, 7.9, settings)
	check(d.player == player and d.intent == "search" and d.roof_inspection, "Visible roof inspection retains known identity until its eight-second deadline")
	d = owner.update(hidden, .11, settings)
	check(d.mode == "cabin" and d.intent == "cabin" and d.player == null and d.vehicle == vehicle and not d.player_visible and d.roof_inspection, "Expired hidden cabin survivor falls back to unknown inspection of the same observed RV")
	check(d.generation > generation and is_equal_approx(owner._remaining, settings.search_seconds), "Forgetting survivor identity changes encounter generation and starts a full fresh inspection window")
	check(d.vehicle_frame == inspect_frame and d.point.is_equal_approx(hidden.vehicle_point) and d.search_point.is_equal_approx(d.point), "Unknown inspection uses current visible RV evidence and discards the survivor's old point and motion lead")
	check(owner._player_id == 0 and not owner._has_local and owner._player_local == Vector3.ZERO and owner._search_offset_local == Vector3.ZERO and owner._motion_sample_time < 0.0, "Fallback clears survivor ID, RV-local memory and observed locomotion samples")
	d = owner.update(hidden, 20, settings)
	check(d.mode == "cabin" and d.player == null and d.roof_inspection and d.intent == "cabin", "Actual roof visibility sustains fallback unknown inspection beyond eight seconds")
	var moved_frame := Transform3D(Basis.IDENTITY, Vector3(40, 0, 0))
	hidden.vehicle_frame = moved_frame
	hidden.vehicle_point = moved_frame.origin
	d = owner.update(hidden, 0, settings)
	check(d.point.is_equal_approx(moved_frame.origin) and d.search_point.is_equal_approx(d.point), "Moving visible RV after fallback cannot resurrect forgotten local survivor memory")
	var reacquired := sight(player, vehicle, 0, true, moved_frame * Vector3(-1, 1, -.5), moved_frame)
	reacquired.sample_time = 900.2
	d = owner.update(reacquired, 0, settings)
	check(d.player == player and d.player_visible and d.intent == "cabin" and d.point.is_equal_approx(reacquired.player_point), "Actual survivor sight reacquires cabin identity after unknown inspection")
	d = owner.update(hidden, 0, settings)
	check(d.player == player and not d.player_visible and d.intent == "search" and d.search_point.is_equal_approx(reacquired.player_point), "First reacquisition sample cannot inherit the forgotten survivor's walking lead")

func _test_roof_fallback_visibility_gates() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	var other_vehicle := actor()
	owner.update(sight(player, vehicle), 0, settings)
	var hidden := sight(null, vehicle)
	# A missing roof does not gate the transition. It does prevent extending
	# the new unknown inspection indefinitely, so expiry still suppresses it.
	var d := owner.update(hidden, 8.1, settings)
	check(d.mode == "cabin" and d.player == null and d.vehicle == vehicle and d.intent == "cabin" and not d.roof_inspection, "Matching visible RV starts a fresh unknown window even without visible roof")
	d = owner.update(hidden, 7.9, settings)
	check(d.mode == "cabin" and d.player == null, "Roofless fallback retains nearly its full fresh eight-second window")
	d = owner.update(hidden, .11, settings)
	check(d.mode == "none" and d.vehicle == null, "Roofless unknown fallback expires without a chassis or hidden-grab intent")
	hidden.roof_visible = true
	d = owner.update(hidden, 20, settings)
	check(d.mode == "none" and not d.roof_inspection, "Expired fallback suppresses the stationary RV even if its roof later becomes visible")
	d = owner.update(sight(player, vehicle), 0, settings)
	check(d.mode == "cabin" and d.player == player and d.player_visible, "Real survivor sight clears suppression after fallback inspection expires")
	owner.reset()
	owner.update(sight(player, vehicle), 0, settings)
	var hidden_rv := sight(null, vehicle, 0, false)
	hidden_rv.roof_visible = true
	d = owner.update(hidden_rv, 8.1, settings)
	check(d.mode == "none" and d.vehicle == null, "Hidden retained RV cannot authorize fallback despite a roof flag")
	owner.reset()
	owner.update(sight(player, vehicle), 0, settings)
	var unrelated := sight(null, other_vehicle)
	unrelated.roof_visible = true
	d = owner.update(unrelated, 8.1, settings)
	check(d.mode == "none" and d.vehicle == null, "A different visible RV cannot authorize fallback or replace the expired encounter in the same update")
	owner.reset()
	owner.update(sight(player, null), 0, settings)
	hidden.roof_visible = true
	d = owner.update(hidden, 8.1, settings)
	check(d.mode == "none" and d.vehicle == null and d.player == null, "Visible old RV and roof cannot convert an expired ground search into unknown cabin inspection")

func _test_roof_damage_progress() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	var other_vehicle := actor()
	var seen := sight(player, vehicle)
	var hidden := sight(null, vehicle)
	hidden.roof_visible = true
	owner.update(seen, 0, settings)
	# Buffer a sight during windup, then lose it before the actual impact.
	owner.update(seen, .1, settings, true)
	owner.update(hidden, 5, settings, true)
	owner.record_roof_damage(vehicle, settings)
	var d := owner.update(hidden, 3, settings)
	check(d.player == player and d.vehicle == vehicle and d.intent == "search" and not d.player_visible, "Real roof damage retains a hidden cabin identity through recovery without granting survivor sight")
	check(is_equal_approx(owner._remaining, 5.0), "Older buffered sight cannot shorten a later same-RV roof-progress deadline")
	check(d.point.is_equal_approx(seen.player_point), "Roof progress cannot replace the last observed survivor point")
	owner.record_roof_damage(other_vehicle, settings)
	d = owner.update(hidden, 5.1, settings)
	check(d.mode == "cabin" and d.player == null and d.vehicle == vehicle and d.roof_inspection, "Wrong-RV progress cannot retain survivor identity after its deadline; the visible roof receives unknown inspection")
	hidden.roof_visible = false
	d = owner.update(hidden, 8.1, settings)
	check(d.mode == "none", "Unknown inspection without a visible roof expires after its own full window")
	owner.record_roof_damage(vehicle, settings)
	check(owner.update(hidden, 0, settings).mode == "none", "Roof progress cannot revive an expired suppressed encounter")
	# A buffered disembark keeps its own observation age; roof progress must
	# not donate a newer deadline to a different ground/RV identity.
	owner.reset()
	owner.update(seen, 0, settings)
	owner.update(sight(player, null), .1, settings, true)
	owner.update(hidden, 5, settings, true)
	owner.record_roof_damage(vehicle, settings)
	d = owner.update({}, 2, settings)
	check(d.mode == "ground" and d.vehicle == null and is_equal_approx(owner._remaining, 1.0), "Buffered visible disembark does not inherit roof-progress time")
	owner.record_roof_damage(vehicle, settings)
	check(owner.update({}, 1.1, settings).mode == "none", "Old-RV roof progress cannot extend a ground-survivor search")

func _test_observed_memory_and_disembark() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	var first := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var local_point := Vector3(2, 1, 3)
	owner.update(sight(player, vehicle, 0, true, first * local_point, first), 0, settings)
	var second := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(20, 0, 0))
	var d := owner.update(sight(null, vehicle, 0, true, Vector3.ZERO, second), 1, settings)
	check(d.point.is_equal_approx(second * local_point) and d.vehicle_frame == second, "Hidden survivor's observed local point follows only supplied visible RV frame")
	player.position = Vector3(900, 900, 900)
	vehicle.position = Vector3(800, 800, 800)
	var hidden := Transform3D(Basis.IDENTITY, Vector3(700, 0, 0))
	d = owner.update(sight(null, vehicle, 0, false, Vector3.ZERO, hidden), 1, settings)
	check(d.point.is_equal_approx(second * local_point) and d.vehicle_frame == second, "Hidden RV frame and actual node transforms cannot move memory")
	var ground_point := Vector3(5, 0, 5)
	d = owner.update(sight(player, null, 0, false, ground_point), 0, settings)
	check(d.mode == "ground" and d.vehicle == null and d.point == ground_point and d.intent == "ground", "Visible disembark removes vehicle association immediately")
	d = owner.update(sight(null, vehicle, 40), 1, settings)
	check(d.mode == "ground" and d.vehicle == null and d.point == ground_point, "Visible old RV cannot alter disembarked survivor memory")

func _test_observed_search_lead() -> void:
	var player := actor(true)
	var vehicle := actor()
	var owner := Encounter.new()
	var frame := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var initial := Vector3(0, 1, 0)
	var last := Vector3(0, 1, 1.6)
	var first := sight(player, vehicle, 0, true, frame * initial, frame)
	first.sample_time = 10.0
	owner.update(first, 0, settings)
	var second := sight(player, vehicle, 0, true, frame * last, frame)
	second.sample_time = 10.2
	var d := owner.update(second, .2, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(d.point), "Visible survivor uses its actual observed point without a search lead")
	# Reusing one sensory cache must retain the last real velocity sample rather
	# than treating repeated owner ticks as fresh motion or stationary evidence.
	for tick in 12: owner.update(second, 1.0 / 60.0, settings)
	var hidden := sight(null, vehicle, 0, true, Vector3(900, 900, 900), frame)
	hidden.sample_time = 1000.0
	hidden.roof_visible = true
	d = owner.update(hidden, .1, settings)
	var led := frame * Vector3(0, 1, 4.6)
	check(d.point.is_equal_approx(frame * last), "Hidden motion prediction preserves the actual last sight-confirmed point")
	check(d.get("search_point", Vector3.INF).is_equal_approx(led), "Search uses a half-second observed local motion lead capped to three metres")
	check(not d.player_visible and d.intent == "search" and d.roof_inspection, "Predicted roof search never invents survivor visibility or a grab intent")
	player.position = Vector3(-800, -800, -800)
	d = owner.update(hidden, 1, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(led), "Hidden fake point, timestamp and live player transform cannot alter the observed search lead")
	var turned := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(20, 0, 0))
	hidden.vehicle_frame = turned
	d = owner.update(hidden, 0, settings)
	check(d.point.is_equal_approx(turned * last) and d.get("search_point", Vector3.INF).is_equal_approx(turned * Vector3(0, 1, 4.6)), "Only a visible RV frame transports both actual local memory and bounded local search lead")
	# All hidden ticks still spend the same eight-second deadline; seeing roofs
	# does not refresh or lengthen the remembered survivor's search window.
	d = owner.update(hidden, 6.89, settings)
	check(d.mode == "cabin", "Bounded prediction retains the original encounter just before eight-second expiry")
	d = owner.update(hidden, .02, settings)
	check(d.mode == "cabin" and d.player == null and d.roof_inspection and d.point.is_equal_approx(hidden.vehicle_point) and d.search_point.is_equal_approx(d.point), "Expired bounded prediction is forgotten when visible RV inspection starts")
	# A slower measurement exercises the time horizon without reaching its cap.
	owner.reset()
	first.sample_time = 20.0
	owner.update(first, 0, settings)
	second.player_point = frame * Vector3(0, 1, .2)
	second.sample_time = 20.2
	owner.update(second, .2, settings)
	hidden.vehicle_frame = frame
	d = owner.update(hidden, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(frame * Vector3(0, 1, .7)), "Observed one-metre-per-second motion leads only half a metre")
	second.sample_time = 20.4
	d = owner.update(second, .2, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(d.point), "Fresh visible standing observation immediately uses the actual point")
	d = owner.update(hidden, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(d.point), "Fresh stationary sight clears the previous motion lead")
	second.sample_time = 21.0
	second.player_point = frame * Vector3(0, 1, 2)
	owner.update(second, .6, settings)
	d = owner.update(hidden, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(d.point), "Sight samples more than three tenths of a second apart cannot invent motion across an occlusion gap")
	# Visible chassis displacement alone cannot be mistaken for cabin walking.
	owner.reset()
	first.sample_time = 30.0
	owner.update(first, 0, settings)
	second.sample_time = 30.2
	second.vehicle_frame = turned
	second.player_point = turned * initial
	owner.update(second, .2, settings)
	hidden.vehicle_frame = turned
	d = owner.update(hidden, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(d.point), "Only survivor motion relative to the observed RV creates cabin search lead")

func _test_single_sight_motion_lead() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	var actual := Vector3(0, 1, -.3)
	var seen := sight(player, vehicle, 0, true, actual)
	seen.sample_time = 10.0
	seen.player_motion_local = Vector3(0, 0, 5)
	var d := owner.update(seen, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(actual), "One visible moving sample still aims at the actual visible survivor")
	var hidden := sight(null, vehicle)
	hidden.player_motion_local = Vector3(900, 900, 900)
	hidden.player_point = Vector3(800, 800, 800)
	hidden.sample_time = 900.0
	d = owner.update(hidden, .1, settings)
	var expected := actual + Vector3(0, 0, 2.5)
	check(d.get("search_point", Vector3.INF).is_equal_approx(expected) and d.point.is_equal_approx(actual), "A single sight-confirmed walking vector supplies a bounded roof-search lead without changing memory")
	d = owner.update(hidden, 1, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(expected), "Forged hidden motion, point and timestamp cannot replace sight-confirmed locomotion")
	seen.sample_time = 10.2
	seen.player_motion_local = Vector3.ZERO
	owner.update(seen, .1, settings)
	d = owner.update(hidden, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(actual), "Fresh directly observed standing vector clears a previous one-sample walking lead")
	owner.reset()
	seen.player_motion_local = Vector3(0, 20, 20)
	owner.update(seen, 0, settings)
	d = owner.update(hidden, 0, settings)
	check(d.get("search_point", Vector3.INF).is_equal_approx(actual + Vector3(0, 0, 3)), "Directly observed motion is horizontal and capped to three metres")
	d = owner.update(hidden, 8.1, settings)
	check(d.mode == "cabin" and d.player == null and d.intent == "cabin" and d.search_point.is_equal_approx(hidden.vehicle_point), "One-sample locomotion expires and cannot carry into unknown RV inspection")

func _test_locks() -> void:
	var owner := Encounter.new()
	var player := actor(true)
	var vehicle := actor()
	var d := owner.update(sight(player, vehicle, 20), 0, settings)
	var generation: int = d.generation
	d = owner.update(sight(player, vehicle, 3), .6, settings, true)
	check(d.mode == "pursuit" and d.generation == generation, "Locked action freezes mode while accumulating low-speed dwell")
	d = owner.update(sight(player, vehicle, 3), 0, settings)
	check(d.mode == "cabin", "Completed dwell applies immediately after action unlock")
	generation = d.generation
	var ground_point := Vector3(7, 0, 7)
	d = owner.update(sight(player, null, 0, false, ground_point), .1, settings, true)
	check(d.mode == "cabin" and d.vehicle == vehicle and d.generation == generation, "Visible disembark is buffered while action is locked")
	d = owner.update(sight(null, vehicle), .1, settings)
	check(d.mode == "ground" and d.vehicle == null and d.point == ground_point and not d.player_visible, "Buffered disembark applies on unlock despite hidden survivor and visible old RV")
	owner.reset()
	d = owner.update(sight(player, vehicle), 0, settings)
	generation = d.generation
	d = owner.update(sight(null, vehicle), 8.1, settings, true)
	check(d.player == player and d.vehicle == vehicle and d.mode == "cabin" and d.generation == generation and owner._has_local, "Expiry cannot forget a locked action's survivor identity or local memory")
	d = owner.update(sight(null, vehicle), 0, settings)
	check(d.mode == "cabin" and d.player == null and d.vehicle == vehicle and d.intent == "cabin", "Deferred expiry starts unknown inspection of matching visible RV only after unlock")
	check(d.generation > generation and is_equal_approx(owner._remaining, settings.search_seconds), "Unlocked fallback gets a full inspection window despite the expired locked search")
	owner.reset()
	owner.update(sight(player, vehicle), 0, settings)
	owner.update(sight(player, null), 0, settings, true)
	owner.update(sight(null, vehicle), 8.1, settings, true)
	d = owner.update(sight(null, vehicle), 0, settings)
	check(d.mode == "none" and d.player == null and d.vehicle == null, "Expired buffered disembark cannot restart ground memory or fall back to the visible old RV on unlock")

func _test_suppression() -> void:
	var owner := Encounter.new()
	var vehicle := actor()
	var player := actor(true)
	owner.update(sight(null, vehicle), 0, settings)
	owner.update(sight(null, vehicle), 8.1, settings)
	var d := owner.update(sight(null, vehicle), 20, settings)
	check(d.mode == "none", "Expired slow RV stays suppressed across repeated visible observations")
	d = owner.update(sight(null, vehicle, 12), .74, settings)
	check(d.mode == "none", "Suppressed RV cannot reacquire from a brief fast burst")
	d = owner.update(sight(null, vehicle, 10), .1, settings)
	d = owner.update(sight(null, vehicle, 12), .76, settings)
	check(d.mode == "pursuit" and d.vehicle == vehicle, "Sustained fast RV clears suppression and reacquires")
	owner.reset()
	owner.update(sight(null, vehicle), 0, settings)
	owner.update(sight(null, vehicle), 8.1, settings)
	d = owner.update(sight(player, vehicle), 0, settings)
	check(d.player == player and d.mode == "cabin", "Visible survivor immediately clears slow-RV suppression")

func _test_invalid_targets() -> void:
	var owner := Encounter.new()
	var player := actor(true) as Survivor
	owner.update(sight(player, null), 0, settings)
	player.is_player_dead = true
	check(owner.update({}, 0, settings, true).mode == "none", "Dead survivor cleanup overrides action lock safely")
	var vehicle := actor()
	owner.update(sight(null, vehicle), 0, settings)
	vehicle.free()
	check(owner.update({}, 0, settings).mode == "none", "Freed vehicle is cleaned up without transform/seat reads")
