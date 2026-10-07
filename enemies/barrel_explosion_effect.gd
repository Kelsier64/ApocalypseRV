extends Node3D
## Transient burst, blue barrel fragments and a spatial pressure/noise sound.
## No gameplay colliders, persistent fire, pickups, or save registrations.
var age := 0.0
var flash: OmniLight3D
static var boom: AudioStreamWAV

func _ready() -> void:
	name = "BarrelExplosionEffect"
	add_to_group("barrel_explosion_effects")
	var flame := SphereMesh.new()
	flame.radius = 0.22; flame.height = 0.44
	flame.radial_segments = 8; flame.rings = 4
	var fire := _burst(32, 0.5, flame, 2.0, 9.0)
	fire.gravity = Vector3(0, 1.5, 0)
	fire.color_ramp = _colors([Color(1, 0.9, 0.5, 1), Color(1, 0.28, 0.035, 0.85), Color(0.3, 0.04, 0.01, 0)])
	fire.mesh.material = _material(true)
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.27; smoke_mesh.height = 0.54
	smoke_mesh.radial_segments = 8; smoke_mesh.rings = 4
	var smoke := _burst(42, 1.8, smoke_mesh, 1.0, 3.5)
	smoke.gravity = Vector3(0, 0.8, 0)
	smoke.color_ramp = _colors([Color(0.24, 0.21, 0.17, 0.85), Color(0.12, 0.12, 0.11, 0.65), Color(0.12, 0.12, 0.11, 0)])
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.6)); growth.add_point(Vector2(0.4, 2.2)); growth.add_point(Vector2(1, 3.2))
	smoke.scale_amount_curve = growth
	smoke.mesh.material = _material(false)
	var shard := BoxMesh.new()
	shard.size = Vector3(0.10, 0.025, 0.15)
	var debris := _burst(24, 1.3, shard, 3.0, 8.0)
	debris.gravity = Vector3(0, -9.8, 0)
	debris.angular_velocity_min = -360; debris.angular_velocity_max = 360
	debris.color_ramp = _colors([Color(0.10, 0.25, 0.35), Color(0.10, 0.18, 0.25), Color(0.10, 0.18, 0.25, 0)])
	debris.mesh.material = _material(false)
	flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.35, 0.055)
	flash.omni_range = 9.0
	flash.light_energy = 8.0
	add_child(flash)
	if boom == null: boom = _make_boom()
	var sound := AudioStreamPlayer3D.new()
	sound.stream = boom
	sound.max_distance = 75.0
	sound.unit_size = 8.0
	sound.volume_db = -3.0
	add_child(sound)
	sound.play()

func _process(delta: float) -> void:
	age += delta
	flash.light_energy = 8.0 * maxf(0.0, 1.0 - age / 0.22)
	if age > 2.2: queue_free()

func _burst(count: int, duration: float, particle_mesh: Mesh, min_speed: float, max_speed: float) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.amount = count
	burst.lifetime = duration
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.randomness = 0.35
	burst.local_coords = false
	burst.mesh = particle_mesh
	burst.direction = Vector3.UP
	burst.spread = 180
	burst.initial_velocity_min = min_speed
	burst.initial_velocity_max = max_speed
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.20
	add_child(burst)
	burst.emitting = true
	return burst

static func _material(unshaded: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 1.0
	return material

static func _colors(colors: Array[Color]) -> Gradient:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	var positions := PackedFloat32Array()
	for i in colors.size(): positions.append(float(i) / maxf(colors.size() - 1, 1))
	gradient.offsets = positions
	return gradient

static func _make_boom() -> AudioStreamWAV:
	const RATE := 22050
	var data := PackedByteArray()
	data.resize(int(RATE * 1.2) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 830431
	var filtered := 0.0
	for i in data.size() / 2:
		var t := float(i) / RATE
		filtered = lerpf(filtered, rng.randf_range(-1, 1), 0.32)
		var sample := clampf((filtered * 1.8 + sin(TAU * (75 * t - 22 * t * t)) * 0.6) * exp(-5.5 * t) * minf(1, t * 1000), -1, 1)
		data.encode_s16(i * 2, int(sample * 29000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
