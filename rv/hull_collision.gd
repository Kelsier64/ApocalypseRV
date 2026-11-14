extends RefCounted
class_name RVHullCollision

var _parts: Dictionary = {}
var _slot_layout := RVStructureSlots.layout()
var _wheel_shapes: Array[CollisionShape3D] = []

func install_wheel_guards(vehicle: Chassis) -> void:
	for i in vehicle.WHEEL_SLOTS.size():
		var proxy := CollisionShape3D.new()
		var sidewall := BoxShape3D.new()
		sidewall.size = Vector3(0.17, vehicle.WHEEL_RADIUS * 0.65, vehicle.WHEEL_RADIUS * 0.7)
		proxy.shape = sidewall
		var hard_point: Vector3 = vehicle.WHEEL_SLOTS[i].position
		proxy.position = hard_point + Vector3(signf(hard_point.x) * vehicle.WHEEL_WIDTH * 0.5, -0.30, 0)
		proxy.set_meta(&"rv_wheel_slot", i)
		proxy.disabled = true
		vehicle.add_child(proxy)
		_wheel_shapes.append(proxy)

func sync(vehicle: Chassis) -> void:
	var slots := vehicle.get_node_or_null("StructureSlots") as RVStructureSlots
	if slots == null: return
	for i in _wheel_shapes.size():
		var missing := vehicle.installed_wheels[i] == null
		if _wheel_shapes[i].disabled != missing: _wheel_shapes[i].disabled = missing
	for slot in _slot_layout:
		var id: String = slot.id
		var part := slots.panel(id)
		if _parts.has(id) and _parts[id].part.get_ref() != part:
			for proxy: CollisionShape3D in _parts[id].shapes:
				proxy.disabled = true
				proxy.queue_free()
			_parts.erase(id)
		if part == null: continue
		if not _parts.has(id):
			var shapes: Array[CollisionShape3D] = []
			for source in part.get_children():
				if not source is CollisionShape3D or not source.shape is BoxShape3D: continue
				var box: BoxShape3D = source.shape.duplicate()
				# Keep the proxy inside the gameplay collider, including around hatch openings.
				box.size -= Vector3.ONE * 0.035
				var proxy := CollisionShape3D.new()
				proxy.shape = box
				proxy.transform = part.transform * source.transform
				proxy.set_meta(&"rv_hull_slot", id)
				proxy.disabled = true
				vehicle.add_child(proxy)
				shapes.append(proxy)
			_parts[id] = {"part": weakref(part), "shapes": shapes}
		var proxy_index := 0
		for source in part.get_children():
			if not source is CollisionShape3D or not source.shape is BoxShape3D: continue
			var proxy: CollisionShape3D = _parts[id].shapes[proxy_index]
			proxy_index += 1
			var enabled := not part.is_destroyed
			if source.has_meta(&"door_leaf"):
				# The real leaf still handles interaction and swept blockers.
				enabled = enabled and part.boarding_leaf_closed(source.get_meta(&"door_leaf"))
			if proxy.disabled == enabled: proxy.disabled = not enabled

func disable_slot(slot: String) -> void:
	if not _parts.has(slot): return
	for proxy: CollisionShape3D in _parts[slot].shapes:
		proxy.disabled = true

static func slot_for(vehicle: Chassis, index: int) -> String:
	var owner := shape_node(vehicle, index)
	return owner.get_meta(&"rv_hull_slot", "") if owner else ""

static func shape_node(vehicle: Chassis, index: int) -> Node:
	if index < 0: return null
	return vehicle.shape_owner_get_owner(vehicle.shape_find_owner(index)) as Node
