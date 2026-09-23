extends "res://enemies/monster_model_visual.gd"
## Per-actor animation library; imported resources are never mutated.
const LOOPS := ["idle", "walk", "chase", "sprint", "crouch_idle", "crouch_walk", "climb_loop", "hang_idle", "slip_loop", "fall_loop"]
var skeleton: Skeleton3D
var pose_modifier: SkeletonModifier3D
var actor: Raker
var locked := 0.0
var previous_climbing := false
var previous_floor := true
const GAITS := ["walk", "chase", "sprint"]
var ground_clip := "idle"
var filtered_speed := 0.0
var airborne_time := 0.0

func _ready() -> void:
	actor = get_parent()
	for node in $Model.find_children("*", "MeshInstance3D", true, false): meshes.append(node)
	animation_player = $Model/AnimationPlayer
	var library := AnimationLibrary.new()
	for name in animation_player.get_animation_list():
		if name == "RESET": continue
		# Godot consumes glTF's _loop naming suffix during scene import.
		var canonical: String = name + "_loop" if name in ["climb", "slip", "fall"] else name
		var clip: Animation = animation_player.get_animation(name).duplicate()
		clip.loop_mode = Animation.LOOP_LINEAR if canonical in LOOPS or canonical.ends_with("_hold") else Animation.LOOP_NONE
		library.add_animation(canonical, clip)
	animation_player.add_animation_library("game", library)
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1,1,1,0)
	actor.attack_started.connect(_attack)
	actor.reaction_started.connect(_reaction)
	actor.death_started.connect(_death)
	skeleton = $Model.find_child("Skeleton3D", true, false)
	pose_modifier = preload("res://enemies/raker_pose_modifier.gd").new()
	pose_modifier.actor = actor
	skeleton.add_child(pose_modifier)
	play("idle")

func play(clip: String, speed: float = 1.0, restart: bool = false, blend: float = .16) -> void:
	var name := "game/" + clip
	animation_player.speed_scale = speed
	if animation_player.current_animation != name or restart:
		var old_clip := animation_player.current_animation.trim_prefix("game/")
		var preserve_step := not restart and old_clip in GAITS and clip in GAITS
		var phase := 0.0
		if preserve_step and animation_player.current_animation_length > 0:
			phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0)
		animation_player.play(name, 0.24 if preserve_step else blend)
		if preserve_step:
			animation_player.seek(phase * animation_player.get_animation(name).length, false)

func _ground_locomotion(delta: float, speed: float) -> void:
	filtered_speed = move_toward(filtered_speed, speed, delta * 12.0)
	# A wall or completed stop must not leave a fast cycle playing in place.
	if speed < .08: filtered_speed = 0.0
	if speed < .08 and filtered_speed < .18: ground_clip = "idle"
	elif actor.crouched: ground_clip = "crouch_walk" if speed > .12 else "crouch_idle"
	elif actor.pursuit_gait == Raker.PursuitGait.VEHICLE_SPRINT and filtered_speed > (4.0 if ground_clip == "sprint" else 5.0): ground_clip = "sprint"
	elif filtered_speed > (1.9 if ground_clip == "chase" or ground_clip == "sprint" else 2.5): ground_clip = "chase"
	else: ground_clip = "walk"
	if actor.crouched and ground_clip == "idle": ground_clip = "crouch_idle"
	var rate := 1.0
	match ground_clip:
		"walk": rate = clampf(filtered_speed / 1.13, .4, 1.8)
		"chase": rate = clampf(filtered_speed / 2.3, .6, 1.8)
		"sprint": rate = clampf(filtered_speed / 6.0, .8, 2.5)
		"crouch_walk": rate = clampf(filtered_speed / .4, .4, 1.8)
	play(ground_clip, rate)

func _attack(clip: String, duration: float) -> void:
	locked = duration
	var speed := 1.0
	var blend := .16
	if clip.begins_with("grab_"):
		if clip.ends_with("_bite"):
			speed = actor.grab.BITE_SPEED
			blend = .035
		elif clip.ends_with("_reach"):
			speed = .6 / actor.grab.REACH_DURATION
			blend = .06
	play(clip, speed, true, blend)

func _reaction() -> void:
	locked = .3
	play("crouch_hit_react" if actor.crouched else "hit_react", 1, true)

func _death() -> void:
	locked = 100
	play("crouch_death" if actor.crouched else "death", 1, true)

func _process(delta: float) -> void:
	if actor.is_dead: return
	if is_instance_valid(actor.grab) and actor.grab.busy(): return
	locked = maxf(0, locked-delta)
	var climbing := actor.locomotion_state == Monster.LocomotionState.CLIMBING
	var floor_now := actor.is_on_floor()
	if not floor_now and not climbing: airborne_time += delta
	if actor.strike_elapsed < 0 and actor.reaction_remaining <= 0:
		if previous_climbing and not climbing and actor.post_climb_transfer_time_remaining > 0:
			locked = .7
			play("mantle", 1, true)
		elif floor_now and not previous_floor and airborne_time > .12 and not climbing and locked <= 0:
			locked = .4
			play("crouch_land" if actor.crouched else "land", 1, true)
	previous_climbing = climbing
	previous_floor = floor_now
	if floor_now or climbing: airborne_time = 0.0
	if locked > 0: return
	if climbing:
		if actor.boarding.grip < actor.grip_capacity*.2: play("slip_loop")
		elif actor.boarding.mode == MonsterBoarding.Mode.DOOR: play("hang_idle")
		else: play("climb_loop")
	elif actor.boarding.settle > 0 and actor.boarding.on_roof(actor): play("roof_settle")
	elif not floor_now and actor.velocity.y < -.5: play("fall_loop")
	else:
		var speed := Vector2(actor.velocity.x, actor.velocity.z).length()
		_ground_locomotion(delta, speed)

func bone_world_position(bone_name: String) -> Vector3:
	if pose_modifier.world_positions.has(bone_name): return skeleton.global_transform * pose_modifier.world_positions[bone_name]
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

func arm_lengths(side: int) -> Vector2:
	var suffix := "_R" if side > 0 else "_L"
	return Vector2(skeleton.get_bone_rest(skeleton.find_bone("forearm" + suffix)).origin.length(), skeleton.get_bone_rest(skeleton.find_bone("hand" + suffix)).origin.length())
