extends Resource
class_name WordBank
## The dispatch computer's vocabulary: one flat-pitched recording per token.
## `words` is written by scripts/audio/dispatch_voice/generate.mjs; do not edit by hand.
## A token list reads like "unit kilo four seven ." where "." closes a sentence.

const STOP := &"."
const DIGITS := [&"zero", &"one", &"two", &"three", &"four", &"five", &"six", &"seven", &"eight", &"nine"]
const LETTERS := [&"alpha", &"bravo", &"charlie", &"delta", &"echo", &"foxtrot", &"golf", &"hotel", &"india",
	&"juliett", &"kilo", &"lima", &"mike", &"november", &"oscar", &"papa", &"quebec", &"romeo", &"sierra",
	&"tango", &"uniform", &"victor", &"whiskey", &"xray", &"yankee", &"zulu"]
const LETTER_CAPTIONS := {&"juliett": "Juliett", &"xray": "X-ray"}

@export var words: Dictionary[StringName, AudioStreamWAV] = {}

static func tokenize(line: String) -> PackedStringArray:
	return line.strip_edges().split(" ", false)

func missing(tokens: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for token in tokens:
		if StringName(token) != STOP and not words.has(StringName(token)): out.append(token)
	return out

## Joins the words with a fixed silence between them, and a longer one after each ".".
## Every word shares one 16-bit mono PCM format, so the join is a byte copy.
func compose(tokens: PackedStringArray, word_gap: float, stop_gap: float) -> AudioStreamWAV:
	var first: AudioStreamWAV = null
	for token in tokens:
		first = words.get(StringName(token))
		if first: break
	if first == null: return null
	var bytes_per_second := first.mix_rate * 2
	var data := PackedByteArray()
	for token in tokens:
		var gap := word_gap
		if StringName(token) == STOP:
			gap = stop_gap
		else:
			var word: AudioStreamWAV = words.get(StringName(token))
			if word == null:
				push_warning("Word bank has no '%s'" % token)
				continue
			data.append_array(word.data)
		var silence := PackedByteArray()
		silence.resize(int(gap * bytes_per_second) & ~1)
		data.append_array(silence)
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = first.mix_rate
	clip.stereo = false
	clip.data = data
	return clip

## The on-screen text for the same tokens: sentence case, call letters capitalised,
## and runs of digits written as one number ("kilo four seven" reads "Kilo 47").
static func caption(tokens: PackedStringArray) -> String:
	var out := ""
	var sentence_start := true
	var after_digit := false
	for token in tokens:
		var name := StringName(token)
		if name == STOP:
			out += "."
			sentence_start = true
			after_digit = false
			continue
		var digit := DIGITS.find(name)
		if digit >= 0:
			out += ("" if after_digit else (" " if not out.is_empty() else "")) + str(digit)
			after_digit = true
			sentence_start = false
			continue
		var text := token
		if name in LETTERS: text = LETTER_CAPTIONS.get(name, token.capitalize())
		elif sentence_start: text = token.capitalize()
		out += (" " if not out.is_empty() else "") + text
		after_digit = false
		sentence_start = false
	return out
