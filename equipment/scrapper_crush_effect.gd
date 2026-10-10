extends Node3D
## One bounded, reusable cosmetic rig per mounted recycler; no physics/save actors.
const DUST_SHADER := preload("res://equipment/scrapper_crush_dust.gdshader")
var working := false
var organic := false
var burst_count := 0
var work_age := 0.0
var _heartbeat := 0.0
var _input_id := 0
var emitters: Array[CPUParticles3D] = []
var dust_material: ShaderMaterial
var sound: AudioStreamPlayer3D
static var grinding_stream: AudioStreamWAV

func _ready() -> void:
	var chip := BoxMesh.new()
	chip.size = Vector3(.028, .006, .018)
	chip.material = _material(Color(.34, .37, .39), .8, .42)
	var flesh := SphereMesh.new()
	flesh.radius = .010; flesh.height = .030
	flesh.radial_segments = 5; flesh.rings = 2
	flesh.material = _material(Color(.28, .012, .024), 0, .25)
	var blood := SphereMesh.new()
	blood.radius = .0035; blood.height = .015
	blood.radial_segments = 5; blood.rings = 2
	blood.material = _material(Color(.43, .017, .026), 0, .22)
	var streak := BoxMesh.new()
	streak.size = Vector3(.002, .035, .002)
	var hot := _material(Color(1, .42, .065), 0, .6)
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.emission_enabled = true
	hot.emission = Color(1, .25, .02)
	hot.emission_energy_multiplier = 2.8
	streak.material = hot
	var cloud := QuadMesh.new()
	cloud.size = Vector2(.40, .40)
	dust_material = ShaderMaterial.new()
	dust_material.shader = DUST_SHADER
	cloud.material = dust_material
	_emitter("MetalChips", chip, 32, .55, 1.0, 2.5)
	_emitter("Dust", cloud, 24, .8, .2, .65).gravity = Vector3(0, .4, 0)
	_emitter("FleshChunks", flesh, 24, .5, .7, 2.0)
	_emitter("BloodSpray", blood, 100, .45, 1.0, 3.1)
	_emitter("Sparks", streak, 38, .24, 1.6, 3.5).set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	_emitter("ChipBurst", chip, 20, .55, 1.2, 3.2, true)
	_emitter("BloodBurst", blood, 48, .5, 1.5, 3.7, true)
	sound = AudioStreamPlayer3D.new()
	sound.name = "GrindingSound"
	sound.stream = _grinding_sound()
	sound.volume_db = -16
	sound.unit_size = 1.5
	sound.max_distance = 22
	add_child(sound)

static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _emitter(label: String, mesh: Mesh, count: int, life: float, speed_min: float, speed_max: float, burst := false) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = label
	particles.emitting = false
	particles.amount = count
	particles.lifetime = life
	particles.lifetime_randomness = .25
	particles.one_shot = burst
	particles.explosiveness = 1.0 if burst else 0.0
	particles.local_coords = false # Ejected fragments remain behind a moving RV.
	particles.mesh = mesh
	particles.direction = Vector3.UP
	particles.spread = 68
	particles.gravity = Vector3(0, -8, 0)
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.scale_amount_min = .5
	particles.scale_amount_max = 1.4
	particles.angle_min = -180; particles.angle_max = 180
	particles.angular_velocity_min = -240; particles.angular_velocity_max = 240
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(.055, .018, .25)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0, .12, .55, 1])
	fade.colors = PackedColorArray([Color(1,1,1,0), Color.WHITE, Color.WHITE, Color(1,1,1,0)])
	particles.color_ramp = fade
	add_child(particles)
	emitters.append(particles)
	return particles

func advance_work(delta: float, flesh_input: bool, local_contact: Vector3, progress: float, input_id: int) -> void:
	if delta <= 0: return
	organic = flesh_input
	working = true
	_heartbeat = .15
	work_age += delta
	position = local_contact
	$MetalChips.emitting = not organic
	$Sparks.emitting = not organic
	$FleshChunks.emitting = organic
	$BloodSpray.emitting = organic
	$Dust.emitting = true
	dust_material.set_shader_parameter("dust_color", Color(.28,.11,.10) if organic else Color(.38,.34,.28))
	dust_material.set_shader_parameter("density", .13 if organic else .24)
	if _input_id != input_id:
		_input_id = input_id
		impact(organic, local_contact)
	sound.pitch_scale = 1.0 + sin(work_age * 32) * .035 + progress * .08
	sound.volume_db = -18 if organic else -16
	if not sound.playing: sound.play()

func impact(flesh_input: bool, local_contact: Vector3) -> void:
	position = local_contact
	burst_count += 1
	var burst: CPUParticles3D = $BloodBurst if flesh_input else $ChipBurst
	burst.restart()
	burst.emitting = true

func stop(clear_particles := false) -> void:
	working = false
	_heartbeat = 0
	if sound != null: sound.stop()
	for emitter in emitters:
		if clear_particles and emitter.is_inside_tree(): emitter.restart()
		if not emitter.one_shot or clear_particles: emitter.emitting = false
	if clear_particles: _input_id = 0

func _process(delta: float) -> void:
	if not working: return
	_heartbeat -= delta
	var processor := get_parent()
	if _heartbeat <= 0 or not processor.is_powered_feed(): stop()

static func _grinding_sound() -> AudioStreamWAV:
	if grinding_stream != null: return grinding_stream
	grinding_stream = AudioStreamWAV.new()
	grinding_stream.format = AudioStreamWAV.FORMAT_16_BITS
	grinding_stream.mix_rate = 22050
	grinding_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	grinding_stream.loop_begin = 0
	grinding_stream.loop_end = 22050
	var bytes := PackedByteArray()
	bytes.resize(44100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61721
	var low := 0.0
	for i in 22050:
		var t := float(i) / 22050
		var white := rng.randf_range(-1,1)
		low = lerpf(low, white, .12)
		var tooth := pow(maxf(0, sin(t * TAU * 14)), 12)
		var sample := sin(t * TAU * 66) * .22 + sin(t * TAU * 132) * .10 + low * .40 + white * tooth * .13
		# Match the loop seam; a quiet motor with repeated hard tooth impacts.
		var seam := minf(1, minf(t, 1-t) * 150)
		bytes.encode_s16(i * 2, int(sample * seam * 24000))
	grinding_stream.data = bytes
	return grinding_stream
