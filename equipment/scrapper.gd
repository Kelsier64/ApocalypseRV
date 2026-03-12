extends Equipment

@onready var roller1: CSGCylinder3D = $CSGCylinder3D
@onready var roller2: CSGCylinder3D = $CSGCylinder3D2

var props_being_crushed: Array[Dictionary] = []
var crush_speed: float = 0.5 # Units per second to pull down
var crush_time: float = 1.5 # Seconds to crush
var roller_spin_speed: float = 5.0 # Radians per second

func _ready():
	# Allow Equipment logic to initialize
	super._ready()
	
	var hopper = get_node_or_null("HopperArea")
	if hopper:
		hopper.body_entered.connect(_on_hopper_body_entered)
	else:
		push_error("Scrapper has no HopperArea!")

func _process(delta: float):
	if props_being_crushed.size() > 0:
		# Rotate rollers around their local Y axis (which is the cylinder's length)
		if is_instance_valid(roller1):
			roller1.rotate_object_local(Vector3.UP, roller_spin_speed * delta)
		if is_instance_valid(roller2):
			# Rotate the other way
			roller2.rotate_object_local(Vector3.UP, -roller_spin_speed * delta)
		
		# Process crushing items
		for i in range(props_being_crushed.size() - 1, -1, -1):
			var data = props_being_crushed[i]
			var p: RigidBody3D = data["prop"]
			
			if is_instance_valid(p):
				# Move item down slowly relative to the scrapper's orientation
				var down_dir = -global_transform.basis.y.normalized()
				p.global_position += down_dir * crush_speed * delta
				data["timer"] -= delta
				
				if data["timer"] <= 0:
					_finish_recycle(p)
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
	var rv = get_connected_rv()
	if not rv:
		print(">>> SCRAPPER OFFLINE: Not connected to RV Power!")
		# Bounce the item back out (or just don't accept it)
		prop.apply_central_impulse(Vector3(0, 5.0, 0))
		return
		
	# Check if already being crushed
	for data in props_being_crushed:
		if data["prop"] == prop:
			return
			
	# Start crushing process
	# Freeze physics so we can manually move it down
	prop.freeze = true
	# Disable collision so it doesn't float on rollers
	prop.collision_layer = 0
	prop.collision_mask = 0
	
	props_being_crushed.append({
		"prop": prop,
		"timer": crush_time
	})

func _finish_recycle(prop: Prop):
	var rv = get_connected_rv()
	if not rv:
		if is_instance_valid(prop):
			prop.queue_free()
		return
		
	var item = prop.item_name
	var yield_text = ""
	
	if prop.get("scrap_yields") and prop.scrap_yields.size() > 0:
		for mat_name in prop.scrap_yields:
			var range_vec = prop.scrap_yields[mat_name]
			# Ensure we are rounding correctly if they pass floats in editor by accident
			var min_qty = int(range_vec.x)
			var max_qty = int(range_vec.y)
			
			if max_qty > 0:
				var amount = randi_range(min_qty, max_qty)
				if amount > 0:
					rv.add_item(mat_name, amount)
					if yield_text != "": yield_text += ", "
					yield_text += str(amount) + "x " + mat_name
	else:
		# Fallback if unconfigured
		rv.add_item("Unknown Material", 1)
		yield_text = "1x Unknown Material"
	
	print(">>> SCRAPPER: Recycled [", item, "] -> ", yield_text)
	
	# Destroy the prop
	if is_instance_valid(prop):
		prop.queue_free()
