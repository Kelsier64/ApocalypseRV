extends Node3D
## Boarding audio, plus placeholder arms for actors without an imported model.
var actor: Monster
var arms: Array[Node3D] = []
var sound: AudioStreamPlayer3D
var strike: float = 0.0
var phase: float = 0.0
var last_mode: int = 0
var grip_sound: AudioStreamWAV
var strike_sound: AudioStreamWAV
static var shared_grip_sound: AudioStreamWAV
static var shared_strike_sound: AudioStreamWAV

func _ready() -> void:
	actor = get_parent()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.08, 0.06)
	var sides: Array = [] if actor.has_node("BodyMesh/Model") else [-1.0, 1.0]
	for side in sides:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.38, 1.45, 0)
		var mesh := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.radius = 0.085
		shape.height = 0.65
		mesh.mesh = shape
		mesh.material_override = material
		mesh.position.y = -0.25
		arm.add_child(mesh)
		add_child(arm)
		arms.append(arm)
	sound = AudioStreamPlayer3D.new()
	sound.max_distance = 25.0
	sound.volume_db = -12.0
	add_child(sound)
	if shared_grip_sound == null:
		shared_grip_sound = _make_sound(0.18, 170.0)
		shared_strike_sound = _make_sound(0.25, 75.0)
	grip_sound = shared_grip_sound
	strike_sound = shared_strike_sound
	actor.attack_landed.connect(_on_attack)

func _make_sound(duration: float, frequency: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := int(duration * stream.mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 741
	for index in range(count):
		var t := float(index) / stream.mix_rate
		var envelope := exp(-t * 23.0) * minf(t * 600.0, 1.0)
		var value := (sin(TAU * frequency * t) * 0.65 + random.randf_range(-0.35, 0.35)) * envelope
		bytes.encode_s16(index * 2, int(value * 22000.0))
	stream.data = bytes
	return stream

func _on_attack(_target: Node3D, source: String) -> void:
	if source != "door_breach" and source != "underfoot": return
	strike = 0.3
	sound.stream = strike_sound
	sound.play()

func _process(delta: float) -> void:
	if actor.is_dead: return
	phase += delta * 5.0
	strike = maxf(0.0, strike - delta)
	var mode := actor.boarding.mode
	if mode != last_mode and actor.locomotion_state == Monster.LocomotionState.CLIMBING:
		sound.stream = grip_sound
		sound.play()
	last_mode = mode
	for index in range(arms.size()):
		var angle := 0.1
		if actor.locomotion_state == Monster.LocomotionState.CLIMBING:
			angle = 2.2 + sin(phase + index * PI) * 0.15
			if mode == MonsterBoarding.Mode.DOOR: angle = 1.6 + (0.6 if strike > 0.0 and index == 0 else 0.0)
		elif actor.boarding.on_roof(actor):
			angle = 0.8 if actor.boarding.settle > 0.0 else 0.1
			if strike > 0.0: angle = 1.2
		arms[index].rotation.x = lerp_angle(arms[index].rotation.x, angle, minf(1.0, delta * 16.0))
