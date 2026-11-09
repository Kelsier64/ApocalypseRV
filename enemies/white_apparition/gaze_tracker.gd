extends RefCounted
## A sighting requires one uninterrupted look during one emergence.
signal threshold_reached

const DWELL_SECONDS := 0.6
const STREAK_EXPIRY := 60.0
const REQUIRED_SIGHTINGS := 3

var count := 0
var completed := false
var _dwell := 0.0
var _unseen_time := 0.0
var _counted_appearance := true

func begin_appearance() -> void:
	_dwell = 0.0
	_counted_appearance = false

func reset() -> void:
	count = 0
	completed = false
	_dwell = 0.0
	_unseen_time = 0.0
	_counted_appearance = true

func sample(valid: bool, delta: float) -> bool:
	if completed: return false
	if not valid:
		_dwell = 0.0
		if count > 0:
			_unseen_time += delta
			if _unseen_time >= STREAK_EXPIRY:
				count = 0
				_unseen_time = 0.0
		return false
	_unseen_time = 0.0
	if _counted_appearance: return false
	_dwell += delta
	if _dwell < DWELL_SECONDS: return false
	_counted_appearance = true
	count += 1
	completed = count == REQUIRED_SIGHTINGS
	if completed: threshold_reached.emit()
	return true
