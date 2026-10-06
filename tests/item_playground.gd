extends "res://tests/rv_interaction_playground.gd"
## Visible production Item acceptance. Fixture keys only stage observations.
var sample: Item
var support_wall: RVStructurePanel
var item_status: Label
var observer: Camera3D
var outside_view := false

func _ready() -> void:
	await super._ready()
	get_window().title = "ApocalypseRV - Unified Item Acceptance"
	for binding in [["place_equipment", KEY_F], ["drop_item", KEY_G]]:
		var key := InputEventKey.new()
		key.keycode = binding[1]
		InputMap.action_add_event(binding[0], key)
	player.inventory.items.clear()
	player.inventory.active_slot = 0
	player.refresh_inventory()
	for label in find_children("*", "Label", true, false):
		if label.get_parent() is CanvasLayer and label.position == Vector2(24, 90): label.hide()
	sample = rv.get_node("Generator") as Item
	support_wall = rv.get_node("StructureSlots").panel("right_0")
	sample.confirm_placement(Transform3D(Basis.IDENTITY, rv.to_global(Vector3(2.42, 1.35, -4))), rv, support_wall)
	sample.condition = 64.0
	var layer := CanvasLayer.new()
	add_child(layer)
	item_status = Label.new()
	item_status.position = Vector2(20, 75)
	item_status.add_theme_font_size_override("font_size", 20)
	layer.add_child(item_status)
	observer = Camera3D.new()
	add_child(observer)
	focus_item(sample)
	print("ITEM_PLAYGROUND_READY id=", sample.persistent_id, " fixed=", sample.is_fixed)

func focus_item(target: Node3D) -> void:
	var point := target.global_position
	player.global_position = Vector3(point.x + 2.0, .11, point.z + .4)
	player.look_at(Vector3(point.x, player.global_position.y, point.z))
	player.camera.look_at(point)
	player.camera.current = true
	outside_view = false

func _process(_delta: float) -> void:
	if item_status == null: return
	var data: Dictionary = player.inventory.active_item()
	var text := "ITEM: wall → fall → E pickup → F preview → place / G drop\nF2 destroy wall | F3 focus loose generator | F4 outside camera | F5 aim ground | F6 restore wall\n"
	text += "F7 focus recycler | F8 replay hold E (1.2 s)\n"
	text += "Inventory %d/6 | two hands: %s | preview: %s" % [player.inventory.items.size(), data.get("is_large", false), player.is_placing_equipment()]
	text += " | metal: %d | queue: %d" % [rv.get_item_count(ItemNames.METAL_PARTS), rv.get_node("Scrapper").props_being_crushed.size()]
	if is_instance_valid(sample): text += "\nGenerator fixed: %s | HP: %.1f | service: %s" % [sample.is_fixed, sample.current_health, sample.can_operate()]
	elif not data.is_empty(): text += "\nHeld: %s | condition: %.1f%%" % [data.name, data.state.get("condition", 100.0)]
	item_status.text = text

func _physics_process(_delta: float) -> void:
	# Locomotion is frozen for repeatable inspection, but production previews run.
	if is_instance_valid(player): player.placement.update_ghost(player)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2:
			support_wall.take_damage(999.0)
			print("ITEM_WALL_DESTROYED")
		KEY_F3:
			for child in WorldEntities.get_container(self).get_children():
				if child is Item and child.definition != null and child.definition.type_id == "generator" and not child.presentation_only:
					sample = child
					focus_item(sample)
		KEY_F4:
			outside_view = not outside_view
			if outside_view:
				observer.global_position = player.global_position + player.global_basis * Vector3(2.8, 1.8, -1.8)
				observer.look_at(player.global_position + Vector3.UP * 1.0)
				observer.current = true
			else: player.camera.current = true
		KEY_F5:
			player.camera.look_at(player.global_position - player.global_basis.z * 2.0 + Vector3.UP * .11)
		KEY_F6:
			support_wall.set_health(support_wall.max_health)
		KEY_F7:
			focus(rv.get_node("Scrapper"), Vector3(0, 1.8, 2.0))
		KEY_F8:
			Input.action_press("interact")
			await get_tree().create_timer(1.2).timeout
			Input.action_release("interact")
