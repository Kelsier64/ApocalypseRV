extends "res://enemies/monster_model_visual.gd"
## Pose the retained Raker skin per instance. Source rig and clips stay untouched.
const STRIDE := 0.64
const STANCE := 0.65
var skeleton: Skeleton3D
var actor: Monster
var bones: Dictionary = {}
var phase := 0.0
var breathing := 0.0
var gait_weight := 0.0
var attack_pulse := 0.0
## Used only by the inspection scene; negative means actual actor velocity.
var preview_speed := -1.0

func _ready() -> void:
	actor = get_parent()
	for node in $Model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	animation_player = $Model/AnimationPlayer
	animation_player.stop()
	animation_player.active = false
	skeleton = $Model.find_child("Skeleton3D", true, false)
	for index in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(index)] = index
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1, 1, 1, 0)
	actor.attack_landed.connect(_on_attack)
	pose(0.0, 0.0)

func _on_attack(_target: Node3D, _source: String) -> void:
	attack_pulse = 1.0

func _process(delta: float) -> void:
	if actor.is_dead: return
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	if preview_speed >= 0.0: speed = preview_speed
	breathing += delta
	gait_weight = move_toward(gait_weight, minf(speed / 0.35, 1.0), delta * 6.0)
	# During stance, contact retreats at actor speed; swing has a smooth lifted arc.
	phase = fposmod(phase + speed * STANCE / (STRIDE * $Model.scale.z) * delta, 1.0)
	attack_pulse = maxf(0.0, attack_pulse - delta * 4.0)
	pose(phase, gait_weight)

func pose(cycle: float, weight: float) -> void:
	skeleton.reset_bone_poses()
	var hips: Transform3D = skeleton.get_bone_global_rest(bones.pelvis)
	var roll := sin(cycle * TAU) * 0.025 * weight
	hips.basis = Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, deg_to_rad(82)) * hips.basis
	hips.origin = Vector3(0, 0.55 + sin(breathing * 2.0) * 0.008, -0.40)
	hips.origin.y += cos(cycle * TAU * 2) * 0.012 * weight
	hips.origin.z += attack_pulse * 0.10
	_set_global(bones.pelvis, hips)
	# Lift the face from the prone torso with a distributed neck bend.
	for part in ["neck_01", "neck_02", "head"]:
		var index: int = bones[part]
		var neck := skeleton.get_bone_global_pose(index)
		neck.basis = Basis(Vector3.RIGHT, deg_to_rad(-27)) * neck.basis
		_set_global(index, neck)
	for side in [-1, 1]:
		var suffix := "_L" if side > 0 else "_R"
		var arm_phase := fposmod(cycle + (0.0 if side > 0 else 0.5), 1.0)
		var leg_phase := fposmod(arm_phase + 0.5, 1.0)
		var hand := Vector3(side * 0.72, 0.035, 0.48) + _step(arm_phase) * weight
		var foot := Vector3(side * 0.64, 0.115, -0.79) + _step(leg_phase) * weight
		_solve_limb("upper_arm" + suffix, "forearm" + suffix, "hand" + suffix, hand, Vector3(side, 0.65, -0.05))
		_solve_limb("thigh" + suffix, "shin" + suffix, "foot" + suffix, foot, Vector3(side, 0.25, 0.4))
		_plant_hand(side, suffix)
		var ankle: int = bones["foot" + suffix]
		var ankle_pose := skeleton.get_bone_global_pose(ankle)
		ankle_pose.basis = Basis(Vector3.UP, side * 0.25) * skeleton.get_bone_global_rest(ankle).basis
		_set_global(ankle, ankle_pose)

func _step(t: float) -> Vector3:
	if t < STANCE:
		return Vector3(0, 0, STRIDE * (0.5 - t / STANCE))
	var swing := (t - STANCE) / (1.0 - STANCE)
	return Vector3(0, sin(swing * PI) * 0.15, STRIDE * (smoothstep(0, 1, swing) - 0.5))

func _set_global(index: int, value: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(index)
	if parent >= 0: value = skeleton.get_bone_global_pose(parent).affine_inverse() * value
	skeleton.set_bone_pose(index, value)

func _aim(index: int, child: int, target: Vector3) -> void:
	var value := skeleton.get_bone_global_pose(index)
	var current := (skeleton.get_bone_global_pose(child).origin - value.origin).normalized()
	var direction := (target - value.origin).normalized()
	value.basis = Basis(Quaternion(current, direction)) * value.basis
	_set_global(index, value)

func _solve_limb(upper_name: String, lower_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var upper: int = bones[upper_name]
	var lower: int = bones[lower_name]
	var end: int = bones[end_name]
	var start := skeleton.get_bone_global_pose(upper).origin
	var a := skeleton.get_bone_rest(lower).origin.length()
	var b := skeleton.get_bone_rest(end).origin.length()
	var direction := (target - start).normalized()
	var distance := clampf(start.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0, a * a - along * along))
	var elbow := start + direction * along + pole.slide(direction).normalized() * height
	_aim(upper, lower, elbow)
	_aim(lower, end, start + direction * distance)

func _plant_hand(side: int, suffix: String) -> void:
	var hand: int = bones["hand" + suffix]
	var rest := skeleton.get_bone_global_rest(hand)
	var finger := (skeleton.get_bone_global_rest(bones["middle_01" + suffix]).origin - rest.origin).normalized()
	var index := skeleton.get_bone_global_rest(bones["index_01" + suffix]).origin - rest.origin
	var palm := finger.cross(index).normalized() * float(-side)
	var local_frame := rest.basis.inverse() * Basis(finger.cross(palm).normalized(), finger, palm)
	var forward := Vector3(side * 0.18, 0, 1).normalized()
	var goal := Basis(forward.cross(Vector3.DOWN).normalized(), forward, Vector3.DOWN)
	var value := skeleton.get_bone_global_pose(hand)
	value.basis = goal * local_frame.inverse()
	_set_global(hand, value)
