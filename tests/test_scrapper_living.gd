extends SceneTree
## Real hopper contacts, deferred actor ownership and persistent torso handoff.
var failures: Array[String] = []
var world: Node3D

class DetonationProbe extends BarrelMan:
	var detonations := 0
	func _resolve_explosion(_origin: Vector3, _vehicle_ref: WeakRef) -> void:
		detonations += 1
		body_collision_shape.disabled = true

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func steps(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func fixture() -> Dictionary:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(30, 0, 0)
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await steps(3)
	rv.current_power = 20.0
	var recycler: Item = rv.get_node("Scrapper")
	check(recycler.can_operate(), "Fixture uses the production RV-mounted scrapper")
	return {"rv": rv, "recycler": recycler, "hopper": recycler.get_node("HopperArea")}

func retire() -> void:
	world.queue_free()
	await steps(3)

func new_player() -> CharacterBody3D:
	var actor: CharacterBody3D = load("res://player/player.tscn").instantiate()
	actor.position = Vector3(-20, .1, 0)
	world.add_child(actor)
	# Stop locomotion only; children and deferred physics keep production processing.
	actor.set_physics_process(false)
	actor.set_process_unhandled_input(false)
	return actor

func new_raker() -> Raker:
	var actor: Raker = load("res://enemies/raker.tscn").instantiate()
	actor.position = Vector3(-20, .1, 0)
	actor.loot_drops = {}
	actor.detection_range = 0
	world.add_child(actor)
	actor.set_physics_process(false)
	return actor

func feed(actor: Node3D, recycler: Item, offset := Vector3(0, .3, 0)) -> void:
	actor.global_position = recycler.to_global(offset)
	actor.reset_physics_interpolation()

func corpses() -> Array[CorpseProp]:
	var result: Array[CorpseProp] = []
	for child in WorldEntities.get_container(world).get_children():
		if child is CorpseProp and not child.is_queued_for_deletion(): result.append(child)
	return result

func queued_corpse(recycler: Item) -> CorpseProp:
	for entry: Dictionary in recycler.props_being_crushed:
		if is_instance_valid(entry.prop) and entry.prop is CorpseProp: return entry.prop
	return null

func player_contact_and_recovery() -> void:
	var data := await fixture()
	var recycler: Item = data.recycler
	var actor := new_player()
	await steps(3)
	var identity := actor.get_instance_id()
	check(actor.add_item("Scrap", false, "res://props/scrap.tscn"), "Player fixture owns a real inventory Item")
	var inventory_before: Array = actor.inventory.items.duplicate(true)
	data.rv.current_power = 0.0
	feed(actor, recycler)
	await steps(4)
	check(data.hopper.get_overlapping_bodies().has(actor), "Unpowered player fixture physically overlaps the hopper")
	check(not actor.is_player_dead and recycler.props_being_crushed.is_empty(), "Zero power leaves overlapping player alive and unclaimed")
	data.rv.current_power = 20.0
	recycler.enabled = false
	recycler.step_work(0.0)
	await steps(2)
	check(not actor.is_player_dead, "Disabled recycler cannot kill an overlapping player")
	recycler.enabled = true
	recycler.presentation_only = true
	recycler.step_work(0.0)
	await steps(2)
	check(not actor.is_player_dead, "Presentation recycler cannot kill an overlapping player")
	recycler.presentation_only = false
	recycler.is_being_placed = true
	recycler.step_work(0.0)
	await steps(2)
	check(not actor.is_player_dead, "Placement preview cannot kill an overlapping player")
	recycler.is_being_placed = false
	recycler.queue_capacity = 0
	recycler.step_work(0.0)
	await steps(2)
	check(not actor.is_player_dead, "Full queue cannot kill an overlapping player")
	recycler.queue_capacity = 4
	feed(actor, recycler, Vector3(.55, .3, 0))
	await steps(4)
	check(data.hopper.get_overlapping_bodies().has(actor), "Outside-center fixture retains real capsule overlap")
	recycler.step_work(0.0)
	await steps(2)
	check(not actor.is_player_dead, "Capsule grazing the hopper wall does not feed an outside-center player")
	actor.global_position = Vector3(-20, .1, 0)
	await steps(3)
	check(actor.sever_part(&"left_arm"), "Injured fixture loses one limb before entering")
	await steps(2)
	var cuts_before := get_nodes_in_group("player_detached_parts").size()
	actor.damage_cooldown = 20.0
	feed(actor, recycler)
	await steps(10)
	check(actor.is_player_dead and actor.current_player_health == 0.0, "Real hopper contact kills despite hurt invulnerability")
	for part: StringName in PlayerBodyState.PARTS:
		check(not actor.body_state.has_part(part), "Hopper severs surviving " + String(part) + " before death")
	check(get_nodes_in_group("player_detached_parts").size() == cuts_before + 4, "Already missing arm creates only four additional detached parts")
	var corpse := queued_corpse(recycler)
	check(corpse != null and recycler.props_being_crushed.size() == 1 and corpses().size() == 1, "Player handoff creates and claims exactly one persistent torso")
	if corpse == null:
		await retire()
		return
	check(corpse.kind == "player" and corpse.bodies.size() == 3, "Player input retains only its anatomical torso bones")
	check(corpse.processing and not corpse.simulator.is_simulating_physics(), "Processing player torso stops every physical bone")
	check(not actor.get_node("Visuals").visible and actor.ragdoll_control.active, "Original player torso is hidden while death camera and timer stay active")
	check(actor.release_death_corpse() == null, "Repeated torso release cannot create another corpse")
	check(WorldActorSnapshot.capture(corpse).is_empty(), "Recycler input has one save owner and is omitted from loose-world records")
	check(VehicleSnapshot.valid_device(VehicleSnapshot.device_state(recycler)), "Player handoff input validates in production device persistence")
	var cosmetic_cuts: Array[Node3D] = []
	for part: Node3D in get_nodes_in_group("player_detached_parts"):
		if part.scrapper != null and part.scrapper.get_ref() == recycler: cosmetic_cuts.append(part)
	check(cosmetic_cuts.size() == 4, "Only newly severed parts join cosmetic rotor ingestion")
	if not cosmetic_cuts.is_empty():
		var piece: Node3D = cosmetic_cuts[0]
		var cut_before := piece.global_position
		await steps(12)
		check(piece.global_position.y < cut_before.y - .05 and not piece.simulated, "Powered cosmetic cuts descend toward the rollers without loose-body simulation")
		data.rv.current_power = 0.0
		var stopped_at := piece.global_position
		var stopped_time: float = piece.crushed_time
		await steps(6)
		check(piece.global_position.is_equal_approx(stopped_at) and is_equal_approx(piece.crushed_time, stopped_time), "Cosmetic cutting progress pauses while RV power is unavailable")
		data.rv.current_power = 20.0
		await steps(32)
		check(piece.crushed_time > stopped_time and piece.meshes[0].transparency > 0.0, "Restored power resumes cosmetic pull and fade")
		check(data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == 0, "Cosmetic cuts never deposit independent materials")
	var torso_before := corpse.global_position
	recycler.step_work(.2)
	await steps(2)
	check(corpse.global_position.distance_to(torso_before) > .05, "Detached player torso visibly follows powered ingestion")
	recycler.enabled = false
	recycler._on_service_stopped()
	await steps(4)
	check(not corpse.processing and not is_instance_valid(corpse.processing_owner) and corpse.simulator.is_simulating_physics(), "Cancelling ingestion releases the transferred torso with articulated physics")
	for piece: Node3D in cosmetic_cuts:
		if is_instance_valid(piece): check(piece.scrapper == null and piece.simulated, "Service cancellation releases cosmetic parts into loose physics")
	check(actor.is_player_dead and is_instance_valid(actor), "Cancellation preserves player death and identity")
	recycler.enabled = true
	corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(3, 3)}
	var amount_before: int = data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
	recycler.recycle_prop(corpse)
	await steps(3)
	recycler.step_work(2.0)
	await steps(3)
	check(not is_instance_valid(corpse) and data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == amount_before + 3, "Resumed player torso produces exactly one fixed yield")
	await steps(160)
	check(is_instance_valid(actor) and actor.get_instance_id() == identity and not actor.is_player_dead, "Player safely respawns as the same controller instance")
	check(actor.inventory.items == inventory_before, "Death, torso destruction and recovery preserve inventory identity/state")
	check(actor.get_node("Visuals").visible and actor.current_player_health == actor.max_player_health, "Respawn restores visible player and health")
	for part: StringName in PlayerBodyState.PARTS: check(actor.body_state.has_part(part), "Respawn restores " + String(part))
	check(corpses().is_empty() and recycler.props_being_crushed.is_empty(), "Recovery neither recreates consumed torso nor feeds a duplicate")
	var local := recycler.to_local(actor.global_position)
	check(absf(local.x) > .3 or absf(local.z) > .3, "Recovery places standing player outside the powered feed opening")
	recycler.step_work(0.0)
	await steps(4)
	check(not actor.is_player_dead and data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == amount_before + 3, "Recovered player stays alive without a second material deposit")
	await retire()

func pending_cancellation_and_world_transfer() -> void:
	var data := await fixture()
	var recycler: Item = data.recycler
	var actor := new_raker()
	await steps(3)
	data.rv.current_power = 0.0
	feed(actor, recycler)
	await steps(4)
	check(data.hopper.get_overlapping_bodies().has(actor), "Pending-cancellation fixture begins with real actor overlap")
	data.rv.current_power = 20.0
	recycler.step_work(0.0)
	check(recycler._pending_living.size() == 1 and actor.has_meta("scrapper_living_owner"), "Overlap retry synchronously reserves the actor before deferred death")
	recycler.enabled = false
	recycler._on_service_stopped()
	await steps(3)
	check(not actor.is_dead and recycler._pending_living.is_empty() and not actor.has_meta("scrapper_living_owner"), "Stopping service before deferred death releases reservation without killing")
	recycler.enabled = true
	recycler.step_work(0.0)
	check(recycler._pending_living.size() == 1, "Cancelled living reservation can be claimed again")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var remote_world := Node3D.new()
	remote_world.set_meta("entity_domain", true)
	viewport.add_child(remote_world)
	WorldEntities.transfer(actor, remote_world)
	await steps(4)
	check(not WorldEntities.same_world(recycler, actor), "World-transfer fixture uses independent physical worlds")
	check(not actor.is_dead and recycler._pending_living.is_empty() and not actor.has_meta("scrapper_living_owner") and corpses().is_empty(), "Deferred intake rejects a transferred actor and releases cross-world ownership")
	viewport.queue_free()
	await steps(3)
	await retire()

func deferred_power_loss_and_retry() -> void:
	var data := await fixture()
	var recycler: Item = data.recycler
	var actor := new_raker()
	await steps(3)
	var deaths := [0]
	actor.death_started.connect(func(): deaths[0] += 1)
	# Production body_entered runs first; remove power before its deferred kill.
	var power_loss := func(body: Node3D):
		if body == actor: data.rv.current_power = 0.0
	data.hopper.body_entered.connect(power_loss)
	feed(actor, recycler)
	await steps(5)
	check(data.hopper.get_overlapping_bodies().has(actor), "Deferred power-loss Raker remains physically inside the hopper")
	check(not actor.is_dead and deaths[0] == 0 and recycler.props_being_crushed.is_empty(), "Power lost after contact prevents deferred killing and frees the reservation")
	check(not actor.has_meta("scrapper_living_owner"), "Rejected deferred contact relinquishes actor claim")
	data.hopper.body_entered.disconnect(power_loss)
	data.rv.current_power = 20.0
	recycler.step_work(0.0)
	await steps(10)
	var corpse := queued_corpse(recycler)
	check(deaths[0] == 1 and corpse != null and corpses().size() == 1, "Regained power retries existing overlap and performs one Raker death/handoff")
	if corpse != null:
		check(corpse.kind == "raker" and corpse.bodies.size() == 15 and corpse.processing, "Raker input preserves its complete existing anatomical rig")
		check(VehicleSnapshot.valid_device(VehicleSnapshot.device_state(recycler)), "Raker handoff input validates in production device persistence")
		corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(2, 2)}
		var amount_before: int = data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
		recycler.step_work(2.0)
		await steps(3)
		recycler.step_work(2.0)
		await steps(2)
		check(data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == amount_before + 2 and corpses().is_empty(), "Raker recycling retires its original source and deposits only once")
	await retire()

func one_slot_reservation() -> void:
	var data := await fixture()
	var recycler: Item = data.recycler
	recycler.queue_capacity = 1
	var first := new_raker()
	var second := new_raker()
	await steps(3)
	var deaths := [0]
	first.death_started.connect(func(): deaths[0] += 1)
	second.death_started.connect(func(): deaths[0] += 1)
	feed(first, recycler, Vector3(-.05, .3, 0))
	feed(second, recycler, Vector3(.05, .3, 0))
	await steps(10)
	check(deaths[0] == 1 and recycler.props_being_crushed.size() == 1 and corpses().size() == 1, "Simultaneous real contacts reserve one slot before deferred deaths")
	var survivor: Raker = first if is_instance_valid(first) and not first.is_dead else second
	check(is_instance_valid(survivor) and not survivor.is_dead, "Full reservation leaves the second living actor alive")
	if is_instance_valid(survivor):
		check(data.hopper.get_overlapping_bodies().has(survivor) and not survivor.has_meta("scrapper_living_owner"), "Rejected actor stays overlapping without an abandoned owner claim")
		var corpse := queued_corpse(recycler)
		if corpse != null:
			recycler.enabled = false
			recycler._on_service_stopped()
			corpse.queue_free()
			await steps(3)
			recycler.enabled = true
			recycler.step_work(0.0)
			await steps(10)
			check(deaths[0] == 2 and recycler.props_being_crushed.size() == 1 and corpses().size() == 1, "Freed slot retries the surviving actor and claims one new corpse")
	await retire()

func competing_recyclers() -> void:
	var data := await fixture()
	var first: Item = data.recycler
	var second: Item = load("res://equipment/scrapper.tscn").instantiate()
	world.add_child(second)
	second.confirm_placement(first.global_transform, data.rv, data.rv)
	await steps(3)
	check(second.can_operate(), "Competing recycler fixture shares the same powered mounted frame")
	var actor := new_raker()
	await steps(3)
	var deaths := [0]
	actor.death_started.connect(func(): deaths[0] += 1)
	feed(actor, first)
	await steps(10)
	check(deaths[0] == 1 and first.props_being_crushed.size() + second.props_being_crushed.size() == 1 and corpses().size() == 1, "Two real overlapping hoppers cannot kill or enqueue one actor twice")
	var owner: Item = first if not first.props_being_crushed.is_empty() else second
	var corpse := queued_corpse(owner)
	if corpse != null:
		corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(4, 4)}
		var amount_before: int = data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL)
		first.step_work(2.0)
		second.step_work(2.0)
		await steps(3)
		check(data.rv.get_item_count(ItemNames.UNKNOWN_MATERIAL) == amount_before + 4 and corpses().is_empty(), "Competing recyclers still award exactly one actor payload")
	await retire()

func special_monster_deaths() -> void:
	var data := await fixture()
	var recycler: Item = data.recycler
	var barrel := DetonationProbe.new()
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = BarrelMan.BARREL_RADIUS
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.position.y = .5
	barrel.add_child(shape)
	barrel.position = Vector3(-20, .1, 0)
	world.add_child(barrel)
	barrel.set_physics_process(false)
	await steps(3)
	feed(barrel, recycler)
	await steps(8)
	check(barrel.is_dead and barrel.detonations == 1, "Actual hopper contact preserves BarrelMan's deferred detonation")
	check(recycler.props_being_crushed.is_empty() and corpses().is_empty(), "Explosive special death does not invent a generic corpse input")
	barrel.queue_free()
	await steps(3)
	var giant: SlenderSpeaker = load("res://enemies/slender_speaker/slender_speaker.tscn").instantiate()
	giant.position = Vector3(-20, .1, 0)
	world.add_child(giant)
	giant.set_physics_process(false)
	await steps(3)
	feed(giant, recycler)
	await steps(8)
	check(data.hopper.get_overlapping_bodies().has(giant), "Invincible special-monster fixture has real hopper overlap")
	check(not giant.is_dead and recycler.props_being_crushed.is_empty() and corpses().is_empty(), "SlenderSpeaker's no-op death does not create a yield or corpse")
	check(not giant.has_meta("scrapper_living_owner"), "Unsupported special death releases actor ownership")
	await retire()

func run() -> void:
	await player_contact_and_recovery()
	await deferred_power_loss_and_retry()
	await pending_cancellation_and_world_transfer()
	await one_slot_reservation()
	await competing_recyclers()
	await special_monster_deaths()
	if failures.is_empty(): print("PASS: living hopper contacts, dismemberment, torso ownership, power/capacity races and special deaths")
	quit(0 if failures.is_empty() else 1)
