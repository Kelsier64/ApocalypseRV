extends CanvasLayer

signal close_requested

@onready var content_label = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ContentLabel")
@onready var vbox = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")

var recipes = {
	"Gasoline Can": {
		"scene": "res://props/gas_can.tscn",
		"costs": {
			"Unrefined Fuel": 5,
			"Metal Parts": 2
		}
	}
}

var craft_buttons = {}
var connected_rv = null
var ui_setup_done = false

func _ready():
	var btn = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Header/CloseButton")
	if btn:
		btn.pressed.connect(_on_close_pressed)
		
	if btn and btn.is_visible_in_tree():
		btn.grab_focus()

func on_open():
	var tablet_screen = get_parent()
	var current_rv = null
	if tablet_screen and tablet_screen.has_method("get_connected_rv"):
		current_rv = tablet_screen.get_connected_rv()
		
	if current_rv != connected_rv:
		if connected_rv and connected_rv.has_signal("inventory_changed") and connected_rv.inventory_changed.is_connected(_on_inventory_changed):
			connected_rv.inventory_changed.disconnect(_on_inventory_changed)
			
		connected_rv = current_rv
		
		if connected_rv and connected_rv.has_signal("inventory_changed"):
			if not connected_rv.inventory_changed.is_connected(_on_inventory_changed):
				connected_rv.inventory_changed.connect(_on_inventory_changed)
				
	if not ui_setup_done:
		_setup_crafting_ui()
		ui_setup_done = true
		
	_update_inventory_display()
	_evaluate_craft_buttons()

func _setup_crafting_ui():
	var hs = HSeparator.new()
	vbox.add_child(hs)
	
	var craft_title = Label.new()
	craft_title.text = ">>> CRAFTING TERMINAL <<<"
	craft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(craft_title)
	
	for recipe_name in recipes.keys():
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var desc = recipe_name + " (Costs: "
		var costs = recipes[recipe_name]["costs"]
		var keys = costs.keys()
		for i in range(keys.size()):
			desc += str(costs[keys[i]]) + " " + keys[i]
			if i < keys.size() - 1: desc += ", "
		desc += ")"
		
		var lb = Label.new()
		lb.text = desc
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		
		var craft_btn = Button.new()
		craft_btn.text = " Craft "
		craft_btn.pressed.connect(func(): _craft_item(recipe_name))
		row.add_child(craft_btn)
		
		craft_buttons[recipe_name] = craft_btn
		vbox.add_child(row)

func _on_close_pressed():
	close_requested.emit()

func _on_inventory_changed(_item_name: String, _new_amount: int):
	_update_inventory_display()
	_evaluate_craft_buttons()

func _evaluate_craft_buttons():
	for recipe_name in recipes.keys():
		if craft_buttons.has(recipe_name):
			if not connected_rv:
				craft_buttons[recipe_name].disabled = true
			else:
				craft_buttons[recipe_name].disabled = not connected_rv.has_materials(recipes[recipe_name]["costs"])

func _craft_item(recipe_name: String):
	if not connected_rv: return
	
	var data = recipes[recipe_name]
	
	if not connected_rv.has_materials(data["costs"]):
		print("Tablet: Not enough materials!")
		return
		
	var stations = get_tree().get_nodes_in_group("crafting_stations")
	if stations.is_empty():
		print("Tablet: No Crafting Station found in the world!")
		return
	
	var valid_station = null
	for st in stations:
		if st.has_method("get_connected_rv") and st.get_connected_rv() == connected_rv:
			valid_station = st
			break
			
	if valid_station == null:
		print("Tablet: Crafting station is not connected to the RV!")
		return
		
	if connected_rv.deduct_materials(data["costs"]):
		valid_station.spawn_item(data["scene"])
	
func _update_inventory_display():
	if not content_label: return
	
	if not connected_rv:
		content_label.text = "\n\n[ CRITICAL ERROR ]\n\nNO CONNECTION TO MAIN RV SERVER.\n\nSYSTEMS OFFLINE."
		return
		
	var text = ">>> LOCAL RV MATERIAL INVENTORY <<<\n\n"
	var items = connected_rv.get_all_items()
	
	if items.is_empty():
		text += "  [ Inventory Empty ]\n"
	else:
		for item_name in items:
			var amount = items[item_name]
			if amount > 0:
				text += "  [ " + str(amount) + " ] " + item_name + "\n"
				
	content_label.text = text
