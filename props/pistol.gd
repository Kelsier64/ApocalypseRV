extends Item
class_name Pistol
## World data is captured normally; held copies are presentation only.
var loaded_rounds := PistolRules.MAGAZINE_CAPACITY
var _shot_time := 0.0
var _reload_progress := -1.0
var _slide: Node3D
var _magazine: Node3D
var _sound: AudioStreamPlayer3D
static var _sounds: Dictionary = {}

func _ready() -> void:
	super._ready()
	_slide = find_child("Slide", true, false) as Node3D
	_magazine = find_child("Magazine", true, false) as Node3D
	_sound = AudioStreamPlayer3D.new()
	_sound.max_distance = 65.0
	_sound.unit_size = 8.0
	add_child(_sound)
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
	_play_sound("shot")

func play_empty() -> void:
	_play_sound("empty")

func set_reload_progress(progress: float) -> void:
	if progress >= 0.0 and _reload_progress < 0.0: _play_sound("reload")
	if progress < 0.0 and _reload_progress >= 0.0 and _sound != null: _sound.stop()
	_reload_progress = progress
	if _magazine != null:
		_magazine.position.y = -.06 * sin(progress * PI) if progress >= 0.0 else 0.0

func _process(delta: float) -> void:
	_shot_time = maxf(0.0, _shot_time - delta)
	if _slide != null:
		_slide.position.z = .019 * sin(_shot_time / .10 * PI) if _shot_time > 0.0 else (.012 if loaded_rounds == 0 else 0.0)
	$Muzzle/Flash.visible = _shot_time > .060 and is_visible_in_tree()
	$Muzzle/Light.visible = _shot_time > .060 and is_visible_in_tree()

func get_interaction_prompt(player: Node3D) -> String:
	return "手槍｜%d / %d 發\n%s" % [loaded_rounds, PistolRules.MAGAZINE_CAPACITY, super.get_interaction_prompt(player)]

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

func _play_sound(kind: String) -> void:
	if _sound == null: return
	if not _sounds.has(kind): _sounds[kind] = _make_sound(kind)
	_sound.stream = _sounds[kind]
	_sound.volume_db = -5.0 if kind == "shot" else -11.0
	_sound.play()

static func _make_sound(kind: String) -> AudioStreamWAV:
	# Original deterministic PCM: a short mechanical crack and low body,
	# separate magazine clicks. No downloaded recordings or runtime generators.
	var rate := 22050
	var duration := .38 if kind == "shot" else (1.4 if kind == "reload" else .09)
	var samples := PackedByteArray()
	samples.resize(int(rate * duration) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7201
	var smooth := 0.0
	for i in samples.size() / 2:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		smooth = lerpf(smooth, noise, .18)
		var value := 0.0
		if kind == "shot":
			value = noise * exp(-t * 74.0) * .68 + smooth * exp(-t * 17.0) * .55 + sin(TAU * (100.0 * t - 52.0 * t * t)) * exp(-t * 24.0) * .35
		else:
			var clicks: Array = [0.0, .32, 1.12] if kind == "reload" else [0.0]
			for start: float in clicks:
				var local := t - start
				if local >= 0.0: value += (noise * .40 + sin(local * TAU * 1700.0) * .18) * exp(-local * 90.0)
		samples.encode_s16(i * 2, int(clampf(value, -.98, .98) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	return stream
