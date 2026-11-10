extends "res://enemies/white_apparition/white_apparition_visual.gd"

const STRIDE_LENGTH := 2.9
const EYE_CENTER := Vector3(0.0, 0.142, -0.094)
var focus := Vector3.INF
var running := false
var _stride_phase := 0.0
var _stride_weight := 0.0

func _ready() -> void:
	super._ready()
	if not _rig_ready: return
	var socket := BoneAttachment3D.new()
	socket.bone_name = "Head"
	_skeletons[0].add_child(socket)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.35
	var mesh := SphereMesh.new()
	mesh.radius = 0.031
	mesh.height = 0.043
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = mesh
		eye.position = EYE_CENTER + Vector3.RIGHT * 0.044 * side
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		socket.add_child(eye)

func _layer_count() -> int:
	return 1

func _skin_material(_layer: int) -> Material:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.018, 0.019, 0.023)
	material.roughness = 1.0
	material.metallic_specular = 0.15
	return material

func begin_appearance() -> void:
	super.begin_appearance()
	running = false
	_stride_phase = 0.0
	_stride_weight = 0.0
	if _rig_ready: _skeletons[0].reset_bone_poses()

func advance_stride(distance: float, delta: float) -> void:
	_stride_phase = fposmod(_stride_phase + distance / STRIDE_LENGTH, 1.0)
	var weight := clampf(distance / (maxf(delta, 0.001) * 2.0), 0.0, 1.0)
	_stride_weight = move_toward(_stride_weight, weight, delta * 8.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not _rig_ready: return
	if running:
		super._process(delta)
		return
	if not focus.is_finite(): return
	var skeleton := _skeletons[0]
	var neck: int = _bones.Neck
	var origin := skeleton.get_bone_global_pose(neck).origin
	var target := skeleton.to_local(focus) - origin
	var yaw := clampf(atan2(-target.x, -target.z), -1.45, 1.45)
	var pitch := clampf(atan2(target.y, Vector2(target.x, target.z).length()), -0.68, 0.68)
	var turn := Quaternion.from_euler(Vector3(pitch, yaw, 0.0))
	var current := skeleton.get_bone_pose_rotation(neck)
	skeleton.set_bone_pose_rotation(neck, current.slerp(turn, 1.0 - exp(-delta * 4.5)))

func _ankle_target(skeleton: Skeleton3D, foot: int, suffix: String) -> Transform3D:
	var ankle := super._ankle_target(skeleton, foot, suffix)
	var phase := fposmod(_stride_phase + (0.5 if suffix == "R" else 0.0), 1.0)
	if phase < 0.5:
		ankle.origin.z += lerpf(-0.73, 0.73, phase * 2.0) * _stride_weight
	else:
		var swing := (phase - 0.5) * 2.0
		ankle.origin.z += lerpf(0.73, -0.73, smoothstep(0.0, 1.0, swing)) * _stride_weight
		ankle.origin.y += sin(swing * PI) * 0.55 * _stride_weight
	return ankle
