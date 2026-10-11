extends Node
class_name PlayerWeapon
## Inventory owns ammunition. This controller owns only transient weapon actions.
var actor: CharacterBody3D
var aim_weight := 0.0
var reload_remaining := 0.0
var recoil := 0.0
var _cooldown := 0.0
var _reload_id := ""
var _fire_down := false
var _owns_fov := false
var _hud_signature := ""

func _ready() -> void:
	actor = get_parent() as CharacterBody3D
	process_physics_priority = 1
	set_physics_process(actor != null)

func _physics_process(delta: float) -> void:
	advance(delta)

func can_use() -> bool:
	if not is_instance_valid(actor) or actor.is_gameplay_input_blocked(): return false
	if actor.get_player_mode() != actor.PlayerMode.NORMAL or not actor.can_use_hands(): return false
	if actor.locomotion_state != actor.LocomotionState.NORMAL: return false
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	# Movement spends the final stamina before assigning its sprint velocity.
	# Use that actual speed, so exhaustion cannot unlock this last sprint frame.
	if Input.is_action_pressed("sprint") and speed > actor.SPEED + .01: return false
	if actor.is_crawling() and (speed > .06 or actor.crawl_transition_remaining > 0.0): return false
	return actor.inventory.active_item().get("scene_path", "") == PistolRules.PISTOL_SCENE

func handle_input(event: InputEvent) -> void:
	if event.is_action_released("weapon_fire"):
		_fire_down = false
	if event.is_action_pressed("weapon_fire") and not event.is_echo():
		if not _fire_down:
			_fire_down = true
			try_fire()
	if event.is_action_pressed("weapon_reload") and not event.is_echo():
		start_reload()

func try_fire() -> bool:
	if not can_use() or reload_remaining > 0.0 or _cooldown > 0.0: return false
	var item: Dictionary = actor.inventory.active_item()
	var state: Dictionary = item.get("state", {})
	var pistol: Dictionary = state.get("pistol", {})
	var rounds := int(pistol.get("loaded_rounds", 0))
	_cooldown = PistolRules.SHOT_INTERVAL
	if rounds <= 0:
		_play("play_empty")
		return false
	pistol["loaded_rounds"] = rounds - 1
	state["pistol"] = pistol
	item["state"] = state
	actor.inventory.items[actor.inventory.active_slot] = item
	_sync_preview()
	recoil = 1.0
	_play("play_shot")
	_trace_shot()
	_refresh_hud()
	return true

func start_reload() -> bool:
	if not can_use() or not actor.can_use_hands(2) or reload_remaining > 0.0: return false
	if loaded_rounds() >= PistolRules.MAGAZINE_CAPACITY or reserve_rounds() <= 0: return false
	_reload_id = str(actor.inventory.active_item().get("state", {}).get("id", ""))
	if _reload_id.is_empty(): return false
	reload_remaining = PistolRules.RELOAD_SECONDS
	_set_reload_visual(0.0)
	_refresh_hud()
	return true

func cancel_actions() -> void:
	reload_remaining = 0.0
	_reload_id = ""
	# Seat mode disables unhandled input, so its release event may never arrive.
	# Gameplay still fires only on a new press event after the mode returns.
	_fire_down = false
	aim_weight = 0.0
	recoil = 0.0
	_set_reload_visual(-1.0)
	_restore_fov()
	_refresh_hud()

func advance(delta: float) -> void:
	if not is_instance_valid(actor): return
	var elapsed := maxf(0.0, delta)
	_cooldown = maxf(0.0, _cooldown - elapsed)
	recoil = move_toward(recoil, 0.0, elapsed * 7.0)
	if not can_use():
		cancel_actions()
		return
	if reload_remaining > 0.0:
		var identity: String = str(actor.inventory.active_item().get("state", {}).get("id", ""))
		if not actor.can_use_hands(2) or identity != _reload_id:
			cancel_actions()
		else:
			reload_remaining = maxf(0.0, reload_remaining - elapsed)
			if reload_remaining <= 0.0:
				_complete_reload()
			else:
				_set_reload_visual(1.0 - reload_remaining / PistolRules.RELOAD_SECONDS)
	var aiming := reload_remaining <= 0.0 and Input.is_action_pressed("weapon_aim")
	aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, elapsed / PistolRules.AIM_SECONDS)
	if actor.camera.current:
		actor.camera.fov = _walk_fov() * lerpf(1.0, PistolRules.AIM_FOV_SCALE, aim_weight)
		_owns_fov = aim_weight > 0.0
	_sync_preview()
	_refresh_hud()

func loaded_rounds() -> int:
	if not is_instance_valid(actor): return 0
	return int(actor.inventory.active_item().get("state", {}).get("pistol", {}).get("loaded_rounds", 0))

func reserve_rounds() -> int:
	if not is_instance_valid(actor): return 0
	var total := 0
	for item: Dictionary in actor.inventory.items:
		if item.get("scene_path", "") == PistolRules.AMMO_SCENE:
			total += int(item.get("state", {}).get("ammo", {}).get("rounds", 0))
	return total

func _complete_reload() -> void:
	# Build the entire transaction before publishing it. Removed boxes may shift
	# the selected slot; the pistol's stable Item ID restores the same selection.
	var next: Array[Dictionary] = []
	var needed := PistolRules.MAGAZINE_CAPACITY - loaded_rounds()
	var transferred := 0
	for original: Dictionary in actor.inventory.items:
		var item := original.duplicate(true)
		if item.get("scene_path", "") == PistolRules.AMMO_SCENE and needed > 0:
			var available := int(item.state.ammo.rounds)
			var consumed := mini(available, needed)
			item.state.ammo.rounds = available - consumed
			needed -= consumed
			transferred += consumed
			if int(item.state.ammo.rounds) <= 0: continue
		next.append(item)
	for index in next.size():
		if next[index].get("scene_path", "") == PistolRules.PISTOL_SCENE and next[index].state.id == _reload_id:
			next[index].state.pistol.loaded_rounds = loaded_rounds() + transferred
			actor.inventory.items.assign(next)
			actor.inventory.active_slot = index
			break
	_reload_id = ""
	_set_reload_visual(-1.0)
	_sync_preview()
	actor._update_inventory_display()

func _trace_shot() -> void:
	if not actor.is_inside_tree() or not is_instance_valid(actor.camera): return
	var held: Node3D = actor.held_item_node
	if not is_instance_valid(held): return
	var muzzle := held.global_position
	if held.has_method("muzzle_position"):
		muzzle = held.muzzle_position()
	else:
		var marker := held.get_node_or_null("Muzzle") as Node3D
		if marker != null: muzzle = marker.global_position
	var origin: Vector3 = actor.camera.global_position
	var target: Vector3 = origin - actor.camera.global_basis.z * PistolRules.RANGE
	var space := actor.get_world_3d().direct_space_state
	var excluded: Array[RID] = [actor.get_rid()]
	for child: Node in actor.find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D: excluded.append(child.get_rid())
	var camera_hit := _ray(space, origin, target, excluded)
	if not camera_hit.is_empty(): target = camera_hit.position
	# A muzzle sticking beyond a wall cannot originate a shot on its far side.
	var clearance := _ray(space, origin, muzzle, excluded)
	if not clearance.is_empty():
		_resolve_hit(held, clearance)
		return
	if muzzle.distance_squared_to(target) < .000001: return
	var hit := _ray(space, muzzle, target + (target - muzzle).normalized() * .005, excluded)
	if hit.is_empty(): return
	_resolve_hit(held, hit)

func _resolve_hit(held: Node3D, hit: Dictionary) -> void:
	_impact(held, hit)
	var body: Node = hit.collider
	while body != null and not body is Monster:
		if body is Item: return
		body = body.get_parent()
	if body is Monster: body.take_damage(PistolRules.DAMAGE)

func _impact(held: Node3D, hit: Dictionary) -> void:
	if held.has_method("play_impact"): held.play_impact(hit.position, hit.normal)

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excluded: Array[RID]) -> Dictionary:
	if from.distance_squared_to(to) < .000001: return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, excluded)
	query.collide_with_areas = false
	query.hit_from_inside = true
	return space.intersect_ray(query)

func _sync_preview() -> void:
	var held: Node3D = actor.held_item_node
	if is_instance_valid(held) and actor.inventory.active_item().get("scene_path", "") == PistolRules.PISTOL_SCENE:
		held.set("loaded_rounds", loaded_rounds())

func _play(method: String) -> void:
	var held: Node3D = actor.held_item_node
	if is_instance_valid(held) and held.has_method(method): held.call(method)

func _set_reload_visual(progress: float) -> void:
	if not is_instance_valid(actor): return
	var held: Node3D = actor.held_item_node
	if is_instance_valid(held) and held.has_method("set_reload_progress"): held.set_reload_progress(progress)

func _walk_fov() -> float:
	return float(actor.game_settings.get_setting(&"walk_fov"))

func _restore_fov() -> void:
	if _owns_fov and is_instance_valid(actor) and is_instance_valid(actor.camera):
		actor.camera.fov = _walk_fov()
	_owns_fov = false

func _refresh_hud() -> void:
	if not is_instance_valid(actor): return
	var signature := "%d:%d:%d:%s" % [loaded_rounds(), reserve_rounds(), ceili(reload_remaining * 10.0), can_use()]
	if signature == _hud_signature: return
	_hud_signature = signature
	actor._update_inventory_display()
