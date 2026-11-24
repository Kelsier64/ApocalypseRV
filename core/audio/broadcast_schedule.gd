extends Timer
class_name BroadcastSchedule
## The receiver decides whether a due transmission is audible.
const FIRST_SIGNAL_DELAY := Vector2(3.0, 7.0)
const SIGNAL_GAP := Vector2(18.0, 42.0)

@export var transmissions: Array[AudioStream] = []
var rng := RandomNumberGenerator.new()
var _last := -1

func start_first() -> void:
	if not transmissions.is_empty():
		start(rng.randf_range(FIRST_SIGNAL_DELAY.x, FIRST_SIGNAL_DELAY.y))

func start_next() -> void:
	if not transmissions.is_empty():
		start(rng.randf_range(SIGNAL_GAP.x, SIGNAL_GAP.y))

func draw() -> AudioStream:
	var count := transmissions.size()
	if count == 0: return null
	var exclude := count > 1 and _last >= 0 and _last < count
	var index := rng.randi_range(0, count - (2 if exclude else 1))
	if exclude and index >= _last: index += 1
	_last = index
	return transmissions[index]
