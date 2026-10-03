extends SceneTree
## Evaluate imported skin over complete crawl cycles, then exercise floor movement.
const PLAYER := preload("res://player/player.tscn")
const CASES := {
	"prone_idle": ["left_leg"],
	"crawl_missing_left_leg": ["left_leg"],
	"crawl_missing_right_leg": ["right_leg"],
	"crawl_no_legs": ["left_leg", "right_leg"],
	"crawl_onearm_L": ["left_leg", "right_leg", "right_arm"],
	"crawl_onearm_R": ["left_leg", "right_leg", "left_arm"],
}
var failures: Array[String] = []
var arena: Node3D
var actor: CharacterBody3D
var visual: PlayerModelVisual
var driver: Node
var skeleton: Skeleton3D

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok and detail not in failures:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func set_injury(missing: Array) -> void:
	var body := PlayerBodyState.new()
	for part in missing: body.sever(StringName(part))
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, .05, 0)), "body": body.capture()})
	actor.velocity = Vector3.ZERO

func joint(name: String) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin

func audit_cycles() -> void:
	actor.set_physics_process(false)
	driver.set_physics_process(false)
	visual.get_node("Carry").set_physics_process(false)
	# Cache imported arrays, but evaluate actual skinning against every sampled pose.
	var surfaces: Array[Dictionary] = []
	var skin: Skin
	for template: Dictionary in visual.dismemberment.templates:
		if template.role != "Part": continue
		skin = template.skin
		for surface in template.mesh.get_surface_count():
			var data: Array = template.mesh.surface_get_arrays(surface)
			surfaces.append({"part": template.part, "vertices": data[Mesh.ARRAY_VERTEX],
				"bones": data[Mesh.ARRAY_BONES], "weights": data[Mesh.ARRAY_WEIGHTS]})
	var bone_indices: Array[int] = []
	for bind in skin.get_bind_count(): bone_indices.append(skeleton.find_bone(skin.get_bind_name(bind)))
	var segments: Array[Dictionary] = []
	for side in ["L", "R"]:
		for pair in [["upper_arm_", "forearm_"], ["forearm_", "hand_"], ["thigh_", "shin_"], ["shin_", "foot_"]]:
			var a: String = pair[0] + side
			var b: String = pair[1] + side
			var length := skeleton.get_bone_global_rest(skeleton.find_bone(a)).origin.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone(b)).origin)
			segments.append({"a": a, "b": b, "length": length})
	var reports: Array[Dictionary] = []
	for clip: String in CASES:
		set_injury(CASES[clip])
		var name := "injury/" + clip
		check(driver.animation.has_animation(name), "Required imported prone clip exists: " + clip)
		if not driver.animation.has_animation(name): continue
		var animation: Animation = driver.animation.get_animation(name)
		var count := ceili(animation.length * 60.0)
		var torso_low := INF
		var torso_highest_bottom := -INF
		var body_low := INF
		var body_high := -INF
		var segment_error := 0.0
		var support_samples := 0
		var pelvis_low := INF
		var pelvis_high := -INF
		var spine_low := INF
		var spine_high := -INF
		var part_bounds := {}
		for frame in range(count + 1):
			driver.animation.play(name, 0)
			driver.animation.seek(animation.length * float(frame) / count, true)
			skeleton.force_update_all_bone_transforms()
			var binds: Array[Transform3D] = []
			for bind in skin.get_bind_count(): binds.append(skeleton.get_bone_global_pose(bone_indices[bind]) * skin.get_bind_pose(bind))
			var frame_torso_low := INF
			for surface: Dictionary in surfaces:
				if surface.part in CASES[clip]: continue
				for index in surface.vertices.size():
					var point := Vector3.ZERO
					for influence in 4:
						var at: int = index * 4 + influence
						point += (binds[surface.bones[at]] * surface.vertices[index]) * surface.weights[at]
					body_low = minf(body_low, point.y)
					body_high = maxf(body_high, point.y)
					if not part_bounds.has(surface.part): part_bounds[surface.part] = {"min": INF, "max": -INF}
					part_bounds[surface.part].min = minf(part_bounds[surface.part].min, point.y)
					part_bounds[surface.part].max = maxf(part_bounds[surface.part].max, point.y)
					if surface.part == "torso": frame_torso_low = minf(frame_torso_low, point.y)
			torso_low = minf(torso_low, frame_torso_low)
			torso_highest_bottom = maxf(torso_highest_bottom, frame_torso_low)
			for segment: Dictionary in segments:
				segment_error = maxf(segment_error, absf(joint(segment.a).distance_to(joint(segment.b)) - segment.length))
			for bone in ["pelvis", "spine_02"]:
				check(joint(bone).y >= .10 and joint(bone).y <= .22, "Torso remains prone throughout cycle: " + clip + "/" + bone)
			pelvis_low = minf(pelvis_low, joint("pelvis").y)
			pelvis_high = maxf(pelvis_high, joint("pelvis").y)
			spine_low = minf(spine_low, joint("spine_02").y)
			spine_high = maxf(spine_high, joint("spine_02").y)
			for side in ["L", "R"]:
				var part := "left_arm" if side == "L" else "right_arm"
				if part in CASES[clip]: continue
				var wrist := joint("hand_" + side)
				if wrist.y < .065:
					support_samples += 1
					check(joint("forearm_" + side).y < .105, "Planted wrist uses low forearm support: " + clip)
		check(torso_low >= -.003 and torso_highest_bottom <= .055, "Torso clothing stays close to floor without penetration: " + clip)
		check(body_low >= -.003 and body_high <= .42, "Remaining body retains a flat, nonpenetrating silhouette: " + clip)
		check(segment_error < .001, "Crawl preserves arm and leg segment lengths: " + clip)
		check(support_samples > count / 2, "Crawl retains forearm support across the cycle: " + clip)
		for piece: Dictionary in visual.dismemberment.pieces:
			if piece.role == "Part": check(piece.full.visible == (piece.part not in CASES[clip]), "Missing limbs stay hidden: " + clip + "/" + piece.part)
		reports.append({"clip": clip, "samples": count + 1, "torso_min": torso_low,
			"torso_max_bottom": torso_highest_bottom, "body_min": body_low, "body_max": body_high,
			"pelvis_min": pelvis_low, "pelvis_max": pelvis_high, "spine_min": spine_low,
			"spine_max": spine_high, "segment_error": segment_error, "parts": part_bounds})
	print("PRONE_SKIN_AUDIT ", JSON.stringify(reports))

func audit_movement() -> void:
	actor.set_physics_process(true)
	driver.set_physics_process(true)
	visual.get_node("Carry").set_physics_process(true)
	for clip: String in CASES:
		set_injury(CASES[clip])
		Input.action_release("move_forward")
		await steps(75)
		check(actor.is_on_floor(), "Prone actor settles on actual floor: " + clip)
		check(actor.camera.global_position.y >= .25 and actor.camera.global_position.y <= .40, "Settled prone eye remains near ground: " + clip)
		var start := actor.global_position
		var eye_low := INF
		var eye_high := -INF
		if clip != "prone_idle": Input.action_press("move_forward")
		await steps(20)
		for frame in 90:
			await steps(1)
			check(actor.is_on_floor() and absf(actor.global_position.y - start.y) < .01, "Crawling stays grounded while moving: " + clip)
			check(actor.camera.global_position.y >= .25 and actor.camera.global_position.y <= .40, "Moving prone eye stays near ground: " + clip)
			eye_low = minf(eye_low, actor.camera.global_position.y)
			eye_high = maxf(eye_high, actor.camera.global_position.y)
		check(driver.current_clip == "injury/" + clip, "Production movement selects correct injury cycle: " + clip)
		if clip != "prone_idle": check(actor.global_position.distance_to(start) > .2, "Prone input produces real floor movement: " + clip)
		print("PRONE_MOVEMENT_AUDIT ", JSON.stringify({"clip": clip, "floor_root_y": start.y,
			"eye_min": eye_low, "eye_max": eye_high, "distance": actor.global_position.distance_to(start)}))
		Input.action_release("move_forward")

func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	current_scene = arena
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	actor = PLAYER.instantiate()
	arena.add_child(actor)
	visual = actor.get_node("Visuals")
	driver = visual.get_node("Locomotion")
	skeleton = visual.skeleton
	await steps(2)
	audit_cycles()
	await audit_movement()
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: six full prone skin cycles, support, unstretched limbs, injury visibility, grounded movement and low camera")
	quit(0 if failures.is_empty() else 1)
