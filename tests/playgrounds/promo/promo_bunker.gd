extends RefCounted

const FLASHLIGHT := "res://props/flashlight.tscn"
const SCRAP := "res://props/scrap.tscn"
const RAKER := "res://enemies/raker.tscn"
const GrabRules := preload("res://core/raker_grab_rules.gd")
const FLOOR_RAIL_SECONDS := 8.0

var inside: PoiInterior
var floor_index := 0
var ceilings: Array[Node3D] = []

func prepare(world) -> bool:
	inside = world.get_node("PoiInstances").interior
	inside.get_node("BlackApparitionEncounter").set_physics_process(false)
	for entity in inside.entities.get_children():
		if entity is Monster: entity.queue_free()
	if world.shot_id == "B5":
		floor_index = int(world.shot.get("floor", 0))
		for room in inside.rooms:
			for mesh in room.get_node("Visuals").get_children():
				if str(mesh.name).begins_with("Ceiling"):
					ceilings.append(mesh)
					mesh.hide()
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = Vector3(-60, -35, 0)
		lamp.light_energy = 1.8
		lamp.shadow_enabled = true
		inside.add_child(lamp)
		var lighting: Environment = inside.get_node("WorldEnvironment").environment
		lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		lighting.ambient_light_color = Color(0.72, 0.80, 0.87)
		lighting.ambient_light_energy = 0.45
		_show_floor(world)
		return world.director.rail.playable()
	world.actor.add_item(ItemNames.FLASHLIGHT, false, FLASHLIGHT)
	if world.shot_id == "B6":
		for entity in inside.entities.get_children():
			if entity.get_meta("bunker_actor_id", "") != inside.content.cargo_id or not entity is Item: continue
			world.subject = entity
			# Start on the connected corridor side of the cargo.
			for i in inside.rooms.size():
				if str(inside.rooms[i].name) != inside.content.cargo_room: continue
				var map := inside.navigation.get_navigation_map()
				var cargo: Vector3 = entity.global_position
				var toward := (inside.navigation_anchor(i) - cargo).slide(Vector3.UP).normalized()
				var placed := false
				for offset in [0.0, PI / 2.0, -PI / 2.0, PI]:
					var mark := cargo + toward.rotated(Vector3.UP, float(offset)) * 2.0
					var point := NavigationServer3D.map_get_closest_point(map, mark)
					if point.distance_to(cargo) > 2.8 or point.distance_to(cargo) < 1.15: continue
					world.actor.global_position = point + Vector3.UP * 0.12
					placed = true
					break
				if not placed: return false
				world._aim_at(entity.global_position)
				return true
		return false
	if not world.find_bunker_lane(inside): return false
	var mark: Vector3 = world._apparition_position
	var toward: Vector3 = (mark - world.actor.global_position).slide(Vector3.UP).normalized()
	var side := toward.cross(Vector3.UP)
	match world.shot_id:
		"B1":
			var cache := BunkerContent.CACHE.instantiate() as BunkerCache
			var rng := RandomNumberGenerator.new()
			rng.seed = int(inside.layout.seed)
			cache.cache_id = "promo-b1"
			cache.remaining.append(BunkerContent._supply(rng, "promo-b1-supply", true))
			cache.position = inside.navigation.to_local(mark)
			cache.rotation.y = atan2(toward.x, toward.z)
			inside.navigation.add_child(cache)
			world.staged.append(cache)
			world.spawn(SCRAP, mark - toward * 1.25 + Vector3.UP * 0.17, inside.entities, true)
		"B3", "B4":
			var path := RAKER if world.shot_id == "B3" else RoadSpawns.BARREL_MAN_SCENE
			var enemy: Monster = world.spawn(path, mark + Vector3.UP * 0.12, inside.entities)
			BunkerContent.configure_monster(enemy)
			enemy.look_at(enemy.global_position - toward)
			enemy.set_physics_process(false)
			world.subject = enemy
			if enemy is BarrelMan:
				for shift in [-1.1, 1.1]:
					var point := mark + side * float(shift)
					if world._clear_shooting_lane(inside.get_world_3d().direct_space_state, mark, point):
						world.spawn(RoadSpawns.OIL_BARREL_SCENE, point + Vector3.UP * 0.50, inside.entities, true)
	return true

func trigger(world) -> bool:
	match world.shot_id:
		"B1":
			if not world.actor._active_flashlight_state().get("on", false): world.actor._toggle_flashlight()
			return true
		"B2":
			if is_instance_valid(world.apparition) or world.actor.get_viewport() != world.get_node("PoiInstances").viewport: return false
			var apparition := BlackApparitionEncounter.SCENE.instantiate() as BlackApparition
			inside.entities.add_child(apparition)
			apparition.configure(world.actor, true)
			apparition.emerge(world._apparition_position, world.actor.camera)
			world.apparition = apparition
			world.subject = apparition
			return true
		"B3", "B4":
			if not is_instance_valid(world.subject) or world.subject.is_physics_processing(): return false
			world.subject.set_physics_process(true)
			return true
		"B5":
			floor_index = posmod(floor_index + 1, InteriorLayout.floor_count(inside.layout))
			_show_floor(world)
			return world.director.play_rail()
		"B6":
			if not is_instance_valid(world.subject): return false
			if world.subject.global_position.distance_to(world.actor.global_position) > 3.0: return false
			world.subject.pickup(world.actor)
			return is_instance_valid(world.actor.held_item_node)
	return false

func _show_floor(world, frame_floor := true) -> void:
	var bounds := AABB()
	var initialized := false
	for room in inside.rooms:
		var floor_number := roundi(-room.position.y / float(inside.layout.floor_spacing))
		room.visible = floor_number == floor_index
		if not room.visible: continue
		var index := inside.rooms.find(room)
		var definition := InteriorLayout.definition(inside.layout, index)
		var box: AABB = room.global_transform * definition.describe().bounds
		bounds = bounds.merge(box) if initialized else box
		initialized = true
	inside.entities.hide()
	for node in inside.navigation.get_children():
		if node is BunkerCache or node is PoiEntrance:
			node.visible = roundi(-node.position.y / float(inside.layout.floor_spacing)) == floor_index
	if not frame_floor or not world.director.use_generated_rail(): return
	var center := bounds.get_center()
	var distance := maxf(9.0, bounds.size.length() * 0.62)
	world.director.clear_generated_rail()
	world.director.rail.duration = FLOOR_RAIL_SECONDS
	for direction in [Vector3(-0.32, 1, 0.35), Vector3(0.0, 1, 0.45), Vector3(0.32, 1, 0.35)]:
		var origin: Vector3 = center + direction.normalized() * distance
		world.director.generated_rail_key(Transform3D(Basis.looking_at(center - origin), origin))

## Unattended take for Movie Maker. Returns how long to keep filming, or -1 after failing.
func autoplay(world) -> float:
	match world.shot_id:
		"B2":
			world.actor.invulnerable = true
			if not world.trigger_take():
				world._fail("Could not reveal the apparition")
				return -1.0
			world.actor._toggle_flashlight()
			if not world.director.use_free_camera():
				world._fail("Could not detach the camera")
				return -1.0
			world.director.view.global_position += world.director.view.global_basis.x * 0.55
			for frame in 90:
				await world.get_tree().physics_frame
				if world.apparition.phase == BlackApparition.Phase.FRENZIED: return 2.5
			world._fail("Flashlight did not trigger pursuit in the bunker")
			return -1.0
		"B5":
			if not world.director.play_rail():
				world._fail("Could not start the floor rail")
				return -1.0
			return float(world.director.rail.duration) + 0.5
		"B1", "B3", "B4":
			if world.shot_id != "B1": world.actor._toggle_flashlight()
			if not world.trigger_take():
				world._fail("Could not start the bunker action")
				return -1.0
			if world.shot_id == "B3":
				for frame in 240:
					await world.get_tree().physics_frame
					if world.actor.is_grabbed(): break
				if not world.actor.is_grabbed():
					world._fail("Raker did not grab the player")
					return -1.0
				var grab: Node = world.actor.grab_control
				var wounded := GrabRules.minimum_wounded_presses(grab.required)
				while world.actor.is_grabbed() and grab.presses < wounded:
					if not world.actor.submit_struggle(): break
					await world.get_tree().create_timer(0.055).timeout
			return 8.0
	if not world.trigger_take():
		world._fail("Could not start the take")
		return -1.0
	return 7.0

func autoplay_error(_world) -> String:
	return ""
