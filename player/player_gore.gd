extends Node3D
## Bounded, cosmetic blood, surface stains and a recorded wet tearing impact.
const TEAR_SOUND: SoundEvent = preload("res://assets/audio/events/player/gore_tear.tres")
## Rollers and the first bite play the tear this much quieter than a severing wound.
const LIGHT_TEAR_DB := -13.0
var remaining := 2.0
const POOL_SHADER = preload("res://player/player_blood_pool.gdshader")
static var pool_mesh: PlaneMesh

static func spawn(actor: CharacterBody3D, at: Vector3, context: Dictionary) -> void:
	var root := preload("res://player/player_gore.gd").new()
	var parent: Node = WorldEntities.get_container(actor)
	if not WorldEntities.same_world(actor, parent): parent = actor.get_parent()
	parent.add_child(root)
	root.global_position = at
	root._burst(actor, context)
	if not bool(context.get("minor", false)): root._stain.call_deferred(actor)

func _burst(actor: CharacterBody3D, context: Dictionary) -> void:
	# Rollers and the first bite clamp spray lightly; a severing wound gushes.
	var at_rollers: bool = context.get("source", "") == "scrapper" or bool(context.get("minor", false))
	var droplets := CPUParticles3D.new()
	droplets.amount = 22 if at_rollers else 65
	droplets.lifetime = .45 if at_rollers else .7
	droplets.one_shot = true
	droplets.explosiveness = .96
	droplets.spread = 42
	droplets.direction = Vector3.UP + actor.global_basis.x * .4
	var captor: Node3D = context.get("captor")
	if is_instance_valid(captor): droplets.direction = (captor.global_position - global_position).normalized() + Vector3.UP * .6
	droplets.initial_velocity_min = .7 if at_rollers else 1.2
	droplets.initial_velocity_max = 2.2 if at_rollers else 3.8
	droplets.gravity = Vector3(0, -9.8, 0)
	droplets.scale_amount_min = .5
	droplets.scale_amount_max = 1.5
	var mesh := SphereMesh.new()
	mesh.radius = .004 if at_rollers else .012
	mesh.height = .014 if at_rollers else .045
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.52, .022, .038)
	material.roughness = .28
	mesh.material = material
	droplets.mesh = mesh
	add_child(droplets)
	droplets.emitting = true
	get_node("/root/Sfx").play(TEAR_SOUND, self, Vector3.ZERO, LIGHT_TEAR_DB if at_rollers else 0.0)

func _stain(actor: CharacterBody3D) -> void:
	if not is_instance_valid(actor): return
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .03, global_position - Vector3.UP * 4, 1, [actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var parent := hit.collider as Node3D
	if parent == null: return
	var pool := MeshInstance3D.new()
	pool.name = "BloodPool"
	pool.add_to_group("player_blood_stains")
	parent.add_child(pool)
	var up: Vector3 = hit.normal
	var x := Vector3.RIGHT.slide(up).normalized()
	if x.length_squared() < .01: x = Vector3.FORWARD.slide(up).normalized()
	var basis := Basis(x, up, x.cross(up)) * Basis(Vector3.UP, randf() * TAU)
	pool.global_transform = Transform3D(basis, hit.position + up * .003)
	if pool_mesh == null:
		pool_mesh = PlaneMesh.new()
		pool_mesh.size = Vector2(1.3, 1.3)
	pool.mesh = pool_mesh
	var material := ShaderMaterial.new()
	material.shader = POOL_SHADER
	material.set_shader_parameter("variation", randf_range(1, 1000))
	pool.material_override = material
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var size := Vector3(randf_range(.85, 1.2), 1, randf_range(.85, 1.2))
	pool.scale = size * Vector3(.45, 1, .45)
	var tween := pool.create_tween()
	tween.tween_property(pool, "scale", size, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(43.6)
	tween.tween_method(func(value: float): material.set_shader_parameter("opacity", value), 1.0, 0.0, 3.0)
	tween.tween_callback(pool.queue_free)
	var old := get_tree().get_nodes_in_group("player_blood_stains")
	while old.size() > 32:
		var remove: Node = old.pop_front()
		if is_instance_valid(remove): remove.queue_free()

func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0: queue_free()
