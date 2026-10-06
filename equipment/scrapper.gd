extends Item

@onready var roller1: CSGCylinder3D = $CSGCylinder3D
@onready var roller2: CSGCylinder3D = $CSGCylinder3D2

var props_being_crushed: Array[Dictionary] = []
var crush_speed: float = 0.5 # Units per second to pull down
var crush_time: float = 1.5 # Seconds to crush
var roller_spin_speed: float = 5.0 # Radians per second
var power_draw_per_second: float = 0.8
@export var queue_capacity: int = 4

func _ready():
	# Allow Item logic to initialize
	super._ready()
	if presentation_only: return
	
	var hopper = get_node_or_null("HopperArea")
	if hopper:
		hopper.collision_mask |= 2 | 128 # Pickup proxies and articulated corpse bones.
		hopper.body_entered.connect(_on_hopper_body_entered)
	else:
		push_error("Scrapper has no HopperArea!")

func step_work(delta: float):
	for index in range(props_being_crushed.size() - 1, -1, -1):
		if not is_instance_valid(props_being_crushed[index].prop): props_being_crushed.remove_at(index)
	if not can_operate():
		return
	# Retry overlapping inputs after power/queue readiness changes, or after a
	# dying actor transfers already-overlapping physical bones to a corpse.
	var source := get_connected_rv()
	if props_being_crushed.size() < queue_capacity and (not source.has_method("has_usable_power") or source.has_usable_power()):
		for body in $HopperArea.get_overlapping_bodies():
			_on_hopper_body_entered(body)
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
				# Item was destroyed elsewhere
				props_being_crushed.remove_at(i)

func _on_hopper_body_entered(body: Node3D):
	# If we are currently being moved/placed, don't recycle things
	if is_being_placed: return
	
	# Assume Item extends RigidBody3D
	if body is Item:
		recycle_prop(body)
	elif body is PhysicalBone3D:
		# A limb may enter while the pelvis pickup proxy remains outside the bin.
		# Resolve only corpse-owned bones; living actors and loose limbs are not inputs.
		var ancestor: Node = body.get_parent()
		while ancestor != null:
			if ancestor is CorpseProp:
				if not ancestor.held: recycle_prop(ancestor)
				return
			ancestor = ancestor.get_parent()

func recycle_prop(prop: Item):
	if prop == self or prop.is_ancestor_of(self) or is_ancestor_of(prop): return
	if prop.presentation_only or prop.is_fixed or prop.is_being_placed: return
	if prop is CorpseProp and prop.held: return
	if prop.is_queued_for_deletion() or not can_operate() or is_instance_valid(prop.processing_owner) or props_being_crushed.size() >= queue_capacity:
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
			
	# Stop device services before accepting a loose item; this releases nested inputs.
	prop._stop_service_once()
	# Start crushing process
	# Freeze physics so we can manually move it down
	var physics := {"freeze": prop.freeze, "mode": prop.freeze_mode, "layer": prop.collision_layer,
		"mask": prop.collision_mask, "linear": prop.linear_velocity, "angular": prop.angular_velocity}
	prop.processing_owner = self
	prop.freeze = true
	# Disable collision so it doesn't float on rollers
	prop.collision_layer = 0
	prop.collision_mask = 0
	if prop.has_method("set_processing"): prop.call_deferred("set_processing", true)
	
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
		if not is_instance_valid(data.prop):
			continue
		var prop: Item = data.prop
		prop.processing_owner = null
		prop.freeze = data.physics.freeze
		prop.freeze_mode = data.physics.mode
		prop.collision_layer = data.physics.layer
		prop.collision_mask = data.physics.mask
		prop.linear_velocity = data.physics.linear
		prop.angular_velocity = data.physics.angular
		if prop.has_method("set_processing"): prop.call_deferred("set_processing", false)
	props_being_crushed.clear()

func _finish_recycle(prop: Item) -> bool:
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

func capture_service_state() -> Dictionary:
	var inputs: Array[Dictionary] = []
	for entry in props_being_crushed:
		if is_instance_valid(entry.prop):
			inputs.append({"scene": entry.prop.scene_file_path, "state": entry.prop.capture_item_state(),
				"timer": entry.timer, "local_position": entry.local_position, "physics": entry.physics.duplicate(true)})
	return {"inputs": inputs}

func restore_service_state(state: Dictionary) -> void:
	for saved: Dictionary in state.get("inputs", []):
		var scene := SaveSceneCatalog.resolve(saved.scene, "item")
		if scene == null: continue
		var input: Item = scene.instantiate()
		input.restore_item_state(saved.state)
		var container := WorldEntities.get_container(self)
		if container == null:
			input.free()
			continue
		container.add_child(input)
		input.processing_owner = self
		input.freeze = true
		input.collision_layer = 0
		input.collision_mask = 0
		input.global_position = to_global(saved.local_position)
		if input.has_method("set_processing"): input.set_processing(true)
		props_being_crushed.append({"prop": input, "timer": saved.timer,
			"local_position": saved.local_position, "physics": saved.physics.duplicate(true)})

func can_accept_held_item(player: Node3D) -> bool:
	if not can_operate() or props_being_crushed.size() >= queue_capacity: return false
	if not player.can_use_hands(2) or not player.inventory.is_holding_large_item(): return false
	if player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL: return false
	var source := get_connected_rv()
	if source == null or not source.has_usable_power(): return false
	var record: Dictionary = player.inventory.active_item()
	return SaveSceneCatalog.resolve(record.get("scene_path", ""), "item") != null

func accept_held_item(player: Node3D) -> String:
	if not can_accept_held_item(player): return "無法投入：分解機未就緒、佇列已滿，或需要雙手大型物品"
	var record: Dictionary = player.inventory.active_item().duplicate(true)
	var scene := SaveSceneCatalog.resolve(record.scene_path, "item")
	var input: Item = scene.instantiate()
	input.restore_item_state(record.state)
	input.item_name = record.name
	input.is_large = record.is_large
	input.is_fixed = false
	var container := WorldEntities.get_container(self)
	if container == null:
		input.free()
		return "分解機所在世界無法接收物品"
	container.add_child(input)
	input.global_position = to_global(Vector3(0, 1.5, 0))
	recycle_prop(input)
	if input.processing_owner != self:
		input.queue_free()
		return "物品未投入，請稍後再試"
	player.consume_active_item()
	return "已投入大型物品，等待分解"
