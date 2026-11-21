extends Node3D
## Brief local impact puff and a recorded body thud, owned by the struck actor.
const THUD: SoundEvent = preload("res://assets/audio/events/monsters/body_hit.tres")
## The thud gains this much from a crawl to a 20 m/s hit.
const SLOW_HIT_DB := -8.0

static func spawn(actor: Node3D, point: Vector3, direction: Vector3, speed: float) -> void:
	var effect := Node3D.new()
	actor.add_child.call_deferred(effect)
	_setup.call_deferred(effect, point, direction, speed)

static func _setup(effect: Node3D, point: Vector3, direction: Vector3, speed: float) -> void:
	if not is_instance_valid(effect) or not effect.is_inside_tree(): return
	effect.top_level = true
	effect.global_position = point
	var puff := CPUParticles3D.new()
	puff.amount = 14
	puff.lifetime = .4
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.direction = direction + Vector3.UP * .35
	puff.spread = 50.0
	puff.initial_velocity_min = 1.0
	puff.initial_velocity_max = clampf(speed * .25, 1.5, 5.0)
	puff.gravity = Vector3(0,-6,0)
	puff.scale_amount_min = .035
	puff.scale_amount_max = .09
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.24,.20,.17)
	mesh.material = material
	puff.mesh = mesh
	effect.add_child(puff)
	effect.get_node("/root/Sfx").play(THUD, effect, Vector3.ZERO, lerpf(SLOW_HIT_DB, 0.0, clampf(speed / 20.0, 0, 1)))
	effect.get_tree().create_timer(.8).timeout.connect(effect.queue_free)
