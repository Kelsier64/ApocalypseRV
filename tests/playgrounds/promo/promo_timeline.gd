extends RefCounted
## A take's timed events. Each entry is {"at": seconds, "do": action, ...params} and fires
## once when the take clock passes `at`. The clock advances with physics time, so slow
## motion and Movie Maker stay in step with the picture.

## Required parameters per action. A stage implements every action listed here.
const ACTIONS := {
	"drive": ["speed"],
	"gear": ["gear"],
	"brake": [],
	"line": ["id"],
	"static": ["level"],
	"radio_off": [],
	"weather": ["to", "seconds"],
	"look": ["yaw", "pitch", "seconds"],
	"gaze": ["target", "seconds"],
	"eyes": ["open", "seconds"],
	"giant": [],
	"steer": ["within"],
	"giant_smash": [],
	"giant_release": [],
	"giant_watch": [],
	"giant_wake": [],
	"wind": ["tier"],
	"crawl": ["seconds"],
	"marker": ["name"],
	"end": [],
}

var cues: Array = []
var clock := 0.0
var running := false
var _next := 0

## Returns an empty string for a valid timeline, otherwise what is wrong with it.
static func check(entries: Variant) -> String:
	if not entries is Array or entries.is_empty(): return "timeline must be a non-empty list"
	var previous := -INF
	for index in entries.size():
		var cue: Variant = entries[index]
		if not cue is Dictionary: return "timeline entry %d is not an object" % index
		if not cue.has("at") or not (cue.at is float or cue.at is int): return "timeline entry %d has no time" % index
		if float(cue.at) < previous: return "timeline entry %d is earlier than the one before it" % index
		previous = float(cue.at)
		var action: String = str(cue.get("do", ""))
		if not ACTIONS.has(action): return "timeline entry %d has unknown action '%s'" % [index, action]
		for parameter in ACTIONS[action]:
			if not cue.has(parameter): return "timeline entry %d (%s) needs '%s'" % [index, action, parameter]
	return ""

func load_from(entries: Array) -> void:
	cues = entries
	clock = 0.0
	_next = 0
	running = false

func start() -> void:
	clock = 0.0
	_next = 0
	running = true

## Seconds from the start to the "end" cue, or to the last cue when there is none.
func length() -> float:
	for cue in cues:
		if cue.do == "end": return float(cue.at)
	return float(cues.back().at) if not cues.is_empty() else 0.0

func finished() -> bool:
	return _next >= cues.size()

## Advances the clock and fires every cue that came due. `fire` returns false to stop the take.
func advance(delta: float, fire: Callable) -> bool:
	if not running: return true
	clock += delta
	while _next < cues.size() and float(cues[_next].at) <= clock:
		var cue: Dictionary = cues[_next]
		_next += 1
		if cue.do == "end":
			running = false
			return true
		if not fire.call(cue):
			running = false
			return false
	if finished(): running = false
	return true
