extends Equipment

func _ready():
	# Allow Equipment logic to initialize
	super._ready()
	
	var hopper = get_node_or_null("HopperArea")
	if hopper:
		hopper.body_entered.connect(_on_hopper_body_entered)
	else:
		push_error("Scrapper has no HopperArea!")

func _on_hopper_body_entered(body: Node3D):
	# If we are currently being moved/placed, don't recycle things
	if is_being_placed: return
	
	if body is Prop:
		recycle_prop(body)

func recycle_prop(prop: Prop):
	var rv = get_connected_rv()
	if not rv:
		print(">>> SCRAPPER OFFLINE: Not connected to RV Power!")
		# Bounce the item back out (or just don't accept it)
		prop.apply_central_impulse(Vector3(0, 5.0, 0))
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
	prop.queue_free()
