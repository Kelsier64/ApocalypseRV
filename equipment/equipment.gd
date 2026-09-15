extends RigidBody3D
class_name Equipment

enum BottomFace { DOWN, UP, FRONT, BACK, LEFT, RIGHT }

@export var equipment_name: String = "Unknown Equipment"
@export var definition: EquipmentDefinition
@export var enabled: bool = true
var persistent_id: String = InstanceIds.create()
var support_lost: bool = false
var mount_support: Node3D = null
var _placement_physics: Dictionary = {}
var _placement_player: Node3D = null
signal availability_changed
signal removing
@export var ghost_material: Material
@export var bottom_face: BottomFace = BottomFace.DOWN # Which local face sticks to the surface (Mode 1)

@export_group("Durability")
@export var max_health: float = 120.0
@export var can_be_destroyed: bool = true
@export var destroy_on_zero_health: bool = true

## Returns the half-extents of the first BoxShape3D collision child, or mesh AABB fallback.
func get_half_extents() -> Vector3:
	return get_placement_bounds().size / 2.0

func get_placement_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for child in get_children():
		if child is CollisionShape3D and child.shape:
			var part: AABB = child.transform * child.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(part) if found else part
			found = true
	return bounds if found else AABB(-Vector3.ONE * 0.5, Vector3.ONE)

## Returns a correction Basis that rotates the equipment so [bottom_face] aligns with -Y.
## Applied before the placement orientation basis.
func get_bottom_face_correction() -> Basis:
	match bottom_face:
		BottomFace.DOWN:
			return Basis.IDENTITY
		BottomFace.UP:
			return Basis(Vector3.RIGHT, PI)
		BottomFace.BACK:
			return Basis(Vector3.RIGHT, PI / 2.0)
		BottomFace.FRONT:
			return Basis(Vector3.RIGHT, -PI / 2.0)
		BottomFace.LEFT:
			return Basis(Vector3.FORWARD, PI / 2.0)
		BottomFace.RIGHT:
			return Basis(Vector3.FORWARD, -PI / 2.0)
	return Basis.IDENTITY

var original_local_transform: Transform3D
var original_parent: Node
var is_being_placed: bool = false
var original_materials: Dictionary = {} # GeometryInstance3D -> Material
var hold_timer: float = 0.0
var current_health: float = 0.0
var is_destroyed: bool = false
var _collision_exception_objects: Array = [] # CollisionObject3D exceptions we added
var _connected_rv_cache: Node3D = null # Only ever holds a verified hit; misses are re-scanned

func _ready():
	if definition:
		equipment_name = definition.display_name
		mass = definition.weight
		max_health = definition.health
	if not ghost_material:
		# Create a default transparent green material
		ghost_material = StandardMaterial3D.new()
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)

	current_health = maxf(max_health, 0.0)
	add_to_group(Groups.EQUIPMENT)
	if can_be_destroyed:
		add_to_group(Groups.MONSTER_DAMAGEABLE)
	call_deferred("_initialize_mount")

func _initialize_mount() -> void:
	var rv := refresh_rv_connection()
	if rv and not is_being_placed:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		collision_layer = 1
		collision_mask = 0
		_add_collision_exceptions_with_ancestors(get_parent())
		if not is_instance_valid(mount_support):
			set_mount_support(rv)

func can_operate() -> bool:
	return enabled and not support_lost and not is_being_placed and not is_destroyed and current_health > 0.0 and get_connected_rv() != null

func set_enabled(value: bool) -> void:
	enabled = value
	availability_changed.emit()

func _on_service_stopped() -> void:
	pass

## Adds (and tracks) collision exceptions with every CollisionObject3D ancestor,
## so a later re-placement can undo them instead of leaking stale exceptions.
func _add_collision_exceptions_with_ancestors(start: Node) -> void:
	var current := start
	while current != null and current is Node3D:
		if current is CollisionObject3D and not _collision_exception_objects.has(current):
			add_collision_exception_with(current)
			_collision_exception_objects.append(current)
		current = current.get_parent()

func _clear_tracked_collision_exceptions() -> void:
	for obj in _collision_exception_objects:
		if is_instance_valid(obj):
			remove_collision_exception_with(obj)
	_collision_exception_objects.clear()

## Revalidate after placement and lazily for scene initialization/reparenting.
## Null results are not sticky: the RV may register its groups after its children.
func get_connected_rv() -> Node3D:
	if RVConnection.is_rv(_connected_rv_cache) and _connected_rv_cache.is_ancestor_of(self):
		return _connected_rv_cache
	return refresh_rv_connection()

func refresh_rv_connection() -> Node3D:
	var previous := _connected_rv_cache
	_connected_rv_cache = RVConnection.resolve(get_parent())
	if previous != _connected_rv_cache:
		if is_instance_valid(previous) and previous.has_method("unregister_equipment"):
			previous.unregister_equipment(self)
		if _connected_rv_cache and _connected_rv_cache.has_method("register_equipment"):
			_connected_rv_cache.register_equipment(self)
	return _connected_rv_cache

func consume_rv_power(amount: float) -> bool:
	if not can_operate():
		return false
	if amount <= 0.0:
		return true
	var rv := get_connected_rv()
	if not rv:
		return false
	if not rv.has_method("consume_power"):
		return false
	return rv.consume_power(amount)

# Called when the player successfully holds F for 2 seconds
func start_placement(player: Node3D):
	if is_being_placed or is_destroyed: return
	# The player is the mode authority: refuse when it is seated/in UI/etc.
	if not player.enter_equipment_placement(self):
		return

	is_being_placed = true
	_placement_player = player
	_placement_physics = {"freeze": freeze, "freeze_mode": freeze_mode, "layer": collision_layer,
		"mask": collision_mask, "linear": linear_velocity, "angular": angular_velocity}
	original_local_transform = transform
	original_parent = get_parent()
	_on_service_stopped()
	availability_changed.emit()

	# Disable physics
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0

	# Apply ghost material to all immediate meshes
	_apply_ghost_material(self)

func _apply_ghost_material(node: Node):
	if node is GeometryInstance3D:
		original_materials[node] = node.material_override
		node.material_override = ghost_material
		
	for child in node.get_children():
		_apply_ghost_material(child)

func restore_original_materials(node: Node):
	if node is GeometryInstance3D:
		if original_materials.has(node):
			node.material_override = original_materials[node]
			
	for child in node.get_children():
		restore_original_materials(child)

func confirm_placement(new_global_transform: Transform3D, new_parent: Node3D, support: Node3D = null):
	is_being_placed = false
	visible = true
	global_transform = new_global_transform
	
	if new_parent and new_parent != get_parent():
		get_parent().remove_child(self)
		new_parent.add_child(self)
		# Needs to re-assert global transform after reparenting
		global_transform = new_global_transform
		
	# Keep physics frozen when glued to a car or ground so it doesn't slide
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	
	# CRITICAL: Prevent the car from launching into space!
	# We explicitly tell Godot's physics engine to NEVER calculate collisions
	# between this equipment and its new parent (e.g. the RV).
	_clear_tracked_collision_exceptions()
	_add_collision_exceptions_with_ancestors(new_parent)
	refresh_rv_connection()
	set_mount_support(support if support else new_parent)


	collision_layer = 1 
	collision_mask = 0 
	
	restore_original_materials(self)
	original_materials.clear()
	_placement_player = null
	availability_changed.emit()
	print(equipment_name, " placed successfully.")

func cancel_placement():
	if not is_being_placed:
		return
	is_being_placed = false
	visible = true
	
	if not is_instance_valid(original_parent):
		detach_from_support()
		return
	if original_parent != get_parent():
		get_parent().remove_child(self)
		original_parent.add_child(self)
		
	transform = original_local_transform

	# Restore exceptions to match the original parent chain
	_clear_tracked_collision_exceptions()
	_add_collision_exceptions_with_ancestors(original_parent)
	refresh_rv_connection()

	freeze = _placement_physics.get("freeze", false)
	freeze_mode = _placement_physics.get("freeze_mode", 0)
	collision_layer = _placement_physics.get("layer", 1)
	collision_mask = _placement_physics.get("mask", 1)
	linear_velocity = _placement_physics.get("linear", Vector3.ZERO)
	angular_velocity = _placement_physics.get("angular", Vector3.ZERO)
	restore_original_materials(self)
	original_materials.clear()
	_placement_player = null
	availability_changed.emit()
	print(equipment_name, " placement cancelled. Returned to original spot.")

func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if not can_be_destroyed or is_destroyed or current_health <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	availability_changed.emit()
	print(equipment_name, " took ", amount, " damage. HP: ", current_health, "/", max_health)

	if current_health <= 0.0 and destroy_on_zero_health:
		_destroy_equipment()
	elif current_health <= 0.0:
		_on_service_stopped()
		remove_from_group(Groups.MONSTER_DAMAGEABLE)

func _destroy_equipment() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	removing.emit()
	_on_service_stopped()
	if is_instance_valid(_placement_player):
		_placement_player.placement.placing_equipment = null
	_placement_player = null
	_on_before_destroy()
	queue_free()

func set_mount_support(support: Node3D) -> void:
	if is_instance_valid(mount_support):
		if mount_support.tree_exiting.is_connected(_support_removed):
			mount_support.tree_exiting.disconnect(_support_removed)
		if mount_support.has_signal("removing") and mount_support.removing.is_connected(_support_removed):
			mount_support.removing.disconnect(_support_removed)
	mount_support = support if support != self else null
	support_lost = false
	if is_instance_valid(mount_support):
		mount_support.tree_exiting.connect(_support_removed)
		if mount_support.has_signal("removing"):
			mount_support.removing.connect(_support_removed)

func _support_removed() -> void:
	support_lost = true
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_on_service_stopped()
	detach_from_support.call_deferred()

func detach_from_support() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var rv := get_connected_rv()
	var inherited_velocity := ClimbMath.point_velocity(rv, global_position)
	var container := WorldEntities.get_container(self)
	if not is_instance_valid(container) or container.is_queued_for_deletion():
		return
	set_mount_support(null)
	removing.emit()
	_on_service_stopped()
	is_being_placed = false
	if is_instance_valid(_placement_player):
		_placement_player.placement.placing_equipment = null
	_placement_player = null
	reparent(container)
	_clear_tracked_collision_exceptions()
	refresh_rv_connection()
	freeze = false
	collision_layer = 1
	collision_mask = 1
	linear_velocity = inherited_velocity
	visible = true
	restore_original_materials(self)
	original_materials.clear()
	availability_changed.emit()

func _exit_tree() -> void:
	_on_service_stopped()
	if is_instance_valid(_connected_rv_cache) and _connected_rv_cache.has_method("unregister_equipment"):
		_connected_rv_cache.unregister_equipment(self)
	_connected_rv_cache = null

func _on_before_destroy() -> void:
	# Override in subclasses that need cleanup before removal.
	pass

func needs_repair() -> bool:
	return not is_destroyed and current_health < max_health

func repair_health(amount: float) -> void:
	if not is_destroyed:
		current_health = minf(max_health, current_health + maxf(amount, 0.0))
		if current_health > 0.0 and can_be_destroyed:
			add_to_group(Groups.MONSTER_DAMAGEABLE)
		availability_changed.emit()
