extends RefCounted
class_name RoutePressureState
## Pure real-second encounter timing. The controller owns actor creation and RNG.
const ENTRY_SECONDS := 3.0
const EXIT_SECONDS := 3.0
const FADE_SECONDS := 12.0
const COOLDOWN_SECONDS := 60.0
const RETRY_SECONDS := 2.0
const FIRST_WAVE := 8.0
const WAVE_INTERVAL := 30.0
const GIANT_SECONDS := 30.0
const MAX_SECONDS := 1000000000.0
const MAX_PROGRESS := 1000000000.0
const TIME_EPSILON := 0.000001
const REASONS := ["", "backtrack", "forest", "backtrack_forest"]

var initialized := false
var active := false
var origin := 0.0
var highwater := 0.0
var fog := 0.0
var reason := ""
var exposure := 0.0
var cooldown := 0.0
var entry_elapsed := 0.0
var exit_elapsed := 0.0
var fog_elapsed := 0.0
var fade_remaining := 0.0
var fade_from := 0.0
var pending_rakers := 0
var wave_ordinal := 0
var giant_done := false
var retry_rakers := 0.0
var retry_giant := 0.0

func initialize(progress: float, start_origin: float) -> void:
	if not is_finite(progress) or not is_finite(start_origin): return
	if absf(progress) > MAX_PROGRESS or absf(start_origin) > MAX_PROGRESS: return
	_restore_values(_empty_state())
	initialized = true
	origin = start_origin
	highwater = maxf(progress, origin)

func advance(delta: float, sample: Dictionary) -> void:
	if not initialized or not is_finite(delta) or delta <= 0.0: return
	if not _number(sample.get("progress"), -MAX_PROGRESS, MAX_PROGRESS): return
	if not _number(sample.get("forest_offset"), 0.0, MAX_PROGRESS): return
	if not sample.get("exempt") is bool or not sample.get("progress_valid") is bool: return
	delta = minf(delta, MAX_SECONDS)
	var progress: float = sample.progress
	if sample.progress_valid: highwater = maxf(highwater, progress)
	var gap := highwater - progress
	var forest: float = sample.forest_offset
	var exempt: bool = sample.exempt
	var deviating := not exempt and (gap > 120.0 or forest > 100.0)
	var safe := exempt or (gap <= 80.0 and forest <= 70.0)
	var next_reason := "backtrack_forest" if gap > 120.0 and forest > 100.0 else ("backtrack" if gap > 120.0 else "forest")
	var previous_cooldown := cooldown
	cooldown = _countdown(cooldown, delta)
	if active:
		entry_elapsed = 0.0
		if deviating: reason = next_reason
		if safe:
			var until_exit := maxf(0.0, EXIT_SECONDS - exit_elapsed)
			var active_delta := minf(delta, until_exit)
			_tick_active(active_delta, maxf(0.0, active_delta - previous_cooldown))
			exit_elapsed += active_delta
			if exit_elapsed + TIME_EPSILON >= EXIT_SECONDS:
				_end_event()
				var remaining := delta - active_delta
				cooldown = _countdown(COOLDOWN_SECONDS, remaining)
				_tick_fade(remaining)
		else:
			exit_elapsed = 0.0
			_tick_active(delta, maxf(0.0, delta - previous_cooldown))
		return
	exit_elapsed = 0.0
	if not deviating:
		entry_elapsed = 0.0
		_tick_fade(delta)
		return
	var until_entry := maxf(0.0, ENTRY_SECONDS - entry_elapsed)
	var inactive_delta := minf(delta, until_entry)
	_tick_fade(inactive_delta)
	entry_elapsed += inactive_delta
	if entry_elapsed + TIME_EPSILON < ENTRY_SECONDS: return
	active = true
	reason = next_reason
	entry_elapsed = 0.0
	fade_remaining = 0.0
	fade_from = 0.0
	_tick_active(delta - inactive_delta, maxf(0.0, delta - maxf(inactive_delta, previous_cooldown)))

func rakers_due() -> bool:
	return active and cooldown <= 0.0 and pending_rakers > 0 and retry_rakers <= 0.0

func giant_due() -> bool:
	return active and cooldown <= 0.0 and exposure + TIME_EPSILON >= GIANT_SECONDS and not giant_done and retry_giant <= 0.0

func resolve_raker_wave(emitted: int, capped: bool = false) -> void:
	if not rakers_due(): return
	pending_rakers = 0 if capped else maxi(0, pending_rakers - clampi(emitted, 0, pending_rakers))
	retry_rakers = RETRY_SECONDS if pending_rakers > 0 else 0.0

func resolve_giant(success: bool) -> void:
	if not giant_due(): return
	giant_done = success
	retry_giant = 0.0 if success else RETRY_SECONDS

func _tick_active(delta: float, spawn_delta: float) -> void:
	fog_elapsed = minf(MAX_SECONDS, fog_elapsed + delta)
	fog = maxf(fog, _fog_at(fog_elapsed))
	retry_rakers = _countdown(retry_rakers, spawn_delta)
	retry_giant = _countdown(retry_giant, spawn_delta)
	exposure = minf(MAX_SECONDS, exposure + spawn_delta)
	var current_wave := _wave_at(exposure)
	if current_wave > wave_ordinal:
		# Only the newest wave survives a long frame; no catch-up burst.
		wave_ordinal = current_wave
		pending_rakers = 2
		retry_rakers = 0.0

func _end_event() -> void:
	active = false
	reason = ""
	exposure = 0.0
	fog_elapsed = 0.0
	exit_elapsed = 0.0
	pending_rakers = 0
	wave_ordinal = 0
	giant_done = false
	retry_rakers = 0.0
	retry_giant = 0.0
	fade_from = fog
	fade_remaining = FADE_SECONDS if fog > 0.0 else 0.0
	cooldown = COOLDOWN_SECONDS

func _tick_fade(delta: float) -> void:
	fade_remaining = _countdown(fade_remaining, delta)
	fog = fade_from * fade_remaining / FADE_SECONDS
	if fade_remaining <= 0.0: fade_from = 0.0

static func _fog_at(seconds: float) -> float:
	if seconds <= FIRST_WAVE: return seconds / FIRST_WAVE * 0.5
	return minf(1.0, 0.5 + (seconds - FIRST_WAVE) / (GIANT_SECONDS - FIRST_WAVE) * 0.5)

static func _wave_at(seconds: float) -> int:
	return 0 if seconds + TIME_EPSILON < FIRST_WAVE else floori((seconds + TIME_EPSILON - FIRST_WAVE) / WAVE_INTERVAL) + 1

static func _countdown(remaining: float, delta: float) -> float:
	var result := maxf(0.0, remaining - delta)
	return 0.0 if result < TIME_EPSILON else result

func capture() -> Dictionary:
	return {"version": 1, "initialized": initialized, "active": active, "origin": origin,
		"highwater": highwater, "fog": fog, "reason": reason, "exposure": exposure,
		"cooldown": cooldown, "entry_elapsed": entry_elapsed, "exit_elapsed": exit_elapsed,
		"fog_elapsed": fog_elapsed, "fade_remaining": fade_remaining, "fade_from": fade_from,
		"pending_rakers": pending_rakers, "wave_ordinal": wave_ordinal, "giant_done": giant_done,
		"retry_rakers": retry_rakers, "retry_giant": retry_giant}

static func _empty_state() -> Dictionary:
	return {"version": 1, "initialized": false, "active": false, "origin": 0.0,
		"highwater": 0.0, "fog": 0.0, "reason": "", "exposure": 0.0, "cooldown": 0.0,
		"entry_elapsed": 0.0, "exit_elapsed": 0.0, "fog_elapsed": 0.0,
		"fade_remaining": 0.0, "fade_from": 0.0, "pending_rakers": 0,
		"wave_ordinal": 0, "giant_done": false, "retry_rakers": 0.0, "retry_giant": 0.0}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(_empty_state().keys()): return false
	if not data.version is int or data.version != 1: return false
	for key in ["initialized", "active", "giant_done"]:
		if not data[key] is bool: return false
	for key in ["origin", "highwater"]:
		if not _number(data[key], -MAX_PROGRESS, MAX_PROGRESS): return false
	for key in ["fog", "fade_from"]:
		if not _number(data[key], 0.0, 1.0): return false
	for key in ["exposure", "fog_elapsed"]:
		if not _number(data[key], 0.0, MAX_SECONDS): return false
	if not _number(data.cooldown, 0.0, COOLDOWN_SECONDS): return false
	if not _number(data.fade_remaining, 0.0, FADE_SECONDS): return false
	for key in ["entry_elapsed", "exit_elapsed"]:
		if not _number(data[key], 0.0, ENTRY_SECONDS) or data[key] >= ENTRY_SECONDS: return false
	for key in ["retry_rakers", "retry_giant"]:
		if not _number(data[key], 0.0, RETRY_SECONDS): return false
	if not data.pending_rakers is int or data.pending_rakers < 0 or data.pending_rakers > 2: return false
	if not data.wave_ordinal is int or data.wave_ordinal != _wave_at(float(data.exposure)): return false
	if not data.reason is String or not data.reason in REASONS: return false
	if not data.initialized: return data == _empty_state()
	if data.highwater < data.origin or data.exposure > data.fog_elapsed: return false
	if data.pending_rakers > 0 and data.wave_ordinal == 0: return false
	if data.retry_rakers > 0.0 and data.pending_rakers == 0: return false
	if data.giant_done and (data.exposure + TIME_EPSILON < GIANT_SECONDS or data.retry_giant != 0.0): return false
	if data.retry_giant > 0.0 and (data.exposure + TIME_EPSILON < GIANT_SECONDS or data.giant_done): return false
	if data.cooldown > 0.0 and data.exposure > 0.0: return false
	if data.fade_remaining == 0.0 and data.fade_from != 0.0: return false
	if not data.active and data.fade_remaining > 0.0 and data.cooldown == 0.0: return false
	if data.active:
		return data.reason != "" and data.entry_elapsed == 0.0 and data.fade_remaining == 0.0 and data.fade_from == 0.0 and data.fog + 0.000001 >= _fog_at(float(data.fog_elapsed))
	return data.reason == "" and data.exposure == 0.0 and data.fog_elapsed == 0.0 and data.exit_elapsed == 0.0 and data.pending_rakers == 0 and not data.giant_done and data.retry_rakers == 0.0 and data.retry_giant == 0.0 and is_equal_approx(float(data.fog), float(data.fade_from) * float(data.fade_remaining) / FADE_SECONDS)

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func restore(data: Dictionary) -> bool:
	if not valid_state(data): return false
	_restore_values(data)
	return true

func _restore_values(data: Dictionary) -> void:
	for key in _empty_state():
		if key != "version": set(key, data[key])
