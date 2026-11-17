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
