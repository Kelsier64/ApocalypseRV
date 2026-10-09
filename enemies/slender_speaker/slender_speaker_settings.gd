extends Resource
class_name SlenderSpeakerSettings
## Runtime defaults; generation uses its own independently seeded planner.
@export var sight_range := 220.0
@export var sight_half_angle_degrees := 65.0
@export var confirm_time := 0.25
@export var patrol_speed := 4.0
@export var chase_speed := 60.0 / 3.6 # 60 km/h, in world metres per second.
@export var acceleration := 2.5
@export var braking := 6.0
@export_range(0.0, 1.0) var turn_speed_ratio := 0.45
@export var fast_turn_degrees := 45.0
@export var near_turn_degrees := 90.0
@export var search_seconds := 8.0
@export var smash_windup := 1.8
@export var smash_lock_seconds := 0.5
@export var smash_recovery := 3.0
@export var grab_windup := 1.0
@export var lift_seconds := 1.4
@export var hold_seconds := 0.6
@export var crush_seconds := 0.4
@export var impact_speed := 10.0
@export var stagger_seconds := 0.8
@export var stagger_cooldown := 8.0
