extends RefCounted

const SCRAP := "res://props/scrap.tscn"
const CORPSE := "res://props/corpse.tscn"
const DEVICE := "res://equipment/item_box.tscn"

var recycler: Node
var feed_index := 0

func prepare(world) -> bool:
	var rv: Chassis = world.rv
	if not rv.interior_requested.cabin: rv.toggle_interior_light("cabin")
	match world.shot_id:
		"R1":
			recycler = rv.get_node("Scrapper")
			var container := WorldEntities.get_container(world)
			for prop in [{"path": SCRAP, "mark": Vector3(0.5, 0.75, -0.8)},
				{"path": RoadSpawns.OIL_BARREL_SCENE, "mark": Vector3(-0.75, 1.0, -2.0)},
				{"path": CORPSE, "mark": Vector3(-0.55, 1.1, -4.1)}]:
				var item: Item = world.spawn(prop.path, rv.to_global(prop.mark), container, true)
				if item is CorpseProp:
					# An already injured survivor fits the hopper at full scale.
					item.kind = "player"
					item.item_name = "Player remains"
					for part in [&"left_arm", &"right_arm"]: item.body_state.sever(part)
			world.actor.global_position = rv.to_global(Vector3(-0.05, 0.55, 0.2))
			world._aim_at(recycler.global_position + Vector3.UP * 0.55)
		"R2":
			world.station = rv.get_node("CraftingStation")
			for id in world.shot.recipes:
				var recipe := RecipeCatalog.find(id)
				for material in recipe.costs: rv.add_item(material, int(recipe.costs[material]) * 3)
			world._aim_at(world.station.spawn_marker.global_position + Vector3.UP * 0.22)
		"R3":
			var slots: RVStructureSlots = rv.get_node("StructureSlots")
			mark_panel(slots.panel("roof_0"), false)
			mark_panel(slots.panel("right_2"), true)
			rv.add_item("Metal Parts", (slots.panel("roof_0").definition.repair_cost + slots.panel("right_2").definition.rebuild_cost) * 3)
			var device: Item = world.spawn(DEVICE, rv.to_global(Vector3(0.8, 0.78, 0.2)), WorldEntities.get_container(world), true)
			device.pickup(world.actor)
			world._aim_at(rv.to_global(Vector3(0.55, 0.48, -0.8)))
	return true

func mark_panel(panel: RVStructurePanel, destroyed: bool) -> void:
	panel.set_health(0.0 if destroyed else panel.max_health * 0.35)

func trigger(world) -> bool:
	if world.shot_id == "R1":
		while feed_index < world.staged.size():
			var item = world.staged[feed_index]
			if not is_instance_valid(item) or item.processing_owner == recycler:
				feed_index += 1
				continue
			if not recycler.props_being_crushed.is_empty(): return false
			if not item.freeze: return false
			if item is CorpseProp:
				if not item.initialized: return false
				item.set_processing(true)
				var pelvis: PhysicalBone3D = item.bodies["pelvis"]
				var head: PhysicalBone3D = item.bodies["head"]
				var spine := (head.global_position - pelvis.global_position).normalized()
				if spine.length_squared() > 0.5:
					item.global_basis = Basis(Quaternion(spine, Vector3.UP)) * item.global_basis
				item.global_position = recycler.to_global(Vector3(0, 1.40, 0))
				item.reset_physics_interpolation()
				recycler.recycle_prop(item)
				return item.processing_owner == recycler
			item.freeze = false
			item.global_position = recycler.to_global(Vector3(0, 0.95, 0))
			item.linear_velocity = Vector3.ZERO
			item.reset_physics_interpolation()
			return true
		return false
	var tablet: Node = world.rv.get_node("TabletScreen")
	if world.actor.in_ui_mode: return false
	tablet.interact_hold(world.actor)
	if not tablet.is_management_active(): return false
	if world.shot_id == "R2":
		tablet.ui_instance.select_recipe(world.shot.recipes[0])
		tablet.ui_instance.select_page("crafting")
	else:
		tablet.ui_instance.select_slot("roof_0")
		tablet.ui_instance.select_page("structure")
	return true

## Unattended take for Movie Maker. Returns how long to keep filming, or -1 after failing.
func autoplay(world) -> float:
	var tablet: Node = world.rv.get_node("TabletScreen")
	match world.shot_id:
		"R1":
			for index in world.staged.size():
				var input = world.staged[index]
				if not world.trigger_take():
					world._fail("Could not feed the scrapper")
					return -1.0
				for frame in 900:
					await world.get_tree().physics_frame
					if not is_instance_valid(input): break
				if is_instance_valid(input):
					world._fail("Scrapper did not finish " + input.item_name)
					return -1.0
				await world.get_tree().create_timer(0.45).timeout
			return 4.0
		"R2":
			if not world.trigger_take():
				world._fail("Could not open the tablet")
				return -1.0
			await world.get_tree().create_timer(0.75).timeout
			tablet.ui_instance._craft()
			if world.station.jobs.is_empty():
				world._fail("Craft failed: " + world.station.last_error)
				return -1.0
			tablet._close_ui()
			return RecipeCatalog.find(world.shot.recipes[0]).duration + 1.5
		"R3":
			if not world.trigger_take():
				world._fail("Could not open Structure")
				return -1.0
			var construction: RVStructureConstruction = world.rv.get_node("StructureSlots").construction
			await world.get_tree().create_timer(0.8).timeout
			for job in [["roof_0", "repair"], ["right_2", "rebuild"]]:
				tablet.ui_instance.select_slot(job[0])
				tablet.ui_instance._begin_structure(job[1])
				if not construction.is_building():
					world._fail(construction.last_message)
					return -1.0
				await world.get_tree().create_timer(float(construction.job.duration) + 0.2).timeout
				if construction.last_message != "Construction complete":
					world._fail(construction.last_message)
					return -1.0
			tablet._close_ui()
			world._aim_at(world.rv.to_global(Vector3(1.9, 1.7, 4.0)))
			return 4.0
	return -1.0

func autoplay_error(world) -> String:
	if world.shot_id == "R2" and not world.station.jobs.is_empty(): return "Print did not finish: " + world.station.last_error
	if world.shot_id == "R1" and (not recycler.props_being_crushed.is_empty() or world.staged.any(func(item): return is_instance_valid(item))):
		return "Scrapper did not finish all three items"
	return ""
