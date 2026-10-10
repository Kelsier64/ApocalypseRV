extends RigidBody3D
class_name RVStructurePanel
## Fixed independently damageable vehicle part. Deliberately not an Item.
@export var definition: RVStructureDefinition
@export var equipment_name: String = "車體結構"
@export var structure_kind: String = ""
@export var mount_slot: String = ""
var current_health: float = 120.0
var max_health: float = 120.0
var is_destroyed: bool = false
signal removing
signal damaged
signal damage_applied(amount: float)
signal availability_changed

func _ready() -> void:
	if definition:
		equipment_name = definition.display_name
		max_health = definition.health
		mass = definition.weight
		structure_kind = definition.slot_kind
	current_health = max_health
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 0
	add_to_group(Groups.MONSTER_DAMAGEABLE)
	var wear := Node.new()
	wear.name = "PanelWear"
	wear.set_script(load("res://rv/panel_wear.gd"))
	add_child(wear)
	if structure_kind == "roof":
		var air := Node3D.new()
		air.name = "CabinAir"
		air.set_script(load("res://rv/cabin_air.gd"))
		add_child(air)
	call_deferred("_connect_structure")

func _connect_structure() -> void:
	var rv := get_connected_rv()
	if rv == null: return
	add_collision_exception_with(rv)
	var slots := rv.get_node_or_null("StructureSlots")
	if slots: slots.register_panel(self)

func get_connected_rv() -> Node3D:
	return RVConnection.resolve(get_parent())

func can_operate() -> bool:
	return not is_destroyed and current_health > 0.0 and get_connected_rv() != null

func take_damage(amount: float) -> void:
	if amount <= 0.0 or not is_finite(amount) or is_destroyed: return
	damaged.emit()
	var previous_health := current_health
	set_health(maxf(0.0, current_health - amount))
	damage_applied.emit(previous_health - current_health)

## Construction/snapshot API; deliberately no repair_health method for H input.
func set_health(value: float) -> void:
	var was_destroyed := is_destroyed
	current_health = clampf(value, 0.0, max_health)
	is_destroyed = current_health <= 0.0
	if is_destroyed and not was_destroyed:
		removing.emit()
		_on_service_stopped()
	visible = not is_destroyed
	collision_layer = 0 if is_destroyed else 1
	for child in get_children():
		if child is CollisionShape3D: child.set_deferred("disabled", is_destroyed)
	if is_destroyed:
		remove_from_group(Groups.MONSTER_DAMAGEABLE)
	elif not is_in_group(Groups.MONSTER_DAMAGEABLE):
		add_to_group(Groups.MONSTER_DAMAGEABLE)
	availability_changed.emit()

func _on_service_stopped() -> void:
	pass

func dependent_names() -> PackedStringArray:
	var names := PackedStringArray()
	var rv := get_connected_rv()
	if rv == null: return names
	for device in rv.get_equipment():
		var cursor: Node = device.mount_support
		var seen: Array[Node] = []
		while is_instance_valid(cursor) and not seen.has(cursor):
			if cursor == self:
				names.append(device.equipment_name)
				break
			seen.append(cursor)
			cursor = cursor.mount_support if cursor is Item else null
	return names

func dependent_summary() -> String:
	var names := dependent_names()
	return "無附掛設備" if names.is_empty() else "附掛設備：" + "、".join(names)

func get_interaction_prompt(_player: Node3D) -> String:
	return "%s｜耐久 %.0f / %.0f\n請使用車載平板維修或改裝\n%s" % [equipment_name, current_health, max_health, dependent_summary()]

func get_placement_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for child in get_children():
		if child is CollisionShape3D and child.shape:
			var part: AABB = child.transform * child.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(part) if found else part
			found = true
	return bounds
