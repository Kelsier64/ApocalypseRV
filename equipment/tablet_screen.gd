extends Equipment

var ui_instance: Node = null
var current_user: Node3D = null
@export var power_cost_per_open: float = 0.2

func _ready():
	super._ready()
	
	# Pre-create the UI instance but keep it hidden
	var ui_scene = load("res://equipment/tablet_ui.tscn")
	if ui_scene:
		ui_instance = ui_scene.instantiate()
		ui_instance.visible = false
		add_child(ui_instance)
		ui_instance.close_requested.connect(_close_ui)

# Called by player_interact when E is held for 1 second
func interact_hold(player: Node3D):
	if not can_operate() or not is_instance_valid(ui_instance) or ui_instance.visible:
		return
	if not player.enter_ui_mode():
		return
	if not consume_rv_power(power_cost_per_open):
		player.exit_ui_mode()
		return
	current_user = player
	player.grab_started.connect(_close_ui)
	ui_instance.on_open()
	ui_instance.visible = true

func _close_ui() -> void:
	if is_instance_valid(ui_instance):
		ui_instance.visible = false
	if is_instance_valid(current_user):
		if current_user.grab_started.is_connected(_close_ui): current_user.grab_started.disconnect(_close_ui)
		current_user.exit_ui_mode()
	current_user = null

func _on_service_stopped() -> void:
	_close_ui()

func _physics_process(_delta: float) -> void:
	if is_instance_valid(current_user):
		if not can_operate() or current_user.is_player_dead or not get_connected_rv().has_usable_power():
			_close_ui()
