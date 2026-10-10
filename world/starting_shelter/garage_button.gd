extends StaticBody3D
const READY_COLOR := Color(0.2, 0.65, 0.3)
const MOVING_COLOR := Color(0.95, 0.56, 0.12)
const STARTED_COLOR := Color(0.2, 0.55, 0.9)
const SEALED_COLOR := Color(0.75, 0.16, 0.12)
const PRESS_DEPTH := 0.026
var run: Node
var _button: MeshInstance3D
var _lamp: MeshInstance3D
var _rest_position: Vector3
var _press_tween: Tween
var _color_tween: Tween

func configure(controller: Node) -> void:
	if is_instance_valid(run) and run.phase_changed.is_connected(_on_phase_changed):
		run.phase_changed.disconnect(_on_phase_changed)
	run = controller
	if _button == null:
		_button = get_node("Visuals/Button")
		_lamp = get_node("Visuals/StatusLamp")
		_rest_position = _button.position
		_button.material_override = _button.material_override.duplicate()
		_lamp.material_override = _lamp.material_override.duplicate()
	run.phase_changed.connect(_on_phase_changed)
	sync_phase()

func sync_phase() -> void:
	if _press_tween: _press_tween.kill()
	if _color_tween: _color_tween.kill()
	_button.position = _rest_position
	_set_color(_phase_color(run.phase))

func _phase_color(phase: String) -> Color:
	match phase:
		"preparing": return READY_COLOR
		"opening", "closing": return MOVING_COLOR
		"started": return STARTED_COLOR
		_: return SEALED_COLOR

func _set_color(color: Color) -> void:
	for mesh in [_button, _lamp]:
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color = color
		material.emission = color

func _on_phase_changed(phase: String) -> void:
	if _color_tween: _color_tween.kill()
	_color_tween = create_tween()
	var material := _button.material_override as StandardMaterial3D
	_color_tween.tween_method(_set_color, material.albedo_color, _phase_color(phase), 0.16)
	if phase != "opening": return
	if _press_tween: _press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(_button, "position", _rest_position + Vector3(0, 0, PRESS_DEPTH), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_interval(0.08)
	_press_tween.tween_property(_button, "position", _rest_position, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func get_interaction_prompt(_player: Node3D) -> String:
	if not is_instance_valid(run): return ""
	match run.phase:
		"preparing": return "啟程按鈕｜E 開啟車庫並出發\n車輛離開後大門永久封閉，留下的物資將無法取回"
		"opening": return "車庫大門開啟中"
		"started": return "旅程已開始｜請駕駛 RV 駛離車庫\n離開後大門永久封閉"
		"closing": return "車庫大門正在封閉｜請保持距離"
		_: return "車庫已永久封閉"

func interact(player: Node3D) -> String:
	if not is_instance_valid(run): return ""
	return run.begin_run(player)
