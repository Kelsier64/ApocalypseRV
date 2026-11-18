class_name EngineGrainBank
extends Resource
## Single-firing grains cut offline by art_source/audio/rv/make_engine_grains.py.
## Each grain holds one firing period plus a raised-cosine fade on both sides,
## so consecutive grains overlap-add back into the recording.

enum Kind { STEADY, RISING, FALLING }

@export var samples: AudioStreamWAV
@export var starts := PackedInt32Array()
@export var periods := PackedInt32Array()
@export var fades := PackedInt32Array()
@export var lengths := PackedInt32Array()
## Firing rate the recording had around each grain, before any resampling.
@export var firing_hz := PackedFloat32Array()
@export var kinds := PackedInt32Array()
## Index of the grain that followed in the recording, or -1 at the end of a run.
@export var follows := PackedInt32Array()

var _pcm := PackedFloat32Array()
var _by_rate := PackedInt32Array()
var _sorted_hz := PackedFloat32Array()


func size() -> int:
	return starts.size()


## Decoded mono samples in [-1, 1]. Decoding happens once per loaded bank.
func pcm() -> PackedFloat32Array:
	if _pcm.is_empty():
		var data := samples.data
		_pcm.resize(data.size() / 2)
		for i in range(_pcm.size()):
			_pcm[i] = data.decode_s16(i * 2) / 32768.0
	return _pcm


func min_hz() -> float:
	_index()
	return _sorted_hz[0]


func max_hz() -> float:
	_index()
	return _sorted_hz[_sorted_hz.size() - 1]


## Grain indices whose native rate lies within the ratio band around hz.
func candidates(hz: float, tolerance: float) -> PackedInt32Array:
	_index()
	var low := _sorted_hz.bsearch(hz / (1.0 + tolerance))
	var high := _sorted_hz.bsearch(hz * (1.0 + tolerance), false)
	if high <= low:
		var nearest := clampi(low, 0, _sorted_hz.size() - 1)
		if nearest > 0 and absf(_sorted_hz[nearest - 1] - hz) < absf(_sorted_hz[nearest] - hz):
			nearest -= 1
		return PackedInt32Array([_by_rate[nearest]])
	return _by_rate.slice(low, high)


func _index() -> void:
	if not _by_rate.is_empty(): return
	var order := range(size())
	order.sort_custom(func(a: int, b: int) -> bool: return firing_hz[a] < firing_hz[b])
	_by_rate = PackedInt32Array(order)
	_sorted_hz.resize(order.size())
	for i in range(order.size()):
		_sorted_hz[i] = firing_hz[order[i]]
