extends Node3D
class_name WeatherRain
## GPU-animated world-space rain fields; CPU work is bounded by shelter sampling.
const NEAR_COUNT := 24576
const FAR_COUNT := 49152
const MAX_DROPS := NEAR_COUNT + FAR_COUNT
const NEAR_RADIUS := 24.0
const FAR_RADIUS := 96.0
const COVER_NEAR_BUDGET := 256
const COVER_FAR_BUDGET := 128
const SPLASH_QUERIES := 8
const MAX_RAYS := COVER_NEAR_BUDGET + COVER_FAR_BUDGET + SPLASH_QUERIES + 1
const MAX_SPLASHES := 64
const SPLASH_LIFETIME := 0.18
var clock: WorldClock
var rng := RandomNumberGenerator.new()
var fields: Array[MultiMeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var near_cover := RainCover.new(0.75)
var far_cover := RainCover.new(3.0)
var roof_transforms: Array[Transform3D] = []
var roof_sizes := PackedVector3Array()
var cover_exclusions: Array[RID] = []
var simulation_time := 0.0
var rain_active := false
var last_center := Vector3.INF
var splash_instance: MultiMeshInstance3D
var splash_material: ShaderMaterial
var splashes: Array[Dictionary] = []
var rays_last_tick := 0
var visible_drops := 0 # Submitted instances; shader shelter/fades reduce actual visibility.
var shelter := 0.0
var bus_name: String
var low_pass: AudioEffectLowPassFilter
var voices: Array[AudioStreamPlayer] = []
var listener: Node3D

func _ready() -> void:
	rng.seed = 73813
	_build_field(NEAR_COUNT, NEAR_RADIUS, 32.0, false)
	_build_field(FAR_COUNT, FAR_RADIUS, 48.0, true)
	splash_instance = MultiMeshInstance3D.new()
	splash_instance.multimesh = MultiMesh.new()
	splash_instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	splash_instance.multimesh.use_custom_data = true
	var splash_mesh := QuadMesh.new()
	splash_material = ShaderMaterial.new()
	splash_material.shader = preload("res://world/rain_splash.gdshader")
	splash_mesh.material = splash_material
	splash_instance.multimesh.mesh = splash_mesh
	splash_instance.multimesh.instance_count = MAX_SPLASHES
	splash_instance.multimesh.visible_instance_count = 0
	splash_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(splash_instance)
	listener = clock.get_parent().get_node_or_null("Player") as Node3D
	bus_name = "Weather_%d" % get_instance_id()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, bus_name)
	low_pass = AudioEffectLowPassFilter.new()
	AudioServer.add_bus_effect(bus, low_pass)
	for heavy in [false, true]:
		var voice := AudioStreamPlayer.new()
		voice.stream = make_rain_audio(heavy)
		voice.bus = bus_name
		voice.volume_db = -80
		add_child(voice)
		voice.play()
		voices.append(voice)

static func make_rain_audio(heavy: bool) -> AudioStreamWAV:
	var noise := RandomNumberGenerator.new()
	noise.seed = 917 if heavy else 319
	var data := PackedByteArray()
	const RATE := 22050
	const COUNT := RATE * 4
	data.resize(COUNT * 2)
	var filtered := 0.0
	for i in range(COUNT):
		var white := noise.randf_range(-1, 1)
		filtered = lerpf(filtered, white, 0.16 if heavy else 0.45)
		var value := (filtered * 0.7 + white * 0.15) * 18000.0
		# Fade only the seam to avoid an audible discontinuity in the loop.
		value *= minf(1.0, minf(float(i), float(COUNT - 1 - i)) / 128.0)
		data.encode_s16(i * 2, int(value))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = COUNT
	return stream

func _exit_tree() -> void:
	for voice in voices:
		voice.stop()
	var bus := AudioServer.get_bus_index(bus_name)
	if bus > 0: AudioServer.remove_bus(bus)

func _build_field(count: int, radius: float, height: float, distant: bool) -> void:
	var field := MultiMeshInstance3D.new()
	field.name = "DistantRain" if distant else "NearRain"
	field.multimesh = MultiMesh.new()
	field.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	field.multimesh.use_custom_data = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/rain_field.gdshader")
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("field_height", height)
	material.set_shader_parameter("distant", distant)
	material.set_shader_parameter("near_cover", near_cover.texture)
	material.set_shader_parameter("far_cover", far_cover.texture)
	mesh.material = material
	field.multimesh.mesh = mesh
	field.multimesh.instance_count = count
	# Seed data uploaded once. The vertex shader moves every drop without CPU loops.
	var seeds := RandomNumberGenerator.new()
	seeds.seed = 9481 if distant else 4371
	for i in range(count):
		field.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(seeds.randf_range(-radius, radius), seeds.randf_range(0, height), seeds.randf_range(-radius, radius))))
		field.multimesh.set_instance_custom_data(i, Color(seeds.randf(), seeds.randf(), seeds.randf(), seeds.randf()))
	field.multimesh.visible_instance_count = 0
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	fields.append(field)
	materials.append(material)

func ray_hit(from: Vector3, to: Vector3, static_only := false) -> Dictionary:
	rays_last_tick += 1
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.hit_from_inside = true
	if static_only: query.exclude = cover_exclusions
	return get_world_3d().direct_space_state.intersect_ray(query)

func _static_hit(from: Vector3, to: Vector3) -> Dictionary:
	return ray_hit(from, to, true)

func _update_roofs(center: Vector3) -> void:
	roof_transforms.clear()
	roof_sizes.clear()
	cover_exclusions.clear()
	var candidates: Array[Node] = []
	for group in [Groups.CHASSIS, Groups.EQUIPMENT, Groups.PLAYER, Groups.MONSTERS]:
		for node in get_tree().get_nodes_in_group(group):
			if not node is CollisionObject3D or node.get_world_3d() != get_world_3d(): continue
			cover_exclusions.append(node.get_rid())
			if group == Groups.EQUIPMENT and node.get("structure_kind") == "roof": candidates.append(node)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	for body in candidates:
		if body.is_queued_for_deletion() or (body.collision_layer & 1) == 0: continue
		if body.global_position.distance_to(center) > FAR_RADIUS + 16: continue
		for shape in body.get_children():
			if shape is CollisionShape3D and not shape.disabled and shape.shape is BoxShape3D:
				if roof_transforms.size() >= 8: break
				roof_transforms.append(shape.global_transform.affine_inverse())
				roof_sizes.append(shape.shape.size * 0.5)
	var origins := PackedVector3Array()
	var rows_x := PackedVector3Array()
	var rows_y := PackedVector3Array()
	var rows_z := PackedVector3Array()
	var sizes := roof_sizes.duplicate()
	for i in range(8):
		var transform := roof_transforms[i] if i < roof_transforms.size() else Transform3D.IDENTITY
		origins.append(transform.origin)
		rows_x.append(Vector3(transform.basis.x.x, transform.basis.y.x, transform.basis.z.x))
		rows_y.append(Vector3(transform.basis.x.y, transform.basis.y.y, transform.basis.z.y))
		rows_z.append(Vector3(transform.basis.x.z, transform.basis.y.z, transform.basis.z.z))
		if sizes.size() < 8: sizes.append(Vector3.ZERO)
	for material in materials:
		material.set_shader_parameter("roof_count", roof_transforms.size())
		material.set_shader_parameter("roof_origin", origins)
		material.set_shader_parameter("roof_row_x", rows_x)
		material.set_shader_parameter("roof_row_y", rows_y)
		material.set_shader_parameter("roof_row_z", rows_z)
		material.set_shader_parameter("roof_extents", sizes)

func roof_blocks(point: Vector3) -> bool:
	for i in range(roof_transforms.size()):
		var transform := roof_transforms[i]
		var origin := transform * point
		var direction := transform.basis * Vector3.UP
		var low := 0.0
		var high := INF
		for axis in range(3):
			if absf(direction[axis]) < 0.00001:
				if absf(origin[axis]) > roof_sizes[i][axis]: high = -1
			else:
				var a := (-roof_sizes[i][axis] - origin[axis]) / direction[axis]
				var b := (roof_sizes[i][axis] - origin[axis]) / direction[axis]
				low = maxf(low, minf(a, b))
				high = minf(high, maxf(a, b))
		if high >= low: return true
	return false

func _physics_process(delta: float) -> void:
	rays_last_tick = 0
	var manager := clock.get_parent().get_node_or_null("PoiInstances")
	var indoor: bool = manager != null and not manager.active_id.is_empty()
	var camera := get_viewport().get_camera_3d()
	var rain := clock.weather.sample().y / 2.0
	var cover := 1.0 if indoor else 0.0
	if not indoor and is_instance_valid(listener) and rain > 0:
		var head := listener.global_position + Vector3.UP * (0.0 if listener is Camera3D else 1.7)
		cover = 0.85 if not ray_hit(head, head + Vector3.UP * 80).is_empty() else 0.0
	shelter = move_toward(shelter, cover, delta * 2)
	low_pass.cutoff_hz = lerpf(16000.0, 1100.0, shelter)
	var volume := rain * lerpf(1.0, 0.2, shelter)
	for i in range(voices.size()):
		var blend := (1.0 - rain) if i == 0 else rain
		voices[i].volume_db = linear_to_db(maxf(0.0001, volume * blend * 0.7))
	rain_active = camera != null and not indoor and rain > 0.001
	if not rain_active:
		splashes.clear()
		splash_instance.multimesh.visible_instance_count = 0
		visible_drops = 0
		for field in fields: field.multimesh.visible_instance_count = 0
		last_center = Vector3.INF
		return
	var center := camera.global_position
	if not last_center.is_finite() or absf(center.y - last_center.y) > 32 or center.distance_to(last_center) > 48:
		near_cover.reset()
		far_cover.reset()
	last_center = center
	_update_roofs(center)
	near_cover.update(center, COVER_NEAR_BUDGET, _static_hit)
	far_cover.update(center, COVER_FAR_BUDGET, _static_hit)
	_advance_splashes(delta)
	for i in range(SPLASH_QUERIES):
		if rng.randf() > rain: continue
		var point := center + Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10))
		var hit := ray_hit(point + Vector3.UP * 64, point + Vector3.DOWN * 32)
		if not hit.is_empty(): _add_splash(hit, center)

func _process(delta: float) -> void:
	if not rain_active: return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	simulation_time += delta
	var rain := clock.weather.sample().y / 2.0
	var daylight := smoothstep(-0.16, 0.22, clock.sun_direction().y)
	splash_material.set_shader_parameter("daylight", daylight)
	visible_drops = 0
	for i in range(fields.size()):
		var field := fields[i]
		var radius := NEAR_RADIUS if i == 0 else FAR_RADIUS
		var height := 32.0 if i == 0 else 48.0
		var count := ceili(field.multimesh.instance_count * pow(rain, 1.6))
		field.multimesh.visible_instance_count = count
		visible_drops += count
		# Shader positions wrap around the real camera; keep CPU culling in agreement.
		field.custom_aabb = AABB(to_local(camera.global_position) - Vector3(radius + 1, height, radius + 1), Vector3((radius + 1) * 2, height * 2, (radius + 1) * 2))
		materials[i].set_shader_parameter("camera_center", camera.global_position)
		materials[i].set_shader_parameter("simulation_time", simulation_time)
		materials[i].set_shader_parameter("daylight", daylight)
		materials[i].set_shader_parameter("density", smoothstep(0.0, 0.15, rain))

func _add_splash(hit: Dictionary, center: Vector3) -> void:
	if splashes.size() >= MAX_SPLASHES or hit.normal.y < 0.5 or hit.position.distance_to(center) > 12: return
	var body := hit.collider as Node3D
	if body == null: return
	splashes.append({"body": weakref(body), "point": body.to_local(hit.position),
		"normal": body.global_basis.inverse() * hit.normal, "age": 0.0, "size": rng.randf_range(0.07, 0.16)})

func _advance_splashes(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for splash in splashes:
		splash.age += delta
		var body: Node3D = splash.body.get_ref()
		if splash.age >= SPLASH_LIFETIME or not is_instance_valid(body): continue
		var normal: Vector3 = (body.global_basis * splash.normal).normalized()
		var tangent := normal.cross(Vector3.FORWARD).normalized()
		if tangent.length_squared() < 0.01: tangent = normal.cross(Vector3.RIGHT).normalized()
		var basis := Basis(tangent, normal.cross(tangent), normal)
		var age: float = splash.age / SPLASH_LIFETIME
		var scale: float = splash.size * lerpf(0.3, 1.0, age)
		var point: Vector3 = body.to_global(splash.point) + normal * 0.015
		var index := alive.size()
		splash_instance.multimesh.set_instance_transform(index, global_transform.affine_inverse() * Transform3D(basis.scaled(Vector3.ONE * scale), point))
		splash_instance.multimesh.set_instance_custom_data(index, Color(age, 0, 0, 1))
		alive.append(splash)
	splashes = alive
	splash_instance.multimesh.visible_instance_count = alive.size()
