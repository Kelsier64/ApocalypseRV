extends RayCast3D

@onready var player = get_parent().get_parent() # RayCast -> Camera3D -> Player

var _e_was_pressed: bool = false
var _install_timer: float = 0.0

func _physics_process(_delta):
	target_position = Vector3(0, 0, -3.0)

	var obj = get_collider() if is_colliding() else null
	var e_pressed := Input.is_physical_key_pressed(KEY_E)
	var e_just_released := not e_pressed and _e_was_pressed
	var is_holding := false

	# 1. Install held wheel: player holds Wheel item + looks at chassis + hold E 1s
	var holding_wheel: bool = player.get_active_item_name() == "Wheel"
	if e_pressed and obj and obj.has_method("install_wheel") and holding_wheel:
		_install_timer += _delta
		is_holding = true
		if _install_timer >= 1.0:
			if obj.install_wheel():
				player.consume_active_item()
			_install_timer = 0.0
	else:
		_install_timer = 0.0

	# 2. E key: hold >= 1s = interact_hold, release before 1s = interact (quick pickup)
	if e_pressed and obj and not (obj.has_method("install_wheel") and holding_wheel):
		if obj.has_method("interact_hold") and "hold_timer" in obj:
			obj.hold_timer += _delta
			is_holding = true
			if obj.hold_timer >= 1.0:
				obj.interact_hold(player)
				obj.hold_timer = 0.0
		elif obj.has_method("interact") and not _e_was_pressed:
			obj.interact(player)
			set_physics_process(false)
			await get_tree().create_timer(0.5).timeout
			set_physics_process(true)
			_e_was_pressed = true
			return

	# E released before 1s hold completes -> treat as quick pickup
	if e_just_released and obj and "hold_timer" in obj:
		if obj.hold_timer > 0.0:
			obj.hold_timer = 0.0
			if obj.has_method("interact"):
				obj.interact(player)
				set_physics_process(false)
				await get_tree().create_timer(0.5).timeout
				set_physics_process(true)
				_e_was_pressed = false
				return

	# 3. Hold F for Equipment placement (only when E not pressed)
	if not e_pressed and Input.is_physical_key_pressed(KEY_F):
		if obj and obj is Equipment and not player.is_placing_equipment():
			obj.hold_timer += _delta
			is_holding = true
			if obj.hold_timer >= 2.0:
				obj.start_placement(player)
				obj.hold_timer = 0.0

	# 4. Reset hold timers when not actively holding
	if not is_holding:
		if obj and "hold_timer" in obj:
			obj.hold_timer = 0.0

	_e_was_pressed = e_pressed
