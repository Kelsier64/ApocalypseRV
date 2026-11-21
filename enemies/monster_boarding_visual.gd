extends Node3D
## Boarding audio, plus placeholder arms for actors without an imported model.
const GRIP_SOUND: SoundEvent = preload("res://assets/audio/events/monsters/climb_grip.tres")
const STRIKE_SOUND: SoundEvent = preload("res://assets/audio/events/monsters/strike.tres")
## Roughly where the hands are, so the sound sits on the hull rather than the feet.
const HANDS := Vector3(0, 1.45, 0)
var actor: Monster
var arms: Array[Node3D] = []
var strike: float = 0.0
var phase: float = 0.0
var last_mode: int = 0

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
	actor.attack_landed.connect(_on_attack)

func _on_attack(_target: Node3D, source: String) -> void:
	if source != "door_breach" and source != "underfoot": return
	strike = 0.3
	get_node("/root/Sfx").play(STRIKE_SOUND, actor, HANDS)

func _process(delta: float) -> void:
	if actor.is_dead: return
	phase += delta * 5.0
	strike = maxf(0.0, strike - delta)
	var mode := actor.boarding.mode
	if mode != last_mode and actor.locomotion_state == Monster.LocomotionState.CLIMBING:
		get_node("/root/Sfx").play(GRIP_SOUND, actor, HANDS)
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
