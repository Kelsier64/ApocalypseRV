extends RefCounted
class_name OpeningSiteContent
## Fixed opening inventory; callers retain the shared outdoor actor lifecycle.
const ORIENTATION_SALVAGE := {
	"a": "res://props/scavenge_loot/copper_wire_spool.tscn",
	"b": "res://props/scavenge_loot/broken_shortwave_radio.tscn",
	"c": "res://props/scavenge_loot/salvaged_motor.tscn",
	"d": "res://props/scavenge_loot/medical_tin.tscn",
	"e": "res://props/scavenge_loot/industrial_valve.tscn",
	"f": "res://props/scavenge_loot/enamel_kettle.tscn",
	"g": "res://props/scrap.tscn",
	"h": "res://props/scrap.tscn"}

## Populate only fresh sites. Restoring a snapshot must never replenish supplies.
static func populate(building: Node3D, container: Node3D, definition_id: StringName) -> bool:
	match definition_id:
		&"orientation_shelter":
			_spawn_orientation_terminal(building, container)
			_spawn_orientation_workshop(building, container)
		&"starting_shelter":
			_spawn_starter_actors(building, container)
		_:
			return false
	return true

## The authored opening has a fixed inventory. Markers carry placement only;
## loose actors use the same owner/snapshot lifecycle as every other walk-in.
static func _spawn_orientation_terminal(building: Node3D, container: Node3D) -> void:
	var point := building.get_node("StarterEquipment/TrainingTerminal") as Marker3D
	var support := building.get_node("Collision/TerminalSupport") as StaticBody3D
	var terminal: TrainingTerminal = load("res://equipment/training_terminal.tscn").instantiate()
	container.add_child(terminal)
	support.set_meta("training_terminal_dock", terminal.persistent_id)
	terminal.confirm_placement(point.global_transform, container, support)

static func workshop_ids(building: Node3D) -> Dictionary:
	var prefix := str(building.get_meta("poi_id", "orientation")) + ":recovery:"
	var result := {}
	for role in ["scrapper", "workbench", "scrap_a", "scrap_b", "scrap_c", "scrap_d", "scrap_e", "scrap_f", "scrap_g", "scrap_h", "barrel", "barrel_b", "spare", "battery", "engine_kit_a", "engine_kit_b"]:
		result[role] = prefix + role
	return result

## Called for a fresh site. Reloading never calls this to replace consumed or lost supplies.
static func _spawn_orientation_workshop(building: Node3D, container: Node3D) -> void:
	var stock := {
		"scrapper": ["WorkshopEquipment/Scrapper", "res://equipment/scrapper.tscn"],
		"workbench": ["WorkshopEquipment/Workbench", "res://equipment/crafting_station.tscn"],
		"barrel": ["WorkshopSupplies/OilBarrel", "res://props/oil_barrel.tscn"],
		"spare": ["WorkshopSupplies/SpareWheel", "res://props/wheel.tscn"],
		"battery": ["WorkshopSupplies/Battery", "res://props/battery.tscn"],
		"engine_kit_a": ["WorkshopSupplies/EngineKitA", "res://props/engine_repair_kit.tscn"],
		"engine_kit_b": ["WorkshopSupplies/EngineKitB", "res://props/engine_repair_kit.tscn"],
		"barrel_b": ["WorkshopSupplies/OilBarrelB", "res://props/oil_barrel.tscn"]}
	for suffix in ORIENTATION_SALVAGE:
		stock["scrap_" + suffix] = ["WorkshopSupplies/Scrap" + suffix.to_upper(), ORIENTATION_SALVAGE[suffix]]
	var identities := workshop_ids(building)
	for role in stock:
		if _orientation_identity_owned(container, identities[role]):
			for actor in container.get_tree().get_nodes_in_group(Groups.ITEMS):
				if actor is Item and actor.persistent_id == identities[role] and WorldEntities.same_world(container, actor): actor.set_meta("orientation_role", role)
			continue
		var point := building.get_node(NodePath(stock[role][0])) as Marker3D
		var item: Item = load(stock[role][1]).instantiate()
		item.freeze = true
		item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		item.set_meta("orientation_role", role)
		container.add_child(item)
		var state := item.capture_item_state()
		state.id = identities[role]
		if role.begins_with("scrap_"):
			state.scrap_yields = {ItemNames.METAL_PARTS: Vector2(3, 3)}
		elif role in ["barrel", "barrel_b"]:
			state.scrap_yields = {ItemNames.METAL_PARTS: Vector2(2, 2), ItemNames.UNREFINED_FUEL: Vector2(10, 10)}
		elif role == "battery":
			state.battery.id = identities[role]
			state.battery.charge = state.battery.capacity
		item.restore_item_state(state)
		item.global_transform = point.global_transform
	_spawn_orientation_food(building, container)
	_spawn_orientation_compass(building, container)

static func _spawn_orientation_compass(building: Node3D, container: Node3D) -> void:
	# Ordinary starter stock, outside the tutorial's required repair roles.
	var identity := str(building.get_meta("poi_id", "orientation")) + ":electronic_compass"
	if _orientation_identity_owned(container, identity): return
	var compass: Item = load("res://props/electronic_compass.tscn").instantiate()
	compass.freeze = true
	container.add_child(compass)
	var state := compass.capture_item_state()
	state.id = identity
	compass.restore_item_state(state)
	compass.global_transform = building.get_node("WorkshopSupplies/ElectronicCompass").global_transform

static func _spawn_orientation_food(building: Node3D, container: Node3D) -> void:
	# Food is ordinary starter stock, outside the tutorial's repair-role contract.
	for scene_path in FoodCatalog.SCENES:
		var food_id: String = scene_path.get_file().get_basename()
		var identity := str(building.get_meta("poi_id", "orientation")) + ":food:" + food_id
		if _orientation_identity_owned(container, identity): continue
		var point := building.get_node("WorkshopSupplies/" + food_id) as Marker3D
		var food: Item = load(scene_path).instantiate()
		food.freeze = true
		food.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		container.add_child(food)
		var state := food.capture_item_state()
		state.id = identity
		food.restore_item_state(state)
		food.global_transform = point.global_transform

static func _orientation_identity_owned(container: Node3D, identity: String) -> bool:
	var world := WorldActorSnapshot.domain(container)
	for item in container.get_tree().get_nodes_in_group(Groups.ITEMS):
		if item is Item and not item.presentation_only and world.is_ancestor_of(item) and item.persistent_id == identity: return true
	var player := world.get_node_or_null("Player")
	if player != null and _orientation_record_has_id(player.inventory.items, identity): return true
	for vehicle in container.get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not world.is_ancestor_of(vehicle): continue
		if identity in vehicle.wheel_ids or _orientation_record_has_id(vehicle.stored_items, identity): return true
	var generator := world.get_node_or_null("WorldGenerator")
	return generator != null and (_orientation_record_has_id(generator.outdoor_sites, identity) or _orientation_record_has_id(generator.dormant_items, identity))

static func _orientation_record_has_id(value: Variant, identity: String) -> bool:
	if value is Dictionary:
		if value.get("id") == identity: return true
		for child in value.values():
			if _orientation_record_has_id(child, identity): return true
	elif value is Array:
		for child in value:
			if _orientation_record_has_id(child, identity): return true
	return false

static func _spawn_starter_actors(building: Node3D, container: Node) -> void:
	var scenes := {
		"StarterEquipment/CraftingStation": "res://equipment/crafting_station.tscn",
		"StarterEquipment/Scrapper": "res://equipment/scrapper.tscn",
		"StarterLoot/Flashlight": "res://props/flashlight.tscn",
		"StarterLoot/Pistol": PistolRules.PISTOL_SCENE,
		"StarterLoot/PistolAmmo1": PistolRules.AMMO_SCENE,
		"StarterLoot/PistolAmmo2": PistolRules.AMMO_SCENE,
		"StarterLoot/Battery": "res://props/battery.tscn",
		"StarterLoot/GasCan1": "res://props/gas_can.tscn",
		"StarterLoot/GasCan2": "res://props/gas_can.tscn",
		"StarterLoot/OilBarrel": "res://props/oil_barrel.tscn",
		"StarterLoot/Wheel": "res://props/wheel.tscn",
	}
	for i in range(1, 7): scenes["StarterLoot/Scrap%d" % i] = "res://props/scrap.tscn"
	for path in scenes:
		var point := building.get_node_or_null(NodePath(path)) as Marker3D
		if point == null:
			push_error("Starting shelter is missing marker: " + path)
			continue
		var actor: Node3D = load(scenes[path]).instantiate()
		container.add_child(actor)
		actor.global_transform = point.global_transform
		if actor is Item:
			actor.freeze = true
			actor.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

