extends Item
class_name Pistol
## World data is captured normally; held copies are presentation only.
var loaded_rounds := PistolRules.MAGAZINE_CAPACITY
var _shot_time := 0.0
var _reload_progress := -1.0
var _slide: Node3D
var _magazine: Node3D
const SHOT_SOUND: SoundEvent = preload("res://assets/audio/events/pistol/shot.tres")
const EMPTY_SOUND: SoundEvent = preload("res://assets/audio/events/pistol/dry_fire.tres")
const RELOAD_SOUND: SoundEvent = preload("res://assets/audio/events/pistol/reload.tres")

func _ready() -> void:
	super._ready()
	_slide = find_child("Slide", true, false) as Node3D
	_magazine = find_child("Magazine", true, false) as Node3D
	set_process(presentation_only)

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["pistol"] = {"loaded_rounds": loaded_rounds}
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	loaded_rounds = int(state.get("pistol", {}).get("loaded_rounds", PistolRules.MAGAZINE_CAPACITY))

func muzzle_position() -> Vector3:
	return $Muzzle.global_position

func play_shot() -> void:
	_shot_time = .10
	_play_sound(SHOT_SOUND)

func play_empty() -> void:
	_play_sound(EMPTY_SOUND)

func set_reload_progress(progress: float) -> void:
	if progress >= 0.0 and _reload_progress < 0.0: _play_sound(RELOAD_SOUND)
	# An interrupted reload goes silent; a shot tail still ringing stops with it.
	if progress < 0.0 and _reload_progress >= 0.0 and is_inside_tree(): get_node("/root/Sfx").stop_from(self)
	_reload_progress = progress
	if _magazine != null:
		_magazine.position.y = -.06 * sin(progress * PI) if progress >= 0.0 else 0.0

func _process(delta: float) -> void:
	_shot_time = maxf(0.0, _shot_time - delta)
	if _slide != null:
		_slide.position.z = .019 * sin(_shot_time / .10 * PI) if _shot_time > 0.0 else (.012 if loaded_rounds == 0 else 0.0)
	$Muzzle/Flash.visible = _shot_time > .060 and is_visible_in_tree()
	$Muzzle/Light.visible = _shot_time > .060 and is_visible_in_tree()

func play_tracer(from: Vector3, to: Vector3) -> void:
	var distance := from.distance_to(to)
	if distance < .001: return
	var tracer := MeshInstance3D.new()
	tracer.name = "PistolTracer"
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = .001
	mesh.bottom_radius = .0025
	mesh.height = distance
	mesh.radial_segments = 6
	mesh.rings = 0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, .86, .60, .85)
	material.emission_enabled = true
	material.emission = Color(1.0, .48, .12)
	material.emission_energy_multiplier = .6
	mesh.material = material
	tracer.mesh = mesh
	# World ownership keeps the shot fixed even if the player moves or unequips.
	WorldEntities.get_container(self).add_child(tracer)
	tracer.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, (to - from) / distance)), (from + to) * .5)
	var tween := tracer.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, .09)
	tween.tween_callback(tracer.queue_free)

func play_impact(point: Vector3, normal: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .024
	mesh.height = .048
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, .70, .23)
	mesh.material = material
	spark.mesh = mesh
	WorldEntities.get_container(self).add_child(spark)
	spark.global_position = point + normal * .012
	var tween := spark.create_tween()
	tween.tween_property(spark, "scale", Vector3.ONE * .08, .12)
	tween.tween_callback(spark.queue_free)

func _play_sound(event: SoundEvent) -> void:
	if is_inside_tree(): get_node("/root/Sfx").play(event, self, to_local(muzzle_position()) if event == SHOT_SOUND else Vector3.ZERO)
