extends Item
class_name CraftingStation
signal output_committed(rv_id: String, item_id: String, recipe_id: String)

@onready var spawn_marker: Marker3D = $SpawnMarker
@export var power_cost_per_spawn: float = 0.6
var last_error: String = ""
var _committing: bool = false
var jobs: Array[Dictionary] = []
@export var queue_capacity: int = 4
@onready var print_visual: CraftingPrintVisual = $PrintVisual

func _ready() -> void:
	super._ready()
	if presentation_only: return
	add_to_group(Groups.CRAFTING_STATIONS)
	_sync_print_visual()

## Read-only eligibility used by both the terminal and the transaction.
## Resolve ancestry without refreshing Item's connection cache or registry.
func craft_rejection_reason(recipe_id: String) -> String:
	var recipe := RecipeCatalog.find(recipe_id)
	if recipe == null or _committing or not _craft_service_ready(self):
		return "Workstation unavailable"
	var rv := RVConnection.resolve(get_parent())
	if rv == null:
		return "Workstation unavailable"
	if jobs.size() >= queue_capacity:
		return "Queue full"
	# Chassis.current_power finds a socket through Item.can_operate(), which may
	# refresh a connection and emit registry signals. Read the same first usable
	# installed battery directly so this query never changes service ownership.
	var charge := 0.0
	var has_battery := false
	for device: Node in rv.get_equipment():
		if device is BatterySocket and _craft_service_ready(device) and device.installed_battery != null:
			if device.installed_battery.condition <= 0.0: break
			has_battery = true
			charge = device.installed_battery.charge
			break
	if not (rv.unlimited_power and has_battery) and charge < maxf(recipe.power_cost, 0.0):
		return "Insufficient battery charge"
	if not rv.has_materials(recipe.costs):
		return "Insufficient materials"
	return ""

func _craft_service_ready(item: Item) -> bool:
	return not item.presentation_only and item.is_fixed and item.enabled and not item.support_lost and not item.is_being_placed and not item.is_destroyed and item.current_health > 0.0 and RVConnection.resolve(item.get_parent()) != null

func request_craft(recipe_id: String) -> bool:
	var rejection := craft_rejection_reason(recipe_id)
	if not rejection.is_empty():
		last_error = rejection
		return false
	var recipe := RecipeCatalog.find(recipe_id)
	var rv := get_connected_rv()
	# Keep final service and power validation adjacent to the synchronous commit.
	if not can_operate() or rv == null:
		last_error = "Workstation unavailable"
		return false
	if not rv.has_usable_power(recipe.power_cost):
		last_error = "Insufficient battery charge"
		return false
	_committing = true
	var paid_costs: Dictionary = {} if rv.unlimited_materials else recipe.costs.duplicate(true)
	var accepted: bool = rv.deduct_materials(recipe.costs)
	if accepted:
		jobs.append({"id": InstanceIds.create(), "recipe": recipe.recipe_id, "remaining": recipe.duration, "costs": paid_costs, "power": recipe.power_cost, "rv": rv})
	_committing = false
	last_error = "Queued" if accepted else "Insufficient materials"
	_sync_print_visual()
	return accepted

func step_work(delta: float) -> void:
	if jobs.is_empty() or not can_operate():
		return
	var job := jobs[0]
	var recipe := RecipeCatalog.find(job.recipe)
	if recipe == null:
		cancel_jobs()
		return
	if recipe.recipe_id != "printed_player" and not job.has("print_orientation"):
		_sync_print_visual()
		if not job.has("print_orientation"):
			last_error = "Output blocked"
			return
	var elapsed := minf(delta, job.remaining)
	var power_needed := minf(job.power, recipe.power_cost * elapsed / maxf(recipe.duration, 0.001))
	if power_needed > 0.0 and not consume_rv_power(power_needed):
		last_error = "Paused: battery empty"
		return
	job.power = maxf(0.0, job.power - power_needed)
	job.remaining = maxf(0.0, job.remaining - elapsed)
	if job.remaining <= 0.00001:
		# Show the finished height before clearing/changing jobs, even when the
		# final work update consumes a large delta. The rig then retracts slowly.
		_sync_print_visual()
		var output_rv := get_connected_rv()
		var item := _spawn_item(recipe.scene_path, {}, 0.0, bool(job.get("crouching", false)), int(job.get("print_orientation", 0)), int(job.get("print_offset", 0)))
		if item != null:
			# Remove the committed job before notifying observers, so a synchronous
			# completion retry cannot print the same job twice.
			jobs.pop_front()
			output_committed.emit(output_rv.persistent_id, item.persistent_id, recipe.recipe_id)
	_sync_print_visual()

func spawn_item(scene_path: String, costs: Dictionary = {}, power_cost: float = -1.0, crouching: bool = false, orientation: int = -1, offset_index: int = 0) -> bool:
	# Direct service calls create physical items without queueing a job.
	return _spawn_item(scene_path, costs, power_cost, crouching, orientation, offset_index) != null

func _spawn_item(scene_path: String, costs: Dictionary, power_cost: float, crouching: bool, orientation: int, offset_index: int) -> Item:
	if _committing or not can_operate():
		last_error = "Workstation unavailable"
		return null
	var rv := get_connected_rv()
	var fee := power_cost_per_spawn if power_cost < 0.0 else power_cost
	if not rv.has_materials(costs) or not rv.has_usable_power(fee):
		last_error = "Insufficient materials or battery charge"
		return null
	if not ResourceLoader.exists(scene_path):
		last_error = "Output unavailable"
		return null
	var scene := load(scene_path) as PackedScene
	if scene == null:
		last_error = "Output unavailable"
		return null
	var instance := scene.instantiate()
	var item := instance as Item
	if item == null:
		instance.free()
		last_error = "Invalid output"
		return null
	if item is PrintedPlayerBody: item.set_crouching(crouching)
	if orientation < 0 and not item is PrintedPlayerBody:
		var selected := CraftingOutputPlacement.select_pose(self, item)
		if selected.is_empty():
			last_error = "Output blocked"
			item.free()
			return null
		orientation = selected.print_orientation
		offset_index = selected.print_offset
	var output := CraftingOutputPlacement.output_pose(item, spawn_marker.global_transform, maxi(orientation, 0), offset_index)
	if not CraftingOutputPlacement.is_clear(self, item, output, false) or (item is PrintedPlayerBody and not CraftingOutputPlacement.body_can_stand(self, output, crouching)):
		last_error = "Output blocked: clear print bed and overhead space" if item is PrintedPlayerBody else "Output blocked"
		item.free()
		return null
	var container := WorldEntities.get_container(self)
	if not is_instance_valid(container) or container.is_queued_for_deletion():
		item.free()
		last_error = "Output unavailable"
		return null
	_committing = true
	var paid_power := 0.0 if rv.unlimited_power else fee
	if not rv.consume_power(fee):
		item.free()
		_committing = false
		return null
	if not rv.deduct_materials(costs):
		rv.add_power(paid_power)
		item.free()
		_committing = false
		return null
	container.add_child(item)
	if "battery" in item:
		item.battery.charge = 0.0
		item._update_label()
	item.global_transform = output
	item.linear_velocity = ClimbMath.point_velocity(rv, output.origin)
	_committing = false
	last_error = "Output ready"
	return item

func cancel_jobs() -> void:
	var cancelled := jobs.duplicate()
	jobs.clear()
	_sync_print_visual()
	for job in cancelled:
		if is_instance_valid(job.rv):
			job.rv.deposit_materials(job.costs, true)

func _on_service_stopped() -> void:
	cancel_jobs()

func capture_service_state() -> Dictionary:
	var saved_jobs: Array[Dictionary] = []
	for job in jobs:
		var saved: Dictionary = job.duplicate(true)
		saved.erase("rv")
		saved_jobs.append(saved)
	return {"jobs": saved_jobs}

func restore_service_state(state: Dictionary) -> void:
	jobs.assign(state.get("jobs", []).duplicate(true))
	for job in jobs:
		job["rv"] = get_connected_rv()

	_sync_print_visual()

func _sync_print_visual() -> void:
	if not is_node_ready() or presentation_only: return
	if not jobs.is_empty() and jobs[0].recipe == "printed_player" and not jobs[0].has("crouching"):
		# Choose once when the job reaches the front. Restores preserve its pose;
		# later obstructions block delivery rather than changing printed geometry.
		var output := spawn_marker.global_transform
		output.origin += global_basis.y * 0.06
		jobs[0]["crouching"] = not CraftingOutputPlacement.body_can_stand(self, output)
	if not jobs.is_empty() and jobs[0].recipe != "printed_player" and not jobs[0].has("print_orientation"):
		var recipe := RecipeCatalog.find(jobs[0].recipe)
		if recipe != null:
			var item := (load(recipe.scene_path) as PackedScene).instantiate() as Item
			jobs[0].merge(CraftingOutputPlacement.select_pose(self, item))
			item.free()
	if not jobs.is_empty() and jobs[0].recipe != "printed_player" and not jobs[0].has("print_orientation"):
		print_visual.sync_job({}, spawn_marker.transform)
		return
	print_visual.sync_job(jobs[0] if not jobs.is_empty() else {}, spawn_marker.transform)
