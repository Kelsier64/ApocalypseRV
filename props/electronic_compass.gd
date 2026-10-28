extends Item
class_name ElectronicCompass
## Read-only navigation display. Item identity/state stay in the shared contract.
const SIGNAL_RANGE := 2000.0
const SCAN_INTERVAL := 1.0
var target_site: Dictionary = {}
var target_distance := 0.0
var target_bearing := 0.0
var _field: WorldField
var _locator: BuildingLocator
var _scan_thread: Thread
var _request_field: WorldField
var _request_locator: BuildingLocator
var _scan_epoch := 0
var _request_epoch := 0
var _scan_remaining := 0.0
var _last_scan := Vector3.INF
@onready var screen: Control = $Display/Screen

func _ready() -> void:
	super._ready()
	# A per-instance texture prevents another compass from changing this screen.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = $Display.get_texture()
	$Visuals/Screen.material_override = material

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var holder := _holder()
	if holder == null or is_being_placed or not enabled or condition <= 0.0:
		_clear_signal("STANDBY")
		return
	# Resolve through this holder's ancestry and World3D, never another world's
	# generator (for example the outdoor world while exploring an interior).
	var field := _holder_field(holder)
	if field == null:
		if _field != null: _scan_epoch += 1
		_field = null
		_locator = null
		_clear_signal("NO SIGNAL")
		return
	if field != _field:
		_scan_epoch += 1
		_field = field
		# The worker owns separate deterministic caches. The live generator's
		# dictionaries must never be read/mutated concurrently by a locator.
		_locator = BuildingLocator.new(WorldField.new(field.world_seed, field.profile.duplicate(true)))
		target_site = {}
		_scan_remaining = 0.0
	var origin := holder.global_position
	_scan_remaining -= delta
	if _scan_thread != null and not _scan_thread.is_alive():
		var result: Dictionary = _scan_thread.wait_to_finish()
		_scan_thread = null
		_request_locator = null
		if _request_field == _field and _request_epoch == _scan_epoch: target_site = result
	if _scan_thread == null and (_scan_remaining <= 0.0 or origin.distance_squared_to(_last_scan) > 400.0):
		_scan_thread = Thread.new()
		_request_field = _field
		_request_epoch = _scan_epoch
		# Callable alone does not retain a RefCounted target during a domain
		# change. Keep the in-flight locator alive until its thread is joined.
		_request_locator = _locator
		var error := _scan_thread.start(_request_locator.nearest.bind(origin, SIGNAL_RANGE))
		if error == OK:
			_last_scan = origin
			_scan_remaining = SCAN_INTERVAL
		else:
			_scan_thread = null
			_request_locator = null
			_scan_remaining = SCAN_INTERVAL
	if target_site.is_empty():
		_clear_signal("SCANNING" if _scan_thread != null else "NO SIGNAL")
		return
	var target: Vector3 = target_site.building.origin
	var offset := target - origin
	target_distance = Vector2(offset.x, offset.z).length()
	if target_distance > SIGNAL_RANGE:
		_clear_signal("NO SIGNAL")
		return
	target_bearing = bearing(offset, -holder.global_basis.z)
	screen.show_reading(target_bearing, target_distance, "ARRIVED" if target_distance < 5.0 else "BUILDING")

static func bearing(offset: Vector3, forward: Vector3) -> float:
	forward.y = 0.0
	if forward.length_squared() < 0.000001: forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return atan2(offset.dot(right), offset.dot(forward))

func _clear_signal(status: String) -> void:
	target_site = {}
	target_distance = 0.0
	target_bearing = 0.0
	screen.show_reading(0.0, -1.0, status)

func _holder() -> Node3D:
	if not presentation_only: return null
	var node := get_parent()
	while node != null:
		if node is CharacterBody3D and "held_item_node" in node:
			return node if node.held_item_node == self else null
		node = node.get_parent()
	return null

func _holder_field(holder: Node3D) -> WorldField:
	var node: Node = holder
	while node != null:
		var generator := node.get_node_or_null("WorldGenerator") as Node3D
		if generator != null and WorldEntities.same_world(holder, generator) and "field" in generator:
			return generator.field
		if node.has_meta("entity_domain"): break
		node = node.get_parent()
	return null

func _exit_tree() -> void:
	if _scan_thread != null:
		_scan_thread.wait_to_finish()
		_scan_thread = null
	_request_locator = null
	super._exit_tree()
