extends Node3D
## Baked fuel fire and soot, surface dust, sparse sparks and bent barrel metal.
## Entirely cosmetic: no colliders, pickups, fire damage or save registrations.
const CLOUD_SHADER := preload("res://enemies/barrel_blast_cloud.gdshader")
const FLASH_SHADER := preload("res://enemies/barrel_blast_flash.gdshader")
const FLIPBOOK_SHADER := preload("res://enemies/barrel_blast_flipbook.gdshader")
const FIRE_ATLAS := preload("res://assets/effects/barrel_blast/fire_atlas.png")
const SMOKE_ATLAS := preload("res://assets/effects/barrel_blast/smoke_atlas.png")
const FRAGMENTS := preload("res://assets/effects/barrel_blast/fragments.glb")
const BOOM := preload("res://assets/effects/barrel_blast/blast.wav")
const METAL_LAND := [preload("res://assets/effects/barrel_blast/metal_land_1.wav"), preload("res://assets/effects/barrel_blast/metal_land_2.wav"), preload("res://assets/effects/barrel_blast/metal_land_3.wav")]
const TURBULENCE := preload("res://assets/effects/barrel_blast/turbulence.png")
const DURATION := 8.0
const MAX_LANDING_VOICES := 3
var age := 0.0
var flash: OmniLight3D
var core: MeshInstance3D
var ground_anchor: Node3D
var fire_material: ShaderMaterial
var smoke_material: ShaderMaterial
var dust_material: ShaderMaterial
var fragments: Array[Dictionary] = []
var landing_voices: Array[AudioStreamPlayer3D] = []
var landing_sound_count := 0
static var quad: QuadMesh

func _ready() -> void:
	name = "BarrelExplosionEffect"
	add_to_group("barrel_explosion_effects")
	_prepare_shared_resources()
	fire_material = _volume_material(FIRE_ATLAS, true)
	smoke_material = _volume_material(SMOKE_ATLAS, false)
	dust_material = _cloud_material(Color("777061"), .40)
	_add_volume("FuelFire", fire_material)
	_add_volume("RollingSoot", smoke_material)
	_add_ground_wave()
	_add_sparks_and_fragments()
	core = MeshInstance3D.new()
	core.name = "PressureFlash"
	core.mesh = quad
	core.material_override = _flash_material()
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

func _physics_process(delta: float) -> void:
	# Swept rays catch fast debris without adding bodies to gameplay physics.
	for fragment in fragments:
		if fragment.settled: continue
		var mesh: MeshInstance3D = fragment.mesh
		var velocity: Vector3 = fragment.velocity
		velocity += Vector3.DOWN * 9.8 * delta
		var start := mesh.global_position
		var destination := start + velocity * delta
		var hit := _support_ray(start, destination - Vector3.UP * float(fragment.radius))
		if not hit.is_empty() and velocity.dot(hit.normal) < 0.0:
			var normal: Vector3 = hit.normal
			var impact := -velocity.dot(normal)
			mesh.global_position = hit.position + normal * float(fragment.radius)
			velocity = velocity.slide(normal) * .58 + normal * impact * .27
			fragment.spin *= .45
			fragment.bounces += 1
			if not fragment.landed:
				fragment.landed = true
				if impact > 2.0: _play_metal_landing(mesh.global_position, impact)
			if velocity.length() < .9 or fragment.bounces >= 6:
				fragment.settled = true
				velocity = Vector3.ZERO
				# The exported lid lies in XZ; settle on the actual support normal.
				mesh.quaternion = Quaternion(Vector3.UP, normal) * Quaternion(Vector3.UP, fragment.rest_yaw)
		else:
			mesh.global_position = destination
		fragment.velocity = velocity
		if not fragment.settled:
			var spin: Vector3 = fragment.spin
			mesh.rotate_object_local(spin.normalized(), spin.length() * delta)

func _update_visuals() -> void:
	fire_material.set_shader_parameter("age", age)
	smoke_material.set_shader_parameter("age", age)
	# Hot fuel rises above a low barrel immediately, before a vehicle overruns it.
	var expansion := 1.0 - exp(-age * 24.0)
	var fire_scale := 1.0 + expansion * .55
	get_node("FuelFire").scale = Vector3(fire_scale, fire_scale, fire_scale)
	get_node("FuelFire").position.y = 1.25 * fire_scale + expansion * 1.3
	# The baked plume keeps rising gently while its last frames disperse.
	get_node("RollingSoot").position.y = 3.75 + (1.0 - exp(-age * 8.0)) * 1.3 + maxf(0.0, age - .5) * .25
	dust_material.set_shader_parameter("age", age)
	dust_material.set_shader_parameter("heat", 0.0)
	core.visible = age < .16
	if core.visible:
		core.scale = Vector3.ONE * lerpf(.35, 1.6, clampf(age / .10, 0, 1))
		core.material_override.set_shader_parameter("opacity", pow(maxf(0, 1.0 - age / .16), 2.0) * .55)
	flash.light_energy = 7.0 * exp(-age * 13.0) + 1.4 * maxf(0.0, 1.0 - age / .85)
	flash.visible = age < .85
	var metal_alpha := 1.0 - smoothstep(6.5, DURATION, age)
	for fragment in fragments:
		for material: StandardMaterial3D in fragment.materials:
			if age > 6.5: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = metal_alpha

func _add_volume(label: String, material: ShaderMaterial) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var is_fire := label == "FuelFire"
	# Real 3D proxy bounds cover all shader samples, including an eye inside it.
	# A flat billboard can be clipped before its fragment shader even runs.
	var volume := BoxMesh.new()
	var size := 5.0 if is_fire else 10.0
	volume.size = Vector3.ONE * size
	material.set_shader_parameter("volume_size", size)
	mesh.mesh = volume
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fire uses tight 4 m / +1 m framing; soot uses 8 m / +3 m. Both at 1.25x.
	add_child(mesh)
	mesh.global_position = global_position + Vector3.UP * (1.25 if is_fire else 3.75)

func _entity_domain(node: Node) -> Node:
	var cursor := node
	while cursor != null:
		if cursor.has_meta("entity_domain"): return cursor
		cursor = cursor.get_parent()
	return get_tree().current_scene

func _is_support(body: Object) -> bool:
	if not body is Node3D or not WorldEntities.same_world(self, body): return false
	if _entity_domain(body) != _entity_domain(self): return false
	# Actor limbs, loose cargo and Item-owned collision parts are never supports.
	var cursor := body as Node
	while cursor != null:
		if cursor is Item or cursor is CharacterBody3D or cursor.is_in_group("player_detached_parts"): return false
		cursor = cursor.get_parent()
	return body is StaticBody3D or body is RVStructurePanel or body is Chassis

func _support_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var omitted: Array[RID] = []
	for attempt in 16:
		query.exclude = omitted
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {}
		if _is_support(hit.collider): return hit
		omitted.append(hit.rid)
	return {}

func _add_ground_wave() -> void:
	var hit := _support_ray(global_position + Vector3.UP * .15, global_position + Vector3.DOWN * 2.5)
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < .45: return
	ground_anchor = Node3D.new()
	ground_anchor.name = "GroundDustAnchor"
	add_child(ground_anchor)
	ground_anchor.global_position = hit.position + hit.normal * .045
	ground_anchor.quaternion = Quaternion(Vector3.UP, hit.normal)
	var dust := _burst("SurfaceDust", 14, 1.65, quad, 2.4, 4.6)
	dust.position = ground_anchor.position + Vector3.UP * .12
	dust.material_override = dust_material
	dust.direction = Vector3.RIGHT
	dust.spread = 180; dust.flatness = 1.0
	dust.gravity = Vector3(0, .28, 0)
	dust.damping_min = 3.5; dust.damping_max = 5.0
	dust.scale_amount_min = .35; dust.scale_amount_max = .6
	dust.scale_amount_curve = _curve([Vector2(0,.25), Vector2(.18,.8), Vector2(1,2.3)])
	dust.color_ramp = _alpha([.65, .5, .20, 0.0])

func _add_sparks_and_fragments() -> void:
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(.025, .14)
	var sparks := _burst("HotSparks", 10, 1.05, spark_mesh, 4.5, 9.0)
	sparks.material_override = _flash_material()
	sparks.material_override.set_shader_parameter("velocity_aligned", true)
	sparks.particle_flag_align_y = true
	sparks.gravity = Vector3(0, -7.5, 0)
	sparks.damping_min = 1.3; sparks.damping_max = 2.2
	sparks.scale_amount_min = .55; sparks.scale_amount_max = 1.2
	sparks.color_ramp = _alpha([1.0, 1.0, .7, 0.0])
	var model := FRAGMENTS.instantiate()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for index in meshes.size():
		var original := meshes[index] as MeshInstance3D
		var mesh := original.duplicate() as MeshInstance3D
		add_child(mesh)
		var is_lid := mesh.name == "BarrelLid"
		var angle := float(index) * TAU / maxf(meshes.size(), 1) + randf_range(-.25, .25)
		var outward := Vector3(cos(angle), 0, sin(angle))
		mesh.global_position = global_position + outward * .22 + Vector3.UP * (.25 if is_lid else randf_range(-.15, .25))
		mesh.rotation = Vector3(randf_range(-.7,.7), angle, randf_range(-.7,.7))
		var materials: Array[StandardMaterial3D] = []
		for surface in mesh.mesh.get_surface_count():
			var source_material := mesh.get_active_material(surface) as StandardMaterial3D
			if source_material != null:
				var material := source_material.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, material)
				materials.append(material)
		fragments.append({"mesh": mesh, "velocity": outward * randf_range(1.2, 3.6) + Vector3.UP * (6.4 if is_lid else randf_range(3.1, 5.4)), "spin": Vector3(randf_range(2, 6), randf_range(-4, 4), randf_range(2, 6)), "radius": .10 if is_lid else .07, "rest_yaw": angle, "landed": false, "settled": false, "bounces": 0, "materials": materials})
	model.free()

func _play_metal_landing(at: Vector3, speed: float) -> void:
	# One strong first landing per fragment; at most three voices and five hits.
	for index in range(landing_voices.size() - 1, -1, -1):
		if not is_instance_valid(landing_voices[index]) or not landing_voices[index].playing: landing_voices.remove_at(index)
	if landing_voices.size() >= MAX_LANDING_VOICES or landing_sound_count >= 5: return
	var sound := AudioStreamPlayer3D.new()
	sound.name = "MetalLanding"
	sound.stream = METAL_LAND[landing_sound_count % METAL_LAND.size()]
	sound.volume_db = lerpf(-14.0, -10.0, clampf((speed - 2.0) / 7.0, 0, 1))
	sound.pitch_scale = randf_range(.94, 1.06)
	sound.max_distance = 28.0
	sound.unit_size = 3.0
	add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	landing_voices.append(sound)
	landing_sound_count += 1
	sound.play()

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

static func _volume_material(atlas: Texture2D, fire: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLIPBOOK_SHADER
	# Emission is extracted from the same smoke render and composited over it.
	material.render_priority = 1 if fire else 0
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("is_fire", fire)
	return material

static func _cloud_material(color: Color, density: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter("turbulence", TURBULENCE)
	material.set_shader_parameter("smoke_color", color)
	material.set_shader_parameter("density", density)
	return material

static func _flash_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLASH_SHADER
	material.set_shader_parameter("tint", Color("ffdc91"))
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
