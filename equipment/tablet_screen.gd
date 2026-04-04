extends Equipment

var ui_instance: Node = null
@export var power_cost_per_open: float = 0.2

func _ready():
	super._ready()
	
	# Pre-create the UI instance but keep it hidden
	var ui_scene = load("res://equipment/tablet_ui.tscn")
	if ui_scene:
		ui_instance = ui_scene.instantiate()
		ui_instance.visible = false
		add_child(ui_instance)

# Called by player_interact when E is held for 1 second
func interact_hold(player: Node3D):
	if is_being_placed: return

	var rv = get_connected_rv()
	if not rv:
		print("Tablet: Offline (not connected to RV).")
		return
	if rv.has_method("has_usable_power") and not rv.has_usable_power():
		print("Tablet: No power available.")
		return
	if not consume_rv_power(power_cost_per_open):
		print("Tablet: Insufficient power to boot screen.")
		return
	
	if ui_instance and not ui_instance.visible:
		# Tell the player to lock movement and camera
		if player.has_method("enter_ui_mode"):
			player.enter_ui_mode()
			
		if ui_instance.has_method("on_open"):
			ui_instance.on_open()
			
		ui_instance.visible = true
		
		# Connect the close signal from the UI if it has one
		if ui_instance.has_signal("close_requested"):
			# Disconnect first to avoid multiple connections if opened multiple times
			if ui_instance.is_connected("close_requested", Callable(self, "_on_ui_close")):
				ui_instance.disconnect("close_requested", Callable(self, "_on_ui_close"))
			
			ui_instance.connect("close_requested", Callable(self, "_on_ui_close").bind(player))

func _on_ui_close(player: Node3D):
	if ui_instance:
		ui_instance.visible = false
		
	if player and player.has_method("exit_ui_mode"):
		player.exit_ui_mode()
