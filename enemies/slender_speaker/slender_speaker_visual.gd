extends Node3D
## Stage 2 presentation only. No actor ownership, hits, death or music.
const CLIPS := ["idle_play", "scan", "walk", "run", "turn_left", "turn_right", "smash", "grab_miss", "grab", "hold", "lift", "crush", "retract"]
const LOOPS := ["idle_play", "scan", "walk", "run", "turn_left", "turn_right", "hold"]
const REVIEW_CLIPS := ["review_hand_open", "review_hand_fist"]
const HEAD_FILL_ENERGY := 8.0
const HEAD_FILL_NIGHT_SHARE := 0.2
const HEAD_FILL_FULL_DISTANCE := 35.0
const HEAD_FILL_END_DISTANCE := 80.0
var skeleton: Skeleton3D
var animation: AnimationPlayer
var available := false
var problem := ""
var _clock: WorldClock
var _head_fill_override_energy := -1.0
var _head_fill_override_view := Vector3.INF
@onready var head_fill: OmniLight3D = $HeadFill

func _enter_tree() -> void:
	_clock = null
	var ancestor := get_parent()
	while ancestor != null and _clock == null:
		_clock = ancestor.get_node_or_null("WorldClock") as WorldClock
		ancestor = ancestor.get_parent()

func _ready() -> void:
	var model := $ModelOffset/Rig
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or animation == null:
		problem = "Rig requires Skeleton3D and AnimationPlayer"
		return
	var library := AnimationLibrary.new()
	for imported in animation.get_animation_list():
		var canonical := String(imported).get_slice("/", String(imported).get_slice_count("/") - 1)
		if canonical.ends_with("_loop"): canonical = canonical.trim_suffix("_loop")
		if canonical not in CLIPS and canonical not in REVIEW_CLIPS: continue
		var clip: Animation = animation.get_animation(imported).duplicate()
		clip.loop_mode = Animation.LOOP_LINEAR if canonical in LOOPS else Animation.LOOP_NONE
		library.add_animation(canonical, clip)
	animation.stop()
	for imported_library in animation.get_animation_library_list():
		animation.remove_animation_library(imported_library)
	animation.add_animation_library("review", library)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in CLIPS:
		if not animation.has_animation("review/" + clip): problem += "Missing clip %s. " % clip
	for socket in ["socket_grip_R", "socket_focus", "socket_strike_R"]:
		if skeleton.find_bone(socket) < 0: problem += "Missing socket %s. " % socket
	available = problem.is_empty()
	if available:
		for cabinet: MeshInstance3D in model.find_children("Speaker_*", "MeshInstance3D", true, false):
			cabinet.layers |= head_fill.light_cull_mask
		sample("idle_play", 0.0)

## Filming can choose when the shared light fades in and where it is aimed from.
func set_head_fill_override(energy: float, viewpoint: Vector3) -> void:
	_head_fill_override_energy = energy
	_head_fill_override_view = viewpoint

func _process(_delta: float) -> void:
	if not available: return
	var viewpoint := _head_fill_override_view
	if not viewpoint.is_finite():
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			head_fill.light_energy = 0.0
			return
		viewpoint = camera.global_position
	var head := bone_world("socket_focus").origin
	var energy := _head_fill_override_energy
	if energy < 0.0:
		var distance_fade := 1.0 - smoothstep(HEAD_FILL_FULL_DISTANCE, HEAD_FILL_END_DISTANCE, head.distance_to(viewpoint))
		var daylight := _clock.daylight() if is_instance_valid(_clock) else 1.0
		energy = HEAD_FILL_ENERGY * distance_fade * lerpf(HEAD_FILL_NIGHT_SHARE, 1.0, daylight)
	head_fill.light_energy = energy
	if energy <= 0.0: return
	var toward_viewer := (viewpoint - head).slide(Vector3.UP)
	toward_viewer /= maxf(1.0, toward_viewer.length())
	head_fill.global_position = head + toward_viewer * 5.0 + toward_viewer.cross(Vector3.UP) * 4.0 + Vector3.UP * 2.5

func duration(clip: String) -> float:
	return animation.get_animation("review/" + clip).length if animation != null and animation.has_animation("review/" + clip) else 0.0

func has_clip(clip: String) -> bool:
	return animation != null and animation.has_animation("review/" + clip)

func sample(clip: String, time: float) -> void:
	if not available or not has_clip(clip): return
	var name := "review/" + clip
	if animation.current_animation != name: animation.play(name, 0.0)
	# Caller controls looping; clamping preserves authored final nonloop poses.
	animation.seek(clampf(time, 0.0, duration(clip)), true)
	animation.advance(0.0)
	skeleton.force_update_all_bone_transforms()

func bone_world(bone_name: String) -> Transform3D:
	var index := skeleton.find_bone(bone_name) if skeleton != null else -1
	return skeleton.global_transform * skeleton.get_bone_global_pose(index) if index >= 0 else global_transform
