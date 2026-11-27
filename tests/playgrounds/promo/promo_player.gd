extends "res://player/player.gd"

## True while the free camera owns the keyboard. Follow and rail cameras leave
## the player in control so a take can be driven or played while filmed from outside.
var camera_locked := false
var invulnerable := false

func is_gameplay_input_blocked() -> bool:
	return camera_locked or super.is_gameplay_input_blocked()

## Apparitions judge gaze from the player's own view, not the filming camera.
func apparition_view_for(presentation: Camera3D) -> Camera3D:
	if super.is_gameplay_input_blocked() or not is_instance_valid(presentation): return null
	if presentation.get_meta(&"promo_camera", false) != true: return null
	return seated_in.seat_camera if is_instance_valid(seated_in) else camera

func _commit_health_loss(amount: float, cause: InjuryEffects.Cause, severed_limb := false) -> void:
	if not invulnerable: super._commit_health_loss(amount, cause, severed_limb)

func kill() -> void:
	if not invulnerable: super.kill()

func can_be_grabbed() -> bool:
	return not invulnerable and super.can_be_grabbed()

func begin_execution(owner: Node3D, anchor: Node3D, look_target: Node3D) -> bool:
	return not invulnerable and super.begin_execution(owner, anchor, look_target)

func complete_execution(owner: Node3D) -> bool:
	return not invulnerable and super.complete_execution(owner)

func apply_grab_bite(captor: Node3D, fatal: bool) -> void:
	if not invulnerable: super.apply_grab_bite(captor, fatal)

func crush_in_scrapper(owner: Node3D) -> bool:
	return not invulnerable and super.crush_in_scrapper(owner)

func sever_part(part: StringName, context: Dictionary = {}) -> bool:
	return not invulnerable and super.sever_part(part, context)

## Filming only: the game's crawl posture (low capsule, ground view, crawl speed) with
## every limb intact, for the trailer's thrown-clear shot.
var prone := false

func set_prone(value: bool) -> void:
	if prone == value: return
	prone = value
	if prone: crawl_transition_remaining = 0.0
	_apply_body_capabilities()

func is_crawling() -> bool:
	return prone or super.is_crawling()
