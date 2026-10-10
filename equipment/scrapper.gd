extends Item
const FEED = preload("res://equipment/scrapper_feed_motion.gd")

@onready var roller1: CSGCylinder3D = $CSGCylinder3D
@onready var roller2: CSGCylinder3D = $CSGCylinder3D2

var props_being_crushed: Array[Dictionary] = []
var crush_time: float = 1.5 # Seconds to crush
var roller_spin_speed: float = 5.0 # Radians per second
var power_draw_per_second: float = 0.8
@export var queue_capacity: int = 4

# A signal reserves the actor/slot before deferred deaths mutate Jolt bodies.
const LIVING_OWNER := &"scrapper_living_owner"
var _pending_living: Dictionary = {}
var crush_effect: Node3D

func _ready():
	# Allow Item logic to initialize
	super._ready()
	if presentation_only: return
	
	var hopper = get_node_or_null("HopperArea")
	if hopper:
		hopper.collision_mask |= 1 | 2 | 128 # Actors, pickup proxies and articulated bones.
		hopper.body_entered.connect(_on_hopper_body_entered)
	else:
		push_error("Scrapper has no HopperArea!")
	crush_effect = preload("res://equipment/scrapper_crush_effect.gd").new()
	crush_effect.name = "CrushEffect"
	add_child(crush_effect)

func step_work(delta: float):
	for index in range(props_being_crushed.size() - 1, -1, -1):
		if not is_instance_valid(props_being_crushed[index].prop): props_being_crushed.remove_at(index)
	if not can_operate():
		_stop_crush_effect()
		return
	# Retry overlapping inputs after power/queue readiness changes, or after a
	# dying actor transfers already-overlapping physical bones to a corpse.
	var source := get_connected_rv()
	if props_being_crushed.size() < queue_capacity and (not source.has_method("has_usable_power") or source.has_usable_power()):
		for body in $HopperArea.get_overlapping_bodies():
			_on_hopper_body_entered(body)
	if delta <= 0:
		_stop_crush_effect()
		return
	if props_being_crushed.is_empty() and _step_living_feed(delta): return
	if props_being_crushed.size() > 0:
		var first: Dictionary = props_being_crushed[0]
		if first.feed == null:
			if first.prop is CorpseProp and not first.prop.initialized: return
			var motion := FEED.new()
			if not motion.setup(first.prop,self,first.get("saved_feed",{})):
				_on_service_stopped()
				return
			first.feed = motion
		if props_being_crushed[0].timer <= 0.0 and first.feed.complete:
			_stop_crush_effect()
			if _finish_recycle(props_being_crushed[0].prop):
				props_being_crushed.pop_front()
			return
		var rv = get_connected_rv()
		if not rv:
			_stop_crush_effect()
			return
		if rv and rv.has_method("consume_power"):
			if not rv.consume_power(power_draw_per_second * (delta if first.feed.physical else minf(delta, props_being_crushed[0].timer))):
				_stop_crush_effect()
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
				data["timer"] = maxf(0.0,data["timer"] - delta)
				data.feed.advance(p,self,clampf(1.0-data.timer/maxf(crush_time,.001),0,1),delta)
				data.local_position = to_local(p.global_position)
				if is_instance_valid(crush_effect):
					crush_effect.advance_work(delta, p is CorpseProp, _crush_contact(data.local_position), clampf(1.0 - data.timer / maxf(crush_time, .001), 0, 1), p.get_instance_id())
				
				if data["timer"] <= 0 and data.feed.complete:
					if _finish_recycle(p):
						props_being_crushed.remove_at(i)
			else:
				# Item was destroyed elsewhere
				props_being_crushed.remove_at(i)

	else:
		_stop_crush_effect()

func _crush_contact(local_input: Vector3) -> Vector3:
	return Vector3(clampf(local_input.x, -.12, .12), .72, clampf(local_input.z, -.18, .18))

func _stop_crush_effect(clear_particles := false) -> void:
	if is_instance_valid(crush_effect): crush_effect.stop(clear_particles)

func _on_hopper_body_entered(body: Node3D):
	# If we are currently being moved/placed, don't recycle things
	if is_being_placed: return
	
	# Assume Item extends RigidBody3D
	if body is Item:
		var local := to_local(body.global_position)
		if absf(local.x) <= .30 and absf(local.z) <= .30 and (body is CorpseProp or FEED.admissible(body,self)): recycle_prop(body)
	elif body is PhysicalBone3D:
		# Resolve the actual owner of a limb; cosmetic loose parts have no yield.
		var ancestor: Node = body.get_parent()
		while ancestor != null:
			if ancestor is CorpseProp:
				if not ancestor.held: recycle_prop(ancestor)
				return
			if ancestor is Monster or ancestor.is_in_group(Groups.PLAYER):
				_queue_living_input(ancestor)
				return
			ancestor = ancestor.get_parent()
	elif body is Monster or body.is_in_group(Groups.PLAYER):
		_queue_living_input(body)

func is_powered_feed() -> bool:
	if is_being_placed or not can_operate(): return false
	var source := get_connected_rv()
	return is_instance_valid(source) and source.has_usable_power()

func _living_overlaps_feed(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not WorldEntities.same_world(self, actor): return false
	var shape_node: CollisionShape3D = $HopperArea.get_child(0)
	var half_size: Vector3 = shape_node.shape.size * .5
	for body in $HopperArea.get_overlapping_bodies():
		if body != actor and not actor.is_ancestor_of(body): continue
		# A capsule grazing the outside wall is not a jump into the opening.
		var local: Vector3 = shape_node.to_local(body.global_position)
		if absf(local.x) <= half_size.x and absf(local.z) <= half_size.z: return true
	return false

func _queue_living_input(actor: Node3D) -> void:
	if not is_powered_feed() or not actor.can_process() or not _living_overlaps_feed(actor): return
	if (actor is Monster and actor.is_dead) or (actor.is_in_group(Groups.PLAYER) and actor.is_player_dead): return
	var id := actor.get_instance_id()
	if _pending_living.has(id) or props_being_crushed.size() + _pending_living.size() >= queue_capacity: return
	var claim: Variant = actor.get_meta(LIVING_OWNER) if actor.has_meta(LIVING_OWNER) else null
	if claim is WeakRef and is_instance_valid(claim.get_ref()): return
	actor.set_meta(LIVING_OWNER, weakref(self))
	_pending_living[id] = {"actor": weakref(actor), "killed": false}
	_start_living_input.call_deferred(id)

func _release_living_input(id: int) -> void:
	if not _pending_living.has(id): return
	var actor: Node = _pending_living[id].actor.get_ref()
	if is_instance_valid(actor):
		var claim: Variant = actor.get_meta(LIVING_OWNER) if actor.has_meta(LIVING_OWNER) else null
		if claim is WeakRef and claim.get_ref() == self: actor.remove_meta(LIVING_OWNER)
	_pending_living.erase(id)

func _start_living_input(id: int) -> void:
	if not _pending_living.has(id): return
	var actor: Node3D = _pending_living[id].actor.get_ref()
	if not is_powered_feed() or props_being_crushed.size() + _pending_living.size() > queue_capacity or not _living_overlaps_feed(actor) or not actor.can_process():
		_release_living_input(id)
		return
	var killed := false
	if actor.is_in_group(Groups.PLAYER) and actor.has_method("crush_in_scrapper"):
		killed = actor.crush_in_scrapper(self)
	elif actor is Monster and not actor.is_dead:
		actor.die() # Preserve special deaths (including the oil-barrel explosion).
		killed = actor.is_dead # Invincible actors may reject death.
	if killed and actor.has_method("sever_scrapper_part"):
		_pending_living[id].elapsed = 0.0
		_pending_living[id].cooldown = .12
		_pending_living[id].cut_pending = false
	if not killed:
		_release_living_input(id)
		return
	_pending_living[id].killed = true
	_finish_living_input.call_deferred(id)

func _finish_living_input(id: int) -> void:
	if not _pending_living.has(id) or not _pending_living[id].killed: return
	var actor: Node3D = _pending_living[id].actor.get_ref()
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not WorldEntities.same_world(self, actor) or not can_operate():
		_release_living_input(id)
		return
	if not is_powered_feed(): return
	var corpse: CorpseProp
	if actor.has_method("release_death_corpse"):
		if not actor.is_player_dead:
			_release_living_input(id)
			return
		if not actor.ragdoll_control.active: return
		for part: StringName in PlayerBodyState.PARTS:
			if actor.body_state.has_part(part): return
		corpse = actor.release_death_corpse()
	elif actor is Raker:
		if not actor.ragdoll.active: return
		actor._ensure_corpse()
		corpse = actor.corpse_prop
	_release_living_input(id)
	if is_instance_valid(corpse): recycle_prop(corpse)

func _step_living_feed(delta: float) -> bool:
	for id: int in _pending_living.keys():
		var entry: Dictionary = _pending_living[id]
		var actor: Node3D = entry.actor.get_ref()
		if not entry.killed or not is_instance_valid(actor) or not actor.has_method("sever_scrapper_part") or not actor.ragdoll_control.active: continue
		if delta <= 0 or not is_powered_feed(): return true
		if not get_connected_rv().consume_power(power_draw_per_second*delta): return true
		if not entry.get("tipped",false):
			actor.ragdoll_control.bodies.pelvis.angular_velocity += global_basis*Vector3(0,0,2.4)
			entry.tipped = true
		entry.elapsed += delta
		entry.cooldown -= delta
		if entry.elapsed > 3.0:
			_release_living_input(id) # A genuinely jammed body returns to ordinary death.
			return false
		actor.ragdoll_control.remaining = maxf(actor.ragdoll_control.remaining,1.75)
		for bone: PhysicalBone3D in actor.ragdoll_control.bodies.values():
			var target := to_global(Vector3(0,.48,0))
			var pull := (target-bone.global_position).limit_length(1.0)*bone.mass*16.0-bone.linear_velocity*bone.mass*3.0
			bone.apply_central_impulse(pull*delta)
		roller1.rotate_object_local(Vector3.UP,roller_spin_speed*delta)
		roller2.rotate_object_local(Vector3.UP,-roller_spin_speed*delta)
		crush_effect.advance_work(delta,true,Vector3(0,.72,0),entry.elapsed/3.0,id)
		if entry.cut_pending or entry.cooldown > 0: return true
		var contact: StringName = actor.scrapper_contact_part(self)
		if contact != &"":
			entry.cut_pending = true
			_cut_living_part.call_deferred(id,contact)
		return true
	return false

func _cut_living_part(id: int, part: StringName) -> void:
	if not _pending_living.has(id): return
	var actor: Node3D = _pending_living[id].actor.get_ref()
	if is_instance_valid(actor) and is_powered_feed() and WorldEntities.same_world(self,actor): actor.sever_scrapper_part(part,self)
	_pending_living[id].cut_pending = false
	_pending_living[id].cooldown = .15
	_finish_living_input(id)

func recycle_prop(prop: Item):
	if prop == self or prop.is_ancestor_of(self) or is_ancestor_of(prop): return
	if prop.presentation_only or prop.is_fixed or prop.is_being_placed: return
	if prop is CorpseProp and prop.held: return
	if not prop is CorpseProp and not FEED.fits(prop,self): return
	if prop.is_queued_for_deletion() or not can_operate() or is_instance_valid(prop.processing_owner) or props_being_crushed.size() + _pending_living.size() >= queue_capacity:
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
		"local_position": to_local(prop.global_position), "feed": null
	})

func _physics_process(_delta: float) -> void:
	if not is_powered_feed() or (props_being_crushed.is_empty() and _pending_living.is_empty()) or (not props_being_crushed.is_empty() and props_being_crushed[0].timer <= 0 and (props_being_crushed[0].feed == null or props_being_crushed[0].feed.complete)): _stop_crush_effect()
	for id: int in _pending_living.keys():
		_finish_living_input(id)
	for data in props_being_crushed:
		if is_instance_valid(data.prop):
			if data.feed != null and data.feed.physical: continue
			if data.feed != null: data.prop.global_transform = global_transform * data.feed.pose
			elif not data.get("saved_feed",{}).is_empty(): data.prop.global_transform = global_transform*data.saved_feed.pose
			else: data.prop.global_position = to_global(data.local_position)

func _on_service_stopped() -> void:
	_stop_crush_effect(true)
	for id: int in _pending_living.keys(): _release_living_input(id)
	for data in props_being_crushed:
		if not is_instance_valid(data.prop):
			continue
		var prop: Item = data.prop
		if data.feed != null: data.feed.release(prop,self)
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
	if is_instance_valid(crush_effect): crush_effect.impact(prop is CorpseProp, _crush_contact(to_local(prop.global_position)))
	for entry: Dictionary in props_being_crushed:
		if entry.prop == prop and entry.feed != null: FEED.restore_cut(entry.feed.surfaces)
	prop.queue_free()
	return true

func capture_service_state() -> Dictionary:
	var inputs: Array[Dictionary] = []
	for entry in props_being_crushed:
		if is_instance_valid(entry.prop):
			var input := {"scene": entry.prop.scene_file_path, "state": entry.prop.capture_item_state(),
				"timer": maxf(0,entry.timer), "local_position": entry.local_position, "physics": entry.physics.duplicate(true)}
			if entry.feed != null: input.feed = entry.feed.capture()
			inputs.append(input)
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
		if saved.has("feed"): input.global_transform = global_transform*saved.feed.pose
		else: input.global_position = to_global(saved.local_position)
		if input.has_method("set_processing"): input.set_processing(true)
		props_being_crushed.append({"prop": input, "timer": saved.timer,
			"local_position": saved.local_position, "physics": saved.physics.duplicate(true), "feed": null, "saved_feed": saved.get("feed",{})})

func can_accept_held_item(player: Node3D) -> bool:
	if not can_operate() or props_being_crushed.size() + _pending_living.size() >= queue_capacity: return false
	if not player.can_use_hands(2) or not player.inventory.is_holding_large_item(): return false
	if player.is_gameplay_input_blocked() or player.get_player_mode() != player.PlayerMode.NORMAL: return false
	var source := get_connected_rv()
	if source == null or not source.has_usable_power(): return false
	var record: Dictionary = player.inventory.active_item()
	var scene := SaveSceneCatalog.resolve(record.get("scene_path", ""), "item")
	if scene == null: return false
	if scene.resource_path == "res://props/corpse.tscn": return true
	var probe: Node3D = scene.instantiate()
	var size: Vector3 = FEED.rotated_box(FEED.geometry_bounds(probe),probe.basis).size
	probe.free()
	return size.x <= FEED.HALF_OPENING*2 and size.z <= FEED.HALF_OPENING*2

func accept_held_item(player: Node3D) -> String:
	if not can_accept_held_item(player): return "無法投入：分解機未就緒、佇列已滿、物品尺寸超過入口，或需要雙手大型物品"
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
	input.global_transform = global_transform * Transform3D(input.basis,Vector3(0,1.5,0))
	recycle_prop(input)
	if input.processing_owner != self:
		input.queue_free()
		return "物品未投入，請稍後再試"
	player.consume_active_item()
	return "已投入大型物品，等待分解"
