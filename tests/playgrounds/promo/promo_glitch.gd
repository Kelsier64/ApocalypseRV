extends RefCounted
## Spells a narration line from the dispatch word bank like WordBank.compose, then breaks
## it the way a failing relay would, baked into the clip so the cab speaker only plays it.
##
## A line's `glitch` in narration.json:
##   from        first word the fault touches; it grows from there to the last word
##   drift       pitch wander depth at the last word (0.05 is five percent either way)
##   distortion  drive, crush and sample-hold reached at the last word (0 to 1)
##   seed        the wander's noise seed
##   words       per-word faults, keyed by token: stutter (repeats of the onset),
##               stretch (tape slowdown factor), reverse, swallow (0 to 1: the word
##               sinks in pitch, crushes and fades out), jam (the buffer hangs and
##               nothing after it plays: {keep, at, grain, seconds, gain}. The first
##               `keep` occurrences play normally; the next plays up to `at` of the
##               word, then loops the `grain`-second slice there for `seconds`, `gain`
##               dB louder than the word)

const STUTTER_SECONDS := 0.09
const DRIFT_HZ := 2.3

## The tokens the speaker gets out, up to the word a jam hangs on, for the caption.
static func heard(tokens: PackedStringArray, spec: Dictionary) -> PackedStringArray:
	var hang := _jam_index(tokens, spec)
	return tokens if hang < 0 else tokens.slice(0, hang + 1)

static func compose(bank: WordBank, tokens: PackedStringArray, word_gap: float, stop_gap: float, spec: Dictionary) -> AudioStreamWAV:
	var rate := 0
	for token in tokens:
		var first: AudioStreamWAV = bank.words.get(StringName(token))
		if first:
			rate = first.mix_rate
			break
	if rate == 0: return null
	var onset := tokens.find(str(spec.get("from", "")))
	var last := tokens.size() - 1
	while last > 0 and StringName(tokens[last]) == WordBank.STOP: last -= 1
	var words: Dictionary = spec.get("words", {})
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(spec.get("seed", 0))
	noise.frequency = DRIFT_HZ
	var out := PackedFloat32Array()
	var hang := _jam_index(tokens, spec)
	for index in tokens.size():
		var token := tokens[index]
		var gap := word_gap
		if StringName(token) == WordBank.STOP:
			gap = stop_gap
		else:
			var word: AudioStreamWAV = bank.words.get(StringName(token))
			if word == null: continue
			var samples := _decode(word.data)
			if onset >= 0 and index >= onset:
				var faults: Dictionary = words.get(token, {})
				var progress := float(index - onset + 1) / float(maxi(1, last - onset + 1))
				samples = _break(samples, faults, progress, spec, noise, out.size(), rate)
				if index == hang:
					out.append_array(_jam(samples, faults.jam, rate))
					break
			out.append_array(samples)
		var silence := PackedFloat32Array()
		silence.resize(int(gap * rate))
		out.append_array(silence)
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = rate
	clip.stereo = false
	clip.data = _encode(out)
	return clip

static func _break(samples: PackedFloat32Array, faults: Dictionary, progress: float, spec: Dictionary, noise: FastNoiseLite, start: int, rate: int) -> PackedFloat32Array:
	var stutter := int(faults.get("stutter", 0))
	if stutter > 0:
		var onset := samples.slice(0, mini(samples.size(), int(STUTTER_SECONDS * rate)))
		var repeated := PackedFloat32Array()
		for i in stutter:
			repeated.append_array(onset)
			repeated.resize(repeated.size() + int(0.03 * rate))
		repeated.append_array(samples)
		samples = repeated
	if faults.get("reverse", false): samples.reverse()
	var swallow := float(faults.get("swallow", 0.0))
	var depth := float(spec.get("drift", 0.0)) * progress
	var stretch := float(faults.get("stretch", 1.0))
	samples = _varispeed(samples, func(t: float) -> float:
		var wander := 1.0 + depth * noise.get_noise_1d(float(start) / rate + t)
		# A swallowed word sinks as if the tape were stopping.
		return wander / stretch * lerpf(1.0, 0.35, swallow * t / maxf(0.001, float(samples.size()) / rate)), rate)
	var drive := clampf(float(spec.get("distortion", 0.0)) * progress + swallow * 0.5, 0.0, 1.0)
	return _damage(samples, drive, swallow)

## Where the jam hangs the line: the first `keep` occurrences of its word after `from`
## play, the next one hangs. -1 when the line has no jam.
static func _jam_index(tokens: PackedStringArray, spec: Dictionary) -> int:
	var onset := tokens.find(str(spec.get("from", "")))
	if onset < 0: return -1
	var words: Dictionary = spec.get("words", {})
	var seen := {}
	for index in range(onset, tokens.size()):
		var faults: Dictionary = words.get(tokens[index], {})
		if not faults.has("jam"): continue
		var occurrence: int = seen.get(tokens[index], 0)
		seen[tokens[index]] = occurrence + 1
		if occurrence == int(faults.jam.get("keep", 0)): return index
	return -1

## A digital buffer that hangs: the word plays up to `at`, then the `grain`-second slice
## there repeats back to back for `seconds`, hard-edged like a frozen audio frame.
static func _jam(samples: PackedFloat32Array, jam: Dictionary, rate: int) -> PackedFloat32Array:
	var length := clampi(int(float(jam.get("grain", 0.06)) * rate), 1, samples.size())
	var start := clampi(int(samples.size() * float(jam.get("at", 0.5))), 0, samples.size() - length)
	var grain := samples.slice(start, start + length)
	var gain := db_to_linear(float(jam.get("gain", 0.0)))
	for i in grain.size(): grain[i] = clampf(grain[i] * gain, -1.0, 1.0)
	var out := samples.slice(0, start)
	var total := out.size() + int(float(jam.get("seconds", 1.0)) * rate)
	while out.size() < total: out.append_array(grain)
	out.resize(total)
	return out

## Resamples at a playback speed that varies over the source time, like a wobbling tape:
## above 1 is faster and higher, below 1 slower and lower.
static func _varispeed(samples: PackedFloat32Array, speed: Callable, rate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var position := 0.0
	var limit := float(samples.size() - 1)
	while position < limit:
		var i := int(position)
		out.append(lerpf(samples[i], samples[i + 1], position - i))
		position += maxf(0.05, float(speed.call(position / rate)))
	return out

## Overdrive, bit crush and sample hold that grow with `drive`; `swallow` fades the
## word out under the damage.
static func _damage(samples: PackedFloat32Array, drive: float, swallow: float) -> PackedFloat32Array:
	if drive <= 0.0 and swallow <= 0.0: return samples
	var gain := 1.0 + drive * 9.0
	var steps := lerpf(32768.0, 12.0, drive * drive)
	var hold := 1 + int(drive * 5.0)
	var held := 0.0
	var count := samples.size()
	for i in count:
		if i % hold == 0: held = samples[i]
		var value := tanh(held * gain) / tanh(gain)
		value = round(value * steps) / steps
		if swallow > 0.0: value *= 1.0 - swallow * smoothstep(0.2, 1.0, float(i) / count)
		samples[i] = value * lerpf(1.0, 0.7, drive)
	return samples

static func _decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size(): out[i] = data.decode_s16(i * 2) / 32768.0
	return out

static func _encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size(): out.encode_s16(i * 2, clampi(int(samples[i] * 32767.0), -32768, 32767))
	return out
