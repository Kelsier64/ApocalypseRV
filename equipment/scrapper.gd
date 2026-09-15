extends Equipment

@onready var roller1: CSGCylinder3D = $CSGCylinder3D
@onready var roller2: CSGCylinder3D = $CSGCylinder3D2

var props_being_crushed: Array[Dictionary] = []
var crush_speed: float = 0.5 # Units per second to pull down
var crush_time: float = 1.5 # Seconds to crush
var roller_spin_speed: float = 5.0 # Radians per second
var power_draw_per_second: float = 0.8
@export var queue_capacity: int = 4

func _ready():
	# Allow Equipment logic to initialize
	super._ready()
	
	var hopper = get_node_or_null("HopperArea")
	if hopper:
		hopper.body_entered.connect(_on_hopper_body_entered)
	else:
		push_error("Scrapper has no HopperArea!")

func step_work(delta: float):
	if not can_operate():
		return
	if props_being_crushed.size() > 0:
		if props_being_crushed[0].timer <= 0.0:
			if _finish_recycle(props_being_crushed[0].prop):
				props_being_crushed.pop_front()
			return
		var rv = get_connected_rv()
		if not rv:
			return
		if rv and rv.has_method("consume_power"):
			if not rv.consume_power(power_draw_per_second * minf(delta, props_being_crushed[0].timer)):
				return

		# Rotate rollers around their local Y axis (which is the cylinder's length)
		if is_instance_valid(roller1):
			roller1.rotate_object_local(Vector3.UP, roller_spin_speed * delta)
		if is_instance_valid(roller2):
			# Rotate the other way
			roller2.rotate_object_local(Vector3.UP, -roller_spin_speed * delta)
		
		# Process crushing items
		for i in range(mini(props_being_crushed.size(), 1) - 1, -1, -1):
			var data = props_being_crushed[i]
			var p: RigidBody3D = data["prop"]
			
			if is_instance_valid(p):
				# Move item down slowly relative to the scrapper's orientation
				data["local_position"].y -= crush_speed * delta
				p.global_position = to_global(data["local_position"])
				data["timer"] -= delta
				
				if data["timer"] <= 0:
					if _finish_recycle(p):
						props_being_crushed.remove_at(i)
			else:
				# Prop was destroyed elsewhere
				props_being_crushed.remove_at(i)

func _on_hopper_body_entered(body: Node3D):
	# If we are currently being moved/placed, don't recycle things
	if is_being_placed: return
	
	# Assume Prop extends RigidBody3D
	if body is Prop:
		recycle_prop(body)

func recycle_prop(prop: Prop):
	if not can_operate() or is_instance_valid(prop.processing_owner) or props_being_crushed.size() >= queue_capacity:
		return
	var rv = get_connected_rv()
	if not rv:
		print(">>> SCRAPPER OFFLINE: Not connected to RV Power!")
		# Bounce the item back out (or just don't accept it)
		prop.apply_central_impulse(Vector3(0, 5.0, 0))
		return
	if rv.has_method("has_usable_power") and not rv.has_usable_power():
		print(">>> SCRAPPER OFFLINE: No RV power available!")
		prop.apply_central_impulse(Vector3(0, 5.0, 0))
		return
		
	# Check if already being crushed
	for data in props_being_crushed:
		if data["prop"] == prop:
			return
			
	# Start crushing process
	# Freeze physics so we can manually move it down
	var physics := {"freeze": prop.freeze, "mode": prop.freeze_mode, "layer": prop.collision_layer,
		"mask": prop.collision_mask, "linear": prop.linear_velocity, "angular": prop.angular_velocity}
	prop.processing_owner = self
	prop.freeze = true
	# Disable collision so it doesn't float on rollers
	prop.collision_layer = 0
	prop.collision_mask = 0
	
	props_being_crushed.append({
		"prop": prop,
		"timer": crush_time,
		"physics": physics,
		"local_position": to_local(prop.global_position)
	})

func _physics_process(_delta: float) -> void:
	for data in props_being_crushed:
		if is_instance_valid(data.prop):
			data.prop.global_position = to_global(data.local_position)

func _on_service_stopped() -> void:
	for data in props_being_crushed:
		var prop: Prop = data.prop
		if not is_instance_valid(prop):
			continue
		prop.processing_owner = null
		prop.freeze = data.physics.freeze
		prop.freeze_mode = data.physics.mode
		prop.collision_layer = data.physics.layer
		prop.collision_mask = data.physics.mask
		prop.linear_velocity = data.physics.linear
		prop.angular_velocity = data.physics.angular
	props_being_crushed.clear()

func _finish_recycle(prop: Prop) -> bool:
	var rv := get_connected_rv()
	if rv == null:
		return false
	if not prop.has_meta("recycle_result"):
		var amounts := {}
		for material in prop.scrap_yields:
			var bounds: Vector2 = prop.scrap_yields[material]
			amounts[material] = randi_range(int(bounds.x), int(bounds.y))
		if amounts.is_empty():
			amounts[ItemNames.UNKNOWN_MATERIAL] = 1
		prop.set_meta("recycle_result", amounts)
	if not rv.deposit_materials(prop.get_meta("recycle_result")):
		return false
	prop.queue_free()
	return true
