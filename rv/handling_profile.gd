class_name RVHandlingProfile
extends Resource

@export_group("Rollover")
@export var rollover_side_up_dot := 0.45
@export var rollover_inverted_up_dot := -0.7
@export var tilt_warning_roll := 0.42
@export var shell_scrape_min_speed := 2.0
@export var shell_scrape_damage_per_meter := 0.65
@export var tire_impact_puncture_damage := 45.0
@export var tire_side_impact_min_speed := 4.0
@export var tire_side_impact_damage_scale := 0.75

@export_group("Occupants")
@export var crash_injury_speed := 4.0
@export var crash_sever_speed := 10.0
@export var crash_lethal_speed := 14.0
@export var crash_seated_damage_scale := 0.5
@export var crash_seated_sever_scale := 0.3
@export var crash_damage_at_lethal_speed := 105.0
@export var crash_launch_lift := 2.0
@export var camera_inertia_scale := 0.035

@export_group("Suspension")
@export var base_center_of_mass := Vector3(0.0, 0.12, 0.0)
@export var suspension_rest_length := 0.3
@export var suspension_travel := 0.45
@export var suspension_stiffness := 32.0
@export var compression_damping := 2.2
@export var rebound_damping := 3.8
@export var max_suspension_force := 24000.0
@export var anti_roll_stiffness := 8500.0
@export var bump_stop_compression := 0.21
@export var bump_stop_stiffness := 45000.0

@export_group("Tires")
@export var asphalt_grip := 0.82
@export var shoulder_grip := 0.69
@export var offroad_grip := 0.56
@export var loose_surface_drag := 0.022
@export var rolling_drag := 0.009
@export var flat_grip := 0.45
@export var flat_rolling_drag := 0.12
@export var flat_radius_scale := 0.8
@export var flat_steering_scale := 0.55
@export var flat_alignment := 0.065
@export var tire_load_sensitivity := 0.15
@export var lateral_peak_angle := 0.13
@export var longitudinal_peak_slip := 0.15
@export var sliding_grip_fraction := 0.64
@export var wheel_inertia := 8.0
@export var wheel_spin_limit := 115.0

@export_group("Transmission")
@export var max_steering := 0.6
@export var high_speed_steering_ratio := 0.18
@export var steering_speed := 10.0
@export var gear_ratios := PackedFloat32Array([4.37, 2.19, 1.40, 1.0])
@export var reverse_torque_scale := 0.45
@export var engine_braking_force := 700.0
@export var front_brake_bias := 0.65

@export_group("Departure")
@export var departure_safe_landing_speed := 10.0
@export var departure_safe_slide_speed := 8.0
@export var departure_safe_wall_speed := 8.0
@export var departure_damage_scale := 0.45
@export var departure_ground_deceleration := 24.0
@export var departure_stagger_seconds := 0.4
