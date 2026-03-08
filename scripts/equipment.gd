extends RigidBody3D
class_name Equipment

@export var equipment_name: String = "Unknown Equipment"
@export var ghost_material: Material
@export var placement_offset: float = 0.0 # How much to push the origin up from the surface

var original_transform: Transform3D
var original_parent: Node
var is_being_placed: bool = false
var original_materials: Dictionary = {} # GeometryInstance3D -> Material
var hold_timer: float = 0.0

func _ready():
	if not ghost_material:
		# Create a default transparent green material
		ghost_material = StandardMaterial3D.new()
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)

# Called when the player successfully holds F for 2 seconds
func start_placement(player: Node3D):
	if is_being_placed: return
	
	is_being_placed = true
	original_transform = global_transform
	original_parent = get_parent()
	
	# Disable physics
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0
	
	# Apply ghost material to all immediate meshes
	_apply_ghost_material(self)
	
	player.enter_equipment_placement(self)

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

func confirm_placement(new_global_transform: Transform3D, new_parent: Node3D):
	is_being_placed = false
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
	var current = new_parent
	while current != null and current is Node3D:
		if current is CollisionObject3D:
			add_collision_exception_with(current)
		current = current.get_parent()
		
	collision_layer = 1 
	collision_mask = 0 
	
	restore_original_materials(self)
	print(equipment_name, " placed successfully.")

func cancel_placement():
	is_being_placed = false
	
	if original_parent and original_parent != get_parent():
		get_parent().remove_child(self)
		original_parent.add_child(self)
		
	global_transform = original_transform
	
	# Clear exceptions if we are canceling
	var current = get_parent()
	while current != null and current is Node3D:
		if current is CollisionObject3D:
			remove_collision_exception_with(current)
		current = current.get_parent()
		
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 1
	restore_original_materials(self)
	print(equipment_name, " placement cancelled. Returned to original spot.")
