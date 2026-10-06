extends Resource
class_name RVStructureDefinition
## Fixed structures have no Item placement, power or service lifecycle.
@export var type_id: String = ""
@export var display_name: String = ""
@export var scene_path: String = ""
@export var slot_kind: String = ""
@export var health: float = 120.0
@export var weight: float = 50.0
@export var allowed_conversions: Array[String] = []
@export var repair_cost: int = 2
@export var repair_seconds: float = 2.0
@export var repair_amount: float = 60.0
@export var rebuild_cost: int = 6
@export var rebuild_seconds: float = 6.0
@export var convert_cost: int = 2
@export var convert_seconds: float = 4.0
