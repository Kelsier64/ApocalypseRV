extends Node3D
## Traveling bends through a continuous skin, with a fixed stance under the moving torso.
const MODEL = preload("res://assets/models/white_apparition/white_apparition.glb")
const SKIN = preload("res://enemies/white_apparition/white_apparition.gdshader")
const SPINE := ["Hips", "Spine", "Spine02", "Spine03", "Spine04", "Spine05", "Spine06", "Spine07", "Chest", "Neck", "Neck02", "Head"]
const ARM := ["UpperArm", "ArmBend", "Forearm", "Wrist", "Hand"]
const LEG := ["Thigh", "LegBend", "Shin", "Foot"]
const SIDES := ["L", "R"]
# Traveling wave, torsion, arm weaving, side fold, suspended reach.
const STYLES := [Vector3(1.19, 0.64, 0.88), Vector3(0.87, -0.34, 0.72), Vector3(0.91, 0.04, 1.0), Vector3(0.62, 0.18, 0.56), Vector3(1.13, 0.04, 1.0)]
const SHUDDER := 5
const REST_SOLE_HEIGHT := 0.03003
const HISTORY_INTERVAL := 0.04
var _clock := 0.0
var _phrase_time := 0.0
var _phrase_duration := 4.0
var _phrase := 2
var _style: Vector3 = STYLES[2]
var _motifs: Array[float] = [0.0, 0.0, 1.0, 0.0, 0.0]
var _rate := 1.0
var _target_rate := 1.0
var _last_sustained := 2
var _rng := RandomNumberGenerator.new()
var _skeletons: Array[Skeleton3D] = []
var _models: Array[Node3D] = []
var _bones: Dictionary = {}
var _rig_ready := false
var _history: Array[Dictionary] = []
var _history_clock := 0.0

func _ready() -> void:
	_rng.randomize()
	_clock = _rng.randf_range(0.0, 30.0)
	for layer in 3:
		var model := MODEL.instantiate() as Node3D
		model.name = "Skin" if layer == 0 else "Echo%d" % layer
		model.position.y = -REST_SOLE_HEIGHT
		add_child(model)
		_models.append(model)
		var material := ShaderMaterial.new()
		material.shader = SKIN
		material.set_shader_parameter("veil", 0.0 if layer == 0 else 1.0)
		for part in model.find_children("*", "Node3D", true, false):
			if part is MeshInstance3D:
				part.material_override = material
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				part.extra_cull_margin = 1.6
			elif part is Skeleton3D:
				_skeletons.append(part)
	if _skeletons.size() != _models.size():
		push_error("White apparition model requires one skeleton per instance")
		return
	var bone_names := SPINE.duplicate()
	for suffix in SIDES:
		for bone in ARM + LEG:
			bone_names.append(bone + suffix)
	for bone in bone_names:
		var index := _skeletons[0].find_bone(bone)
		if index < 0:
			push_error("White apparition model is missing bone %s" % bone)
			return
		_bones[bone] = index
	_rig_ready = true

func begin_appearance() -> void:
	_history.clear()
	_history_clock = 0.0
	_phrase = _rng.randi_range(0, STYLES.size() - 1)
	_last_sustained = _phrase
	_phrase_time = 0.0
	_phrase_duration = _rng.randf_range(2.8, 4.8)
	_target_rate = _rng.randf_range(0.7, 1.35)
	_rate = _target_rate
	_style = STYLES[_phrase]
	for motif in _motifs.size():
		_motifs[motif] = 1.0 if motif == _phrase else 0.0

func gaze_points() -> PackedVector3Array:
	if not _rig_ready: return PackedVector3Array()
	var skeleton := _skeletons[0]
	return PackedVector3Array([
		skeleton.to_global(skeleton.get_bone_global_pose(_bones.Chest) * Vector3(0, 0.045, 0)),
		skeleton.to_global(skeleton.get_bone_global_pose(_bones.Head) * Vector3(0, 0.145, 0))])

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not _rig_ready: return
	_phrase_time += delta
	if _phrase_time >= _phrase_duration:
		_phrase_time = 0.0
		if _phrase != SHUDDER and _rng.randf() < 0.18:
			_last_sustained = _phrase
			_phrase = SHUDDER
			_phrase_duration = _rng.randf_range(0.17, 0.26)
		else:
			var previous := _last_sustained if _phrase == SHUDDER else _phrase
			_phrase = (previous + _rng.randi_range(1, STYLES.size() - 1)) % STYLES.size()
			_last_sustained = _phrase
			_phrase_duration = _rng.randf_range(2.8, 4.8)
			_target_rate = _rng.randf_range(0.7, 1.35)
	var progress := clampf(_phrase_time / _phrase_duration, 0.0, 1.0)
	var pace := _target_rate
	if _phrase == 4:
		# Hang in an unfinished gesture, then resume faster; never reset the wave phase.
		var hold := smoothstep(0.14, 0.29, progress) * (1.0 - smoothstep(0.65, 0.78, progress))
		pace = lerpf(_target_rate + 0.5 * smoothstep(0.72, 0.9, progress), 0.025, hold)
	_rate = lerpf(_rate, pace, 1.0 - exp(-delta * 9.0))
	_clock += delta * _rate
	var shudder := 0.0
	if _phrase == SHUDDER:
		var envelope := sin(PI * _phrase_time / _phrase_duration)
		shudder = envelope * envelope * sin(_phrase_time * 56.0)
	else:
		_style = _style.lerp(STYLES[_phrase], 1.0 - exp(-delta * 2.0))
		for motif in _motifs.size():
			_motifs[motif] = lerpf(_motifs[motif], 1.0 if motif == _phrase else 0.0, 1.0 - exp(-delta * 2.5))
	var t := _clock
	var skeleton := _skeletons[0]
	var hips: int = _bones.Hips
	var hip_position := skeleton.get_bone_rest(hips).origin + Vector3(
		0.13 * sin(t * 1.42), -0.069 + 0.024 * sin(t * 1.19), 0.095 * sin(t * 1.11 + 0.9))
	skeleton.set_bone_pose_position(hips, hip_position)
	_pose_spine(skeleton, t, shudder)
	var chest := skeleton.get_bone_global_pose(_bones.Chest).basis.get_rotation_quaternion()
	var arm_support := Quaternion.IDENTITY.slerp(chest, 0.22)
	for side in SIDES.size():
		_pose_arm(skeleton, t, shudder, side, arm_support)
		_plant_foot(skeleton, SIDES[side])
	_update_echoes(delta, hip_position)

func _pose_spine(skeleton: Skeleton3D, time: float, shudder: float) -> void:
	var parent_frame := Quaternion.IDENTITY
	for segment in SPINE.size():
		# These are tangents along one wave, expressed in skeleton space.
		# Converting adjacent tangents to local turns prevents the bend accumulating at each joint.
		var height := float(segment) / float(SPINE.size() - 1)
		var delayed := time - 0.48 * smoothstep(0.69, 1.0, height)
		var phase := delayed * 1.82 + 0.22 * sin(delayed * 0.58) - height * 5.5
		var amplitude := lerpf(0.19, _style.x, smoothstep(0.0, 0.52, height))
		var bend := amplitude * (0.89 * sin(phase) + 0.23 * sin(delayed * 1.13 - height * 2.6))
		var plane := _style.y + 0.84 * sin(time * 0.38) + 0.48 * height
		var turn := (0.24 + height * 0.43) * sin(delayed * 1.21 - height * 3.1)
		# Opposed chest/waist rotation and an off-centre fold change the silhouette,
		# rather than merely changing the amplitude of the same wave.
		turn += _motifs[1] * 0.78 * sin(height * 5.2 - 0.8) * sin(delayed * 0.91)
		var fold := _motifs[3] * sin(delayed * 0.83) * smoothstep(0.0, 0.55, height)
		var frame := Quaternion.from_euler(Vector3(
			bend * sin(plane) - 0.19 * height + shudder * 0.09 * height + absf(fold) * 0.28,
			turn,
			bend * cos(plane) + height * 0.14 * sin(delayed * 0.77) + fold * (0.86 - 0.48 * height)))
		skeleton.set_bone_pose_rotation(_bones[SPINE[segment]], parent_frame.inverse() * frame)
		parent_frame = frame

func _pose_arm(skeleton: Skeleton3D, time: float, shudder: float, side: int, support: Quaternion) -> void:
	var suffix: String = SIDES[side]
	var outward := -1.0 if side == 0 else 1.0
	var parent_frame := skeleton.get_bone_global_pose(_bones.Chest).basis.get_rotation_quaternion()
	for segment in ARM.size():
		var delayed := time - float(segment) * 0.18
		var phase := delayed * (0.87 if side == 0 else 1.06) + float(side) * 2.8
		var sweep := sin(phase) + 0.19 * sin(phase * 0.57 + 0.5)
		var rise := smoothstep(-0.46, 1.0, sweep)
		var elevation := 0.11 + 2.48 * _style.z * rise
		var reach_axis := Vector3(0.44 * sin(phase * 0.6 + 0.8) + 0.19, 0, outward).normalized()
		var curl := float(segment) * (0.07 + 0.14 * sin(phase * 1.36 - 0.9))
		var frame := support * Quaternion(reach_axis, elevation) * Quaternion.from_euler(Vector3(
			curl + shudder * 0.14 * outward,
			0.34 * sin(phase * 0.87),
			outward * float(segment) * 0.05 * cos(phase * 1.23)))
		# Forearms weave forward of the torso, with different timing on each side.
		var weave := support * Quaternion.from_euler(Vector3(
			0.95 + 0.42 * sin(phase) + float(segment) * 0.13,
			outward * (0.28 + 0.3 * sin(phase * 0.73)),
			-outward * (0.4 + 0.3 * sin(phase - float(segment) * 0.32))))
		frame = frame.slerp(weave, _motifs[2])
		# In the side fold one arm trails low while the other hooks over the head.
		var hook := support * Quaternion(reach_axis, (0.22 if side == 0 else 2.62) + 0.2 * sin(phase)) * Quaternion.from_euler(Vector3(
			float(segment) * 0.19, 0.24 * sin(phase), -outward * float(segment) * 0.16))
		frame = frame.slerp(hook, _motifs[3])
		skeleton.set_bone_pose_rotation(_bones[ARM[segment] + suffix], parent_frame.inverse() * frame)
		parent_frame = frame

func _plant_foot(skeleton: Skeleton3D, suffix: String) -> void:
	var thigh: int = _bones["Thigh" + suffix]
	var bend: int = _bones["LegBend" + suffix]
	var shin: int = _bones["Shin" + suffix]
	var foot: int = _bones["Foot" + suffix]
	var hips := skeleton.get_bone_global_pose(_bones.Hips)
	var thigh_rest := skeleton.get_bone_rest(thigh)
	var bend_rest := skeleton.get_bone_rest(bend)
	var shin_rest := skeleton.get_bone_rest(shin)
	var foot_rest := skeleton.get_bone_rest(foot)
	var planted := skeleton.get_bone_global_rest(foot)
	var thigh_pose := hips * thigh_rest
	var upper := (bend_rest * shin_rest).origin
	var reach := planted.origin - thigh_pose.origin
	var axis := reach.normalized()
	var upper_length := upper.length()
	var lower_length := foot_rest.origin.length()
	var length := clampf(reach.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	var along := (upper_length * upper_length - lower_length * lower_length + length * length) / (2.0 * length)
	var pole := Vector3.FORWARD.slide(axis).normalized()
	var knee := thigh_pose.origin + axis * along + pole * sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var ankle := thigh_pose.origin + axis * length
	# The upper section spans Thigh and LegBend, then Shin aims at the planted ankle.
	var thigh_basis := Basis(Quaternion((thigh_pose.basis * upper).normalized(), (knee - thigh_pose.origin).normalized())) * thigh_pose.basis
	var bend_basis := thigh_basis * bend_rest.basis
	var shin_basis := bend_basis * shin_rest.basis
	shin_basis = Basis(Quaternion((shin_basis * foot_rest.origin).normalized(), (ankle - knee).normalized())) * shin_basis
	skeleton.set_bone_pose_rotation(thigh, (hips.basis.inverse() * thigh_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(shin, (bend_basis.inverse() * shin_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(foot, (shin_basis.inverse() * planted.basis).get_rotation_quaternion())

func _update_echoes(delta: float, hip_position: Vector3) -> void:
	_history_clock += delta
	if _history.is_empty() or _history_clock >= HISTORY_INTERVAL:
		_history_clock = fmod(_history_clock, HISTORY_INTERVAL)
		var rotations: Dictionary = {}
		for index in _bones.values():
			rotations[index] = _skeletons[0].get_bone_pose_rotation(index)
		_history.push_front({"rotations": rotations, "hips": hip_position})
		if _history.size() > 3: _history.pop_back()
	for layer in range(1, _skeletons.size()):
		var delayed: Dictionary = _history[mini(layer, _history.size() - 1)]
		_skeletons[layer].set_bone_pose_position(_bones.Hips, delayed.hips)
		for index in delayed.rotations:
			_skeletons[layer].set_bone_pose_rotation(index, delayed.rotations[index])
