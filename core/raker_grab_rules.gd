extends RefCounted
## Shared gameplay tuning for the authoritative clock, player HUD and fixtures.
const HOLD_DURATION := 1.0
const MIN_PRESSES := 6
const MAX_PRESSES := 10
const WOUNDED_PERCENT := 60

static func reaches_wounded_threshold(presses: int, required: int) -> bool:
	return presses * 100 >= required * WOUNDED_PERCENT

static func minimum_wounded_presses(required: int) -> int:
	return ceili(float(required * WOUNDED_PERCENT) / 100.0)
