extends Resource
class_name SlenderSpeakerSettings
## Runtime defaults; generation uses its own independently seeded planner.
@export var sight_range := 220.0
@export var sight_half_angle_degrees := 65.0
@export var confirm_time := 0.25
@export var patrol_speed := 4.0
@export var chase_speed := 45.0 / 3.6 # 45 km/h, in world metres per second.
@export var acceleration := 2.5
@export var braking := 6.0
@export_range(0.0, 1.0) var turn_speed_ratio := 0.45
@export var fast_turn_degrees := 45.0
@export var near_turn_degrees := 90.0
@export var head_yaw_degrees := 75.0
@export var head_pitch_degrees := 20.0
@export var head_turn_degrees := 120.0
@export var search_seconds := 8.0
@export var cabin_enter_speed := 6.0 / 3.6
@export var pursuit_enter_speed := 10.0 / 3.6
@export var cabin_enter_seconds := 0.5
@export var pursuit_enter_seconds := 0.75
@export var smash_windup := 1.8
@export var smash_lock_seconds := 0.5
@export var smash_recovery := 3.0
@export var smash_chassis_damage := 60.0
@export var smash_wall_damage := 60.0
@export var smash_equipment_damage := 60.0
@export var smash_player_damage := 40.0
@export var foot_player_damage := 40.0
@export var grab_windup := 1.0
@export var lift_seconds := 1.4
@export var hold_seconds := 2.0
@export var crush_seconds := 0.4
@export var impact_speed := 10.0
@export var stagger_seconds := 0.8
@export var stagger_cooldown := 8.0
