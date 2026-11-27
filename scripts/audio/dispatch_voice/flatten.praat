# Flattens every trimmed word in inDir$ to one pitch and gives it a narrowband
# receiver tone. Called by generate.mjs; see assets/audio/dispatch_voice/README.md.
form Flatten dispatch words
	sentence inDir
	sentence outDir
	real pitch 0
	positive rate 16000
	positive lowCut 300
	positive highCut 3400
	positive drive 2.5
endform

list = Create Strings as file list: "words", inDir$ + "/*.wav"
n = Get number of strings

# Pitch 0 means: use the voice's own typical pitch, so the flat line sits where it speaks.
if pitch <= 0
	total = 0
	counted = 0
	for i to n
		selectObject: list
		name$ = Get string: i
		sound = Read from file: inDir$ + "/" + name$
		track = To Pitch: 0.01, 60, 400
		median = Get quantile: 0, 0, 0.5, "Hertz"
		if median <> undefined
			total += median
			counted += 1
		endif
		removeObject: sound, track
	endfor
	pitch = total / counted
endif
writeInfoLine: "pitch ", fixed$(pitch, 1)

for i to n
	selectObject: list
	name$ = Get string: i
	sound = Read from file: inDir$ + "/" + name$
	duration = Get total duration
	manipulation = To Manipulation: 0.01, 60, 400
	tier = Create PitchTier: "flat", 0, duration
	Add point: duration / 2, pitch
	selectObject: manipulation
	plusObject: tier
	Replace pitch tier
	selectObject: manipulation
	flat = Get resynthesis (overlap-add)
	band = Filter (pass Hann band): lowCut, highCut, 100
	Scale peak: 0.9
	Formula: "tanh(self * drive) / tanh(drive)"
	out = Resample: rate, 50
	Scale peak: 0.95
	Save as WAV file: outDir$ + "/" + name$
	removeObject: sound, manipulation, tier, flat, band, out
endfor
removeObject: list
