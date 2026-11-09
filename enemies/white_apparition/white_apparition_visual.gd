extends Node3D
## Continuous skinned anatomy with large, deliberately uncoordinated dance phrases.
const MODEL = preload("res://assets/models/white_apparition/white_apparition.glb")
const SKIN = preload("res://enemies/white_apparition/white_apparition.gdshader")
const BONES := ["Hips", "Spine", "Chest", "Neck", "Head", "UpperArmL", "ForearmL", "HandL", "ThighL", "ShinL", "FootL", "UpperArmR", "ForearmR", "HandR", "ThighR", "ShinR", "FootR"]
var confirmed := 0.0
var _presence := 0.0
var _clock := 0.0
var _phrase_time := 0.0
var _phrase_duration := 2.4
var _phrase := 2
var _rng := RandomNumberGenerator.new()
var _skeletons: Array[Skeleton3D] = []
var _models: Array[Node3D] = []
var _bones: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _history: Array[Dictionary] = []
var _history_clock := 0.0

func _ready() -> void:
	_rng.randomize()
	_clock = _rng.randf_range(0.0, 30.0)
	for layer in 3:
		var model := MODEL.instantiate() as Node3D
		model.name = "Skin" if layer == 0 else "Echo%d" % layer
		add_child(model)
		_models.append(model)
		var material := ShaderMaterial.new()
		material.shader = SKIN
		material.set_shader_parameter("veil", 0.0 if layer == 0 else 1.0)
		material.set_shader_parameter("presence", _presence)
		_materials.append(material)
		for part in model.find_children("*", "Node3D", true, false):
			if part is MeshInstance3D:
				part.material_override = material
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				part.extra_cull_margin = 1.6
			elif part is Skeleton3D:
				_skeletons.append(part)
	for bone in BONES:
		_bones[bone] = _skeletons[0].find_bone(bone)
	visible = _presence > 0.001

func set_presence(amount: float) -> void:
	var was_visible := visible
	_presence = clampf(amount, 0.0, 1.0)
	visible = _presence > 0.001
	for material in _materials:
		material.set_shader_parameter("presence", _presence)
	if not visible:
		_history.clear()
	elif not was_visible:
		_phrase = _rng.randi_range(0, 2)
		_phrase_time = 0.0

func gaze_points() -> PackedVector3Array:
	if _skeletons.is_empty(): return PackedVector3Array()
	var skeleton := _skeletons[0]
	return PackedVector3Array([
		skeleton.to_global(skeleton.get_bone_global_pose(_bones.Chest) * Vector3(0, 0.08, 0)),
		skeleton.to_global(skeleton.get_bone_global_pose(_bones.Head) * Vector3(0, 0.105, 0))])

func _process(delta: float) -> void:
	if not visible or _skeletons.is_empty() or confirmed > 0.0: return
	_clock += delta
	_phrase_time += delta
	if _phrase_time >= _phrase_duration:
		_phrase_time = 0.0
		# Brief interruptions punctuate the dance; most time is spent moving.
		_phrase = (_phrase + _rng.randi_range(1, 2)) % 3 if _phrase == 3 or _rng.randf() > 0.16 else 3
		_phrase_duration = _rng.randf_range(1.6, 3.1) if _phrase != 3 else _rng.randf_range(0.12, 0.24)
	if _phrase == 3: return
	var t := _clock
	var beat := t * 4.6
	var sway := sin(t * 3.1)
	var jerk := pow(maxf(0.0, sin(t * 17.3)), 12.0) * sin(t * 8.7)
	var fold := 1.0 if _phrase == 0 else 0.48
	var twist := 1.0 if _phrase == 1 else 0.4
	var dance := 1.0 if _phrase == 2 else 0.65
	var pose := {
		"Hips": Vector3(0.12 * sin(beat), sin(t * 2.4) * 0.7 * twist, sway * 0.22),
		"Spine": Vector3(sin(t * 2.7) * 0.32, -sin(t * 2.4 - 0.4) * 0.85 * twist, -sway * 0.72 * fold),
		"Chest": Vector3(-0.22 + sin(t * 2.7 - 0.8) * 0.36, -sin(t * 2.4 - 0.8) * 0.7 * twist, -sin(t * 3.1 - 0.65) * 0.5 * fold + jerk * 0.2),
		"Neck": Vector3(sin(t * 2.7 - 1.4) * 0.44, sin(t * 2.4 - 1.5) * 0.5, sin(t * 3.1 - 1.4) * 0.65 * fold),
		"Head": Vector3(-0.2 + jerk * 0.48, sin(t * 2.4 - 1.9) * 0.48, sin(t * 3.1 - 1.9) * 0.65 + jerk * 0.35),
	}
	for side in [-1, 1]:
		var suffix := "L" if side < 0 else "R"
		var phase: float = beat + (0.0 if side < 0 else PI + 0.45)
		var lift := maxf(0.0, sin(phase))
		pose["UpperArm" + suffix] = Vector3(sin(phase * 0.7) * 0.9, side * cos(phase * 0.6) * 0.7, side * (0.65 + (sin(phase * 0.68) + 1.0) * 0.95 * dance))
		pose["Forearm" + suffix] = Vector3(-0.45 - (cos(phase * 0.86) + 1.0) * 0.8, sin(phase) * 0.45, side * (sin(phase * 1.3) * 0.65 + jerk * 0.35))
		pose["Hand" + suffix] = Vector3(0.7 + sin(phase - 0.9) * 0.6, sin(phase * 1.2) * 0.35, side * 0.45)
		pose["Thigh" + suffix] = Vector3(-lift * 0.85 * dance, side * (0.18 + sin(phase * 0.5) * 0.23), side * (0.12 + sin(phase) * 0.17))
		pose["Shin" + suffix] = Vector3(0.15 + lift * 1.1 * dance, 0, side * jerk * 0.08)
		pose["Foot" + suffix] = Vector3(-0.12 - lift * 0.3, side * 0.22, sin(phase) * 0.16)
	var skeleton := _skeletons[0]
	var blend := 1.0 - exp(-delta * (22.0 + absf(jerk) * 35.0))
	for bone in pose:
		var index: int = _bones[bone]
		var rotation := skeleton.get_bone_pose_rotation(index).slerp(Quaternion.from_euler(pose[bone]), blend)
		skeleton.set_bone_pose_rotation(index, rotation)
		pose[bone] = rotation
	# Plant the lowest sole while the opposite knee lifts; avoid sinking the dance into terrain.
	_models[0].position = Vector3(sway * 0.11, 0, sin(t * 2.3) * 0.045)
	var sole_height := INF
	var skeleton_to_model := _models[0].global_transform.affine_inverse() * skeleton.global_transform
	for foot in ["FootL", "FootR"]:
		var transform := skeleton.get_bone_global_pose(_bones[foot])
		for point in [Vector3(0, -0.065, 0.02), Vector3(0, -0.065, -0.16)]:
			sole_height = minf(sole_height, (skeleton_to_model * (transform * point)).y)
	_models[0].position.y = -sole_height
	_history_clock += delta
	if _history_clock >= 0.035:
		_history_clock = fmod(_history_clock, 0.035)
		_history.push_front({"rotations": pose.duplicate(), "root": _models[0].position})
		if _history.size() > 10: _history.pop_back()
	for layer in range(1, 3):
		if _history.is_empty(): continue
		var delayed: Dictionary = _history[mini(layer, _history.size() - 1)]
		for bone in delayed.rotations:
			_skeletons[layer].set_bone_pose_rotation(_bones[bone], delayed.rotations[bone])
		_models[layer].position = delayed.root + Vector3(layer * 0.012 * sin(t * 2.3), 0, layer * 0.01)
