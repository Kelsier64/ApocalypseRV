extends Node3D
## Stage 2 presentation only. No actor ownership, hits, death or music.
const MODEL_PATH := "res://assets/models/slender_speaker/slender_speaker_rigged.glb"
const CLIPS := ["idle_play", "scan", "walk", "run", "turn_left", "turn_right", "smash", "grab_miss", "grab", "hold", "lift", "crush", "retract"]
const LOOPS := ["idle_play", "scan", "walk", "run", "turn_left", "turn_right", "hold"]
const REVIEW_CLIPS := ["review_hand_open", "review_hand_fist"]
var skeleton: Skeleton3D
var animation: AnimationPlayer
var available := false
var problem := ""

func _ready() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		problem = "Rigged model is absent: " + MODEL_PATH
		return
	var resource := load(MODEL_PATH) as PackedScene
	if resource == null:
		problem = "Rigged model could not be loaded"
		return
	var offset := Node3D.new()
	offset.name = "ModelOffset"
	offset.rotation.y = PI # Imported +Z front becomes controller -Z.
	add_child(offset)
	var model := resource.instantiate()
	offset.add_child(model)
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
	if available: sample("idle_play", 0.0)

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
