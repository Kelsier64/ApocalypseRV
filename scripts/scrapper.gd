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
	var item = prop.item_name
	var received = ""
	
	# Simple recipe logic
	if item == "Scrap Metal":
		received = "3x Metal Parts"
	elif item == "Oil Barrel":
		received = "15x Unrefined Fuel"
	else:
		received = "1x Unknown Material"
		
	print(">>> SCRAPPER: Recycled [", item, "] -> Output: [", received, "]")
	
	# Destroy the prop
	prop.queue_free()
