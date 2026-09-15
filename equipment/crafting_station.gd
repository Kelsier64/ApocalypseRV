extends Equipment
class_name CraftingStation

@onready var spawn_marker: Marker3D = $SpawnMarker
@export var power_cost_per_spawn: float = 0.6
var last_error: String = ""
var _committing: bool = false
var jobs: Array[Dictionary] = []
@export var queue_capacity: int = 4

func _ready() -> void:
	super._ready()
	add_to_group(Groups.CRAFTING_STATIONS)

func request_craft(recipe_id: String) -> bool:
	var recipe := RecipeCatalog.find(recipe_id)
	if recipe == null or not can_operate() or _committing:
		last_error = "Workstation unavailable"
		return false
	if jobs.size() >= queue_capacity:
		last_error = "Queue full"
		return false
	var rv := get_connected_rv()
	if not rv.has_usable_power(recipe.power_cost):
		last_error = "Insufficient battery charge"
		return false
	_committing = true
	var accepted: bool = rv.deduct_materials(recipe.costs)
	if accepted:
		jobs.append({"id": InstanceIds.create(), "recipe": recipe.recipe_id, "remaining": recipe.duration, "costs": recipe.costs.duplicate(true), "power": recipe.power_cost, "rv": rv})
	_committing = false
	last_error = "Queued" if accepted else "Insufficient materials"
	return accepted

func step_work(delta: float) -> void:
	if jobs.is_empty() or not can_operate():
		return
	var job := jobs[0]
	var recipe := RecipeCatalog.find(job.recipe)
	if recipe == null:
		cancel_jobs()
		return
	var elapsed := minf(delta, job.remaining)
	var power_needed := minf(job.power, recipe.power_cost * elapsed / maxf(recipe.duration, 0.001))
	if power_needed > 0.0 and not consume_rv_power(power_needed):
		last_error = "Paused: battery empty"
		return
	job.power = maxf(0.0, job.power - power_needed)
	job.remaining = maxf(0.0, job.remaining - elapsed)
	if job.remaining <= 0.00001 and spawn_item(recipe.scene_path, {}, 0.0):
		jobs.pop_front()

func spawn_item(scene_path: String, costs: Dictionary = {}, power_cost: float = -1.0) -> bool:
	if _committing or not can_operate():
		last_error = "Workstation unavailable"
		return false
	var rv := get_connected_rv()
	var fee := power_cost_per_spawn if power_cost < 0.0 else power_cost
	if not rv.has_materials(costs) or not rv.has_usable_power(fee):
		last_error = "Insufficient materials or battery charge"
		return false
	if not ResourceLoader.exists(scene_path):
		last_error = "Output unavailable"
		return false
	var scene := load(scene_path) as PackedScene
	if scene == null:
		last_error = "Output unavailable"
		return false
	var instance := scene.instantiate()
	var item := instance as Prop
	if item == null:
		instance.free()
		last_error = "Invalid output"
		return false
	var output := spawn_marker.global_transform
	# A clearance sphere encloses current small products. Never debit a blocked output.
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.28
	query.shape = shape
	output.origin += global_basis.y * 0.3
	query.transform = output
	query.collision_mask = 1
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		item.free()
		last_error = "Output blocked"
		return false
	var container := WorldEntities.get_container(self)
	if not is_instance_valid(container) or container.is_queued_for_deletion():
		item.free()
		last_error = "Output unavailable"
		return false
	_committing = true
	if not rv.consume_power(fee):
		item.free()
		_committing = false
		return false
	if not rv.deduct_materials(costs):
		rv.add_power(fee)
		item.free()
		_committing = false
		return false
	container.add_child(item)
	if "battery" in item:
		item.battery.charge = 0.0
		item._update_label()
	item.global_transform = output
	item.linear_velocity = ClimbMath.point_velocity(rv, output.origin)
	_committing = false
	last_error = "Output ready"
	return true

func cancel_jobs() -> void:
	var cancelled := jobs.duplicate()
	jobs.clear()
	for job in cancelled:
		if is_instance_valid(job.rv):
			job.rv.deposit_materials(job.costs, true)

func _on_service_stopped() -> void:
	cancel_jobs()
