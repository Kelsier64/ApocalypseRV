extends AnimatableBody3D

# Repeating elevator platform that moves up and down
# Attached to the LiftPlatform node inside elevator.tscn

@export var bottom_y: float = 0.5
@export var top_y: float = 27.15
@export var speed: float = 5.0
@export var wait_time: float = 2.0  # Seconds to pause at top/bottom

var going_up: bool = true
var waiting: bool = false
var wait_timer: float = 0.0

func _physics_process(delta: float):
	if waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			waiting = false
			going_up = !going_up
		return
	
	var target_y = top_y if going_up else bottom_y
	var direction = 1.0 if going_up else -1.0
	var move_amount = direction * speed * delta
	
	var new_y = position.y + move_amount
	
	# Check if we've reached the target
	if going_up and new_y >= top_y:
		new_y = top_y
		_start_wait()
	elif not going_up and new_y <= bottom_y:
		new_y = bottom_y
		_start_wait()
	
	position.y = new_y

func _start_wait():
	waiting = true
	wait_timer = wait_time
