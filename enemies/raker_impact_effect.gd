extends Node3D
## Brief local impact puff and a synthesized thud, owned by the struck actor.
static var thud: AudioStreamWAV

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
	if thud == null:
		thud = AudioStreamWAV.new()
		thud.format = AudioStreamWAV.FORMAT_16_BITS
		thud.mix_rate = 22050
		var data := PackedByteArray()
		data.resize(4410 * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 43
		for i in 4410:
			var t := float(i) / 22050.0
			var sample := (sin(TAU * (70.0*t - 80.0*t*t)) * .7 + rng.randf_range(-.3,.3)) * exp(-t*28.0) * minf(t*700.0,1.0)
			data.encode_s16(i*2, int(sample*23000.0))
		thud.data = data
	var audio := AudioStreamPlayer3D.new()
	audio.stream = thud
	audio.volume_db = lerpf(-9.0, -1.0, clampf(speed/20.0,0,1))
	audio.max_distance = 35.0
	effect.add_child(audio)
	audio.play()
	effect.get_tree().create_timer(.8).timeout.connect(effect.queue_free)
