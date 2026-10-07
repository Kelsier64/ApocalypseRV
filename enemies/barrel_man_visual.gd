extends "res://enemies/monster_model_visual.gd"
## Authored Blender clips; gameplay owns all root movement and state timing.
const BARREL = preload("res://assets/models/oil_barrel/oil_barrel.glb")
const LOOPS = ["disguised", "idle", "run", "sprint", "turn_left", "turn_right", "fall"]
var actor: BarrelMan
var skeleton: Skeleton3D
var barrel_bone := -1
var attachment: BoneAttachment3D
var ground_modifier: SkeletonModifier3D
var previous_floor := true
var previous_yaw := 0.0
var land_remaining := 0.0
var airborne_time := 0.0
var current_clip := ""

func _ready() -> void:
	actor = get_parent() as BarrelMan
	process_physics_priority = 1
	skeleton = $Model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		for node in $Model.find_children("*", "Skeleton3D", true, false): skeleton = node; break
	animation_player = $Model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(skeleton != null and animation_player != null, "BarrelMan GLB requires skeleton and authored clips")
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	for imported in animation_player.get_animation_list():
		if imported == "RESET": continue
		var canonical := str(imported).get_file().trim_suffix("_loop")
		var clip := animation_player.get_animation(imported).duplicate() as Animation
		clip.loop_mode = Animation.LOOP_LINEAR if canonical in LOOPS else Animation.LOOP_NONE
		library.add_animation(canonical, clip)
	animation_player.add_animation_library("game", library)
	barrel_bone = skeleton.find_bone("barrel")
	assert(barrel_bone >= 0)
	attachment = BoneAttachment3D.new()
	attachment.name = "SharedBarrel"
	attachment.bone_name = "barrel"
	skeleton.add_child(attachment)
	var barrel := BARREL.instantiate() as Node3D
	attachment.add_child(barrel)
	barrel.basis = skeleton.get_bone_global_rest(barrel_bone).basis.inverse()
	for node in $Model.find_children("*", "MeshInstance3D", true, false): meshes.append(node)
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1, 1, 1, 0)
	ground_modifier = preload("res://enemies/barrel_man_grounding.gd").new()
	ground_modifier.actor = actor
	skeleton.add_child(ground_modifier)
	previous_yaw = actor.rotation.y
	_play("disguised", 0.0)
	animation_player.advance(0.0)

func _play(clip: String, blend: float = 0.10, rate: float = 1.0) -> void:
	var key := "game/" + clip
	if not animation_player.has_animation(key): return
	if current_clip != clip:
		var old_phase := 0.0
		if current_clip in ["run", "sprint", "turn_left", "turn_right"] and animation_player.current_animation_length > 0:
			old_phase = animation_player.current_animation_position / animation_player.current_animation_length
		animation_player.play(key, blend)
		if clip in ["run", "sprint", "turn_left", "turn_right"]: animation_player.seek(old_phase * animation_player.get_animation(key).length, true)
		current_clip = clip
	animation_player.speed_scale = rate

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor.is_dead: return
	var fraction := clampf((actor.visual_height - .5) / .9, 0.0, 1.0)
	if actor.phase in [BarrelMan.Phase.DISGUISED, BarrelMan.Phase.RISING, BarrelMan.Phase.RETRACTING]:
		# Seeking the rise clip in both directions also supports interrupted retracts.
		var clip := "disguised" if actor.phase == BarrelMan.Phase.DISGUISED else "rise"
		_play(clip, 0.0, 0.0)
		animation_player.seek(fraction * .8 if clip == "rise" else 0.0, true)
		animation_player.advance(0.0)
		previous_floor = actor.is_on_floor()
		previous_yaw = actor.rotation.y
		return
	var floor_now := actor.is_on_floor()
	if not floor_now: airborne_time += delta
	elif not previous_floor and airborne_time > .12:
		land_remaining = .4
		airborne_time = 0.0
	previous_floor = floor_now
	land_remaining = maxf(0.0, land_remaining - delta)
	var yaw_speed := angle_difference(previous_yaw, actor.rotation.y) / maxf(delta, .001)
	previous_yaw = actor.rotation.y
	if not floor_now and airborne_time > .12: _play("fall")
	elif land_remaining > 0 and actor.horizontal_speed < .6: _play("land", .05)
	elif actor.horizontal_speed < .15: _play("idle", .15)
	elif actor.horizontal_speed > 7.5: _play("sprint", .1, clampf(actor.horizontal_speed / 10.0, .45, 1.25))
	elif absf(yaw_speed) > .9: _play("turn_left" if yaw_speed > 0 else "turn_right", .1, clampf(actor.horizontal_speed / 6.0, .25, 1.3))
	else: _play("run", .12, clampf(actor.horizontal_speed / 6.0, .25, 1.3))
	animation_player.advance(delta)
	ground_modifier.landing_compression = 0.0
	if land_remaining > 0.0 and actor.horizontal_speed >= .6:
		# Keep the running stride through a moving landing, adding a short weight
		# compression instead of sliding the planted feet of the standing clip.
		var progress := 1.0 - land_remaining / .4
		var compression := .07 * sin(PI * minf(1.0, progress * 1.6))
		ground_modifier.landing_compression = compression
		for name in ["pelvis", "barrel"]:
			var bone := skeleton.find_bone(name)
			var pose := skeleton.get_bone_global_pose(bone)
			pose.origin.y -= compression
			skeleton.set_bone_global_pose(bone, pose)

func get_blast_origin() -> Vector3:
	if skeleton != null and barrel_bone >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(barrel_bone).origin
	return actor.global_position + Vector3.UP * actor.visual_height
