extends Resource
class_name WorldProfile
@export var generation_version: int = 5
## All distances are metres. Determinism includes the generation version.
# Older worlds retain their original collision strip.
var chunk_length: float = 150.0
var terrain_half_width: float:
	get: return 450.0 if generation_version >= 4 else 225.0
var terrain_step: float = 3.0
@export var road_width: float = 15.0
@export var narrow_width: float = 10.0
@export var road_shoulder: float = 14.0
@export var max_grade: float = 0.08
# Road crossfall is currently zero (below the 3% design ceiling).
var max_crossfall: float = 0.03
@export var min_turn_radius: float = 80.0
@export var region_length: float = 900.0
@export var region_transition: float = 240.0
@export var stop_spacing: float = 450.0
@export var stop_jitter: float = 75.0
var parking_size := Vector2(12.0, 24.0)
@export var decoration_density: float = 1.0
@export var chunks_ahead: int = 3
@export var chunks_behind: int = 2
