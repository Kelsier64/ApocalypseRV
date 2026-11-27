extends Timer
class_name BroadcastSchedule
## The receiver decides whether a due transmission is audible.
## A draw is either a fixed clip or a template the dispatch computer reads from its word bank.
const FIRST_SIGNAL_DELAY := Vector2(3.0, 7.0)
const SIGNAL_GAP := Vector2(18.0, 42.0)

@export var transmissions: Array[AudioStream] = []
## Token lines with slots: {unit} call letter and two digits, {letter}, {digit}, {a|b} one of the words.
@export var templates: PackedStringArray = []
@export var voice: WordBank
@export var word_gap: float
@export var stop_gap: float
var rng := RandomNumberGenerator.new()
## Caption of the last draw; empty for a clip without words.
var caption := ""
var _last := -1

func start_first() -> void:
	if _count() > 0:
		start(rng.randf_range(FIRST_SIGNAL_DELAY.x, FIRST_SIGNAL_DELAY.y))

func start_next() -> void:
	if _count() > 0:
		start(rng.randf_range(SIGNAL_GAP.x, SIGNAL_GAP.y))

func _count() -> int:
	return transmissions.size() + (templates.size() if voice else 0)

func draw() -> AudioStream:
	var count := _count()
	caption = ""
	if count == 0: return null
	var exclude := count > 1 and _last >= 0 and _last < count
	var index := rng.randi_range(0, count - (2 if exclude else 1))
	if exclude and index >= _last: index += 1
	_last = index
	if index < transmissions.size(): return transmissions[index]
	return speak(fill(templates[index - transmissions.size()]))

## Fills a template's slots from this schedule's own generator, never the gameplay one.
func fill(template: String) -> PackedStringArray:
	var out := PackedStringArray()
	for token in WordBank.tokenize(template):
		if not token.begins_with("{"):
			out.append(token)
			continue
		var slot := token.trim_prefix("{").trim_suffix("}")
		match slot:
			"unit": out.append_array([_pick(WordBank.LETTERS), _pick(WordBank.DIGITS), _pick(WordBank.DIGITS)])
			"letter": out.append(_pick(WordBank.LETTERS))
			"digit": out.append(_pick(WordBank.DIGITS))
			_: out.append(_pick(slot.split("|")))
	return out

func speak(tokens: PackedStringArray) -> AudioStream:
	caption = WordBank.caption(tokens)
	return voice.compose(tokens, word_gap, stop_gap)

func _pick(options: Variant) -> String:
	return String(options[rng.randi_range(0, options.size() - 1)])
