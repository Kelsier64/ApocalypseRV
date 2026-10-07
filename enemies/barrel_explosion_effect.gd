extends Node3D
## Brief pressure flash, rolling fuel fire, rising soot, dust, sparks and metal.
## Entirely cosmetic: no colliders, pickups, fire damage or save registrations.
const CLOUD_SHADER := preload("res://enemies/barrel_blast_cloud.gdshader")
const FLASH_SHADER := preload("res://enemies/barrel_blast_flash.gdshader")
const DURATION := 3.8
var age := 0.0
var flash: OmniLight3D
var core: MeshInstance3D
var ring: MeshInstance3D
var fire_material: ShaderMaterial
var smoke_material: ShaderMaterial
var dust_material: ShaderMaterial
const BOOM := preload("res://assets/effects/barrel_blast/blast.wav")
const TURBULENCE := preload("res://assets/effects/barrel_blast/turbulence.png")
static var quad: QuadMesh

func _ready() -> void:
	name = "BarrelExplosionEffect"
	add_to_group("barrel_explosion_effects")
	_prepare_shared_resources()
	fire_material = _cloud_material(Color("26221d"), 1.0)
	smoke_material = _cloud_material(Color("363330"), .85)
	dust_material = _cloud_material(Color("777061"), .48)
	var fire := _burst("FuelFire", 22, .85, quad, 1.8, 4.3)
	fire.material_override = fire_material
	fire.gravity = Vector3(0, 1.6, 0)
	fire.damping_min = 2.8; fire.damping_max = 4.0
	fire.scale_amount_min = .65; fire.scale_amount_max = 1.10
	fire.scale_amount_curve = _curve([Vector2(0,.25), Vector2(.18,1.15), Vector2(.65,1.50), Vector2(1,1.70)])
	fire.color_ramp = _alpha([1.0, 1.0, .80, 0.0])
	var smoke := _burst("RollingSoot", 18, 3.15, quad, .5, 1.8)
	smoke.material_override = smoke_material
	smoke.direction = Vector3.UP; smoke.spread = 72
	smoke.gravity = Vector3(0, .65, 0)
	smoke.damping_min = .65; smoke.damping_max = 1.15
	smoke.scale_amount_min = .80; smoke.scale_amount_max = 1.3
	smoke.scale_amount_curve = _curve([Vector2(0,.35), Vector2(.12,.85), Vector2(.5,1.6), Vector2(1,2.1)])
	smoke.color_ramp = _alpha([0.0, .83, .58, 0.0])
	_add_ground_wave()
	_add_sparks_and_fragments()
	core = MeshInstance3D.new()
	core.name = "PressureFlash"
	core.mesh = quad
	core.material_override = _flash_material(false)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	flash = OmniLight3D.new()
	flash.name = "FireLight"
	flash.light_color = Color(1, .51, .14)
	flash.omni_range = 8.0
	flash.light_energy = 7.0
	# A single short-lived shadowed light avoids illuminating a sealed room.
	flash.shadow_enabled = true
	add_child(flash)
	var sound := AudioStreamPlayer3D.new()
	sound.name = "PressureAndDebris"
	sound.stream = BOOM
	sound.max_distance = 75.0
	sound.unit_size = 8.0
	sound.volume_db = -3.0
	add_child(sound)
	sound.play()
	_update_visuals()

func _process(delta: float) -> void:
	age += delta
	_update_visuals()
	if age >= DURATION: queue_free()

func _update_visuals() -> void:
	fire_material.set_shader_parameter("age", age)
	fire_material.set_shader_parameter("heat", maxf(0.0, 1.15 - age * 1.65))
	smoke_material.set_shader_parameter("age", age)
	smoke_material.set_shader_parameter("heat", maxf(0.0, .52 - age * .85))
	dust_material.set_shader_parameter("age", age)
	dust_material.set_shader_parameter("heat", 0.0)
	core.visible = age < .19
	if core.visible:
		core.scale = Vector3.ONE * lerpf(.4, 2.1, clampf(age / .12, 0, 1))
		core.material_override.set_shader_parameter("opacity", pow(maxf(0, 1.0 - age / .19), 2.0))
	if ring != null:
		ring.visible = age < .48
		if ring.visible:
			ring.scale = Vector3.ONE * lerpf(.3, 4.0, 1.0 - pow(1.0 - clampf(age / .48, 0, 1), 2.0))
			ring.material_override.set_shader_parameter("opacity", pow(maxf(0, 1.0 - age / .48), 1.5))
	flash.light_energy = 7.0 * exp(-age * 13.0) + 1.5 * maxf(0.0, 1.0 - age / .65)
	flash.visible = age < .65

func _add_ground_wave() -> void:
	# Only emit surface dust when a nearby solid floor/support actually exists.
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .15, global_position + Vector3.DOWN * 2.5)
	query.collide_with_areas = false
	var hit: Dictionary = {}
	# Bodies/limbs/loose cargo cannot turn a ground pressure wave into a halo.
	var omitted: Array[RID] = []
	for attempt in 12:
		query.exclude = omitted
		hit = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return
		var body: Object = hit.collider
		if body is StaticBody3D or body is RVStructurePanel or body is Chassis: break
		omitted.append(hit.rid)
		hit = {}
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < .45: return
	var at: Vector3 = to_local(hit.position + hit.normal * .045)
	ring = MeshInstance3D.new()
	ring.name = "GroundPressureRing"
	ring.mesh = quad
	ring.material_override = _flash_material(true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = at
	ring.quaternion = Quaternion(Vector3.BACK, hit.normal)
	var dust := _burst("SurfaceDust", 16, 1.55, quad, 3.5, 6.0)
	dust.position = at + Vector3.UP * .12
	dust.material_override = dust_material
	dust.direction = Vector3.RIGHT
	dust.spread = 180; dust.flatness = 1.0
	dust.gravity = Vector3(0, .28, 0)
	dust.damping_min = 4.0; dust.damping_max = 5.5
	dust.scale_amount_min = .35; dust.scale_amount_max = .6
	dust.scale_amount_curve = _curve([Vector2(0,.25), Vector2(.18,.8), Vector2(1,2.3)])
	dust.color_ramp = _alpha([.7, .58, .25, 0.0])

func _add_sparks_and_fragments() -> void:
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(.035, .21)
	var sparks := _burst("HotSparks", 48, 1.05, spark_mesh, 4.5, 11.0)
	sparks.material_override = _flash_material(false)
	sparks.material_override.set_shader_parameter("velocity_aligned", true)
	sparks.particle_flag_align_y = true
	sparks.gravity = Vector3(0, -7.5, 0)
	sparks.damping_min = 1.3; sparks.damping_max = 2.2
	sparks.scale_amount_min = .55; sparks.scale_amount_max = 1.7
	sparks.color_ramp = _alpha([1.0, 1.0, .7, 0.0])
	var shard := BoxMesh.new()
	shard.size = Vector3(.095, .013, .18)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("214756")
	metal.metallic = .65; metal.roughness = .68
	metal.vertex_color_use_as_albedo = true
	metal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard.material = metal
	var debris := _burst("BarrelMetal", 16, 1.45, shard, 2.8, 6.0)
	debris.gravity = Vector3(0, -9.8, 0)
	debris.angular_velocity_min = -540; debris.angular_velocity_max = 540
	debris.scale_amount_min = .5; debris.scale_amount_max = 1.5
	debris.color_ramp = _alpha([1.0, 1.0, 1.0, 0.0])

func _burst(label: String, count: int, duration: float, particle_mesh: Mesh, min_speed: float, max_speed: float) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.name = label
	burst.emitting = false
	burst.amount = count
	burst.lifetime = duration
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.lifetime_randomness = .2
	burst.local_coords = false
	burst.mesh = particle_mesh
	burst.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.direction = Vector3.UP
	burst.spread = 180
	burst.initial_velocity_min = min_speed
	burst.initial_velocity_max = max_speed
	burst.angle_min = -180; burst.angle_max = 180
	burst.angular_velocity_min = -35; burst.angular_velocity_max = 35
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = .20
	add_child(burst)
	burst.emitting = true
	return burst

static func _prepare_shared_resources() -> void:
	if quad == null:
		quad = QuadMesh.new()
		quad.size = Vector2(2, 2)

static func _cloud_material(color: Color, density: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter("turbulence", TURBULENCE)
	material.set_shader_parameter("smoke_color", color)
	material.set_shader_parameter("density", density)
	return material

static func _flash_material(ground: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLASH_SHADER
	material.set_shader_parameter("ground_ring", ground)
	material.set_shader_parameter("tint", Color("cbb499") if ground else Color("ffdc91"))
	return material

static func _curve(points: Array[Vector2]) -> Curve:
	var curve := Curve.new()
	curve.max_value = 3.0
	for point in points: curve.add_point(point)
	return curve

static func _alpha(values: Array[float]) -> Gradient:
	var colors := PackedColorArray()
	var offsets := PackedFloat32Array()
	for index in values.size():
		colors.append(Color(1,1,1,values[index]))
		offsets.append(float(index) / float(values.size() - 1))
	var gradient := Gradient.new()
	gradient.colors = colors
	gradient.offsets = offsets
	return gradient
