extends RefCounted
## Takes over the RV's dispatch speaker for a take: its own broadcast schedule stays silent,
## signal strength is pinned, and the trailer narration plays through the real speaker,
## spelled from the same word bank and gaps as in-game broadcasts.

const NARRATION := "res://tests/playgrounds/promo/narration.json"
## Long enough that the speaker never resamples coverage during a take.
const NO_SAMPLE := 1.0e9

var speaker: DispatchSpeaker
var lines: Dictionary
var strength := 1.0

static func narration() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(NARRATION))
	return data.lines if data is Dictionary and data.get("lines") is Dictionary else {}

static func tokens(text: String) -> PackedStringArray:
	return WordBank.tokenize(text)

func attach(rv: Chassis, level: int) -> bool:
	lines = narration()
	for child in rv.get_children():
		if child is DispatchSpeaker: speaker = child
	if speaker == null or lines.is_empty(): return false
	if not speaker.enabled: speaker.set_enabled(true)
	speaker.level = clampi(level, 0, 2)
	speaker.schedule.stop()
	# A disabled timer never fires, so no in-game broadcast interrupts the narration.
	speaker.schedule.process_mode = Node.PROCESS_MODE_DISABLED
	_pin()
	return true

## Plays narration line `id`. Returns false when the line or one of its words is missing.
func play(id: String) -> bool:
	if not lines.has(id): return false
	var spoken := tokens(lines[id])
	if not speaker.schedule.voice.missing(spoken).is_empty(): return false
	strength = 1.0
	_pin()
	speaker._fading = false
	speaker.speaker.stream = speaker.schedule.speak(spoken)
	speaker.speaker.volume_db = speaker.level_db[speaker.level] + speaker._exterior_gain()
	speaker.speaker.play()
	return speaker.speaker.playing

## Holds the receiver at `level` signal strength (hiss rises as it falls). `cut` stops the
## current line at once, the way a lost carrier drops a sentence mid-word.
func set_signal(level: float, cut: bool) -> void:
	strength = clampf(level, 0.0, 1.0)
	if cut: speaker.speaker.stop()
	_pin()

## Dead air: no voice and no hiss for the rest of the take.
func silence() -> void:
	speaker.speaker.stop()
	speaker.noise.stop()
	speaker.set_process(false)

func tick() -> void:
	if speaker != null and speaker.is_processing(): _pin()

func _pin() -> void:
	speaker.strength = strength
	speaker._jitter = 0.0
	speaker._drop_db = 0.0
	speaker._sample_in = NO_SAMPLE
