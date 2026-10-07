extends Resource
class_name BarrelManSettings
## Shared tuning for the actor, deterministic spawn policy and explosion resolver.
const ROAD_CHANCE := 0.10
const MINOR_CHANCE := 0.15
const BUNKER_CHANCE := 0.20

@export_group("Pursuit")
@export var player_detection_range := 8.0
@export var vehicle_detection_range := 12.0
@export var rise_duration := 0.8
@export var retract_duration := 0.8
@export var chase_speed := 6.0
@export var vehicle_speed_margin := 1.2
@export var vehicle_speed_cap := 10.0
@export var acceleration := 8.0
@export var lose_interest_range := 35.0
@export var lose_interest_time := 5.0
@export var max_health := 60.0
@export_group("Explosion")
@export_range(0.0, 10.0, 0.05) var proximity_trigger_radius := 3.0
@export_range(0.0, 60.0, 0.01) var proximity_fuse_duration := 2.0
@export var blast_radius := 4.0
@export var player_full_damage_radius := 1.5
@export var player_damage := 70.0
@export var double_limb_radius := 0.8
@export var shell_full_damage_radius := 2.0
@export var shell_damage := 120.0
@export var engine_damage := 60.0
