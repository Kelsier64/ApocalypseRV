extends Resource
class_name ItemDefinition

@export var type_id: String = ""
@export var display_name: String = ""
@export var weight: float = 25.0
@export var health: float = 120.0
@export var requires_upright: bool = false
@export var placement_clearance: Vector3 = Vector3.ZERO
@export var clearance_center: Vector3 = Vector3.ZERO
@export var is_large: bool = true
@export var requires_rv_connection: bool = true
@export var scrap_yields: Dictionary = {"Metal Parts": Vector2(2, 2)}
