extends AudioStreamPlayer3D
## The head loudspeaker: a garbage-truck Für Elise that loops for the giant's
## whole life, including capture and execution. This player is the dry direct
## sound; the synced Echo child feeds the OutdoorEcho reverb bus.
##
## Distance shapes four cues every frame: level, brightness, stereo width and
## echo ratio. Godot's attenuation is disabled, but max_distance still scales
## both layers linearly to silence, so the curve below is tuned with it.

const FADE_SECONDS := 6.0

@export_group("Level")
## Direct level at or inside the reference distance.
@export var near_db := 8.0
## About the speaker height: a listener on the ground never gets closer.
@export var reference_distance := 15.0
## Level lost per doubling of distance, near-physical close up.
@export var near_slope_db := 6.0
## Per-doubling loss beyond the knee, so the warning still carries far.
@export var far_slope_db := 1.5
## Doublings beyond the reference distance over which the slope eases.
@export var knee_doublings := 5.0
@export_group("Distance cues")
## Cutoff of the built-in distance shelf. Its depth already grows as the
## level falls; a lower cutoff far away leaves only the mids.
@export var near_cutoff_hz := 8000.0
@export var far_cutoff_hz := 1500.0
## Precise placement close up, diffuse far away.
@export var near_panning := 1.0
@export var far_panning := 0.5
## Echo level relative to the direct layer.
@export var near_echo_db := -15.0
@export var far_echo_db := -4.0

@onready var echo: AudioStreamPlayer3D = $Echo
var _fade_elapsed := 0.0


func start() -> void:
	if not is_inside_tree() or stream == null or playing: return
	_fade_elapsed = 0.0
	volume_linear = 0.0
	echo.volume_linear = 0.0
	echo.stream = stream
	play()
	echo.play()


func halt() -> void:
	stop()
	echo.stop()


## Direct and echo levels in dB, shelf cutoff and panning strength at a listener distance.
func mix(distance: float) -> Dictionary:
	var doublings := log(maxf(distance, reference_distance) / reference_distance) / log(2.0)
	var eased := minf(doublings, knee_doublings)
	# The slope falls linearly from near to far across the knee, then stays far.
	var drop := near_slope_db * eased - (near_slope_db - far_slope_db) * eased * eased / (2.0 * knee_doublings) \
		+ far_slope_db * (doublings - eased)
	var far := smoothstep(0.0, knee_doublings, doublings)
	return {
		"direct_db": near_db - drop,
		"echo_db": near_db - drop + lerpf(near_echo_db, far_echo_db, far),
		"cutoff_hz": exp(lerpf(log(near_cutoff_hz), log(far_cutoff_hz), far)),
		"panning": lerpf(near_panning, far_panning, far),
	}


func _process(delta: float) -> void:
	if not playing: return
	_fade_elapsed = minf(_fade_elapsed + delta, FADE_SECONDS)
	var viewport := get_viewport()
	var listener: Node3D = viewport.get_audio_listener_3d()
	if listener == null: listener = viewport.get_camera_3d()
	if listener == null: return
	var levels := mix(listener.global_position.distance_to(global_position))
	var entrance := smoothstep(0.0, FADE_SECONDS, _fade_elapsed)
	volume_linear = entrance * db_to_linear(levels.direct_db)
	echo.volume_linear = entrance * db_to_linear(levels.echo_db)
	attenuation_filter_cutoff_hz = levels.cutoff_hz
	panning_strength = levels.panning
