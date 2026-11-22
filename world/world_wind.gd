extends RefCounted
class_name WorldWind
## Natural wind derived from the current weather segment; nothing here is saved.
## The tier and base heading hash the world seed with WorldWeather.rng.state,
## which is constant within a segment and already checkpointed. Gusts and veer
## are smooth noise over game seconds. Nothing reads or advances any RNG.
const CALM := 0
const BREEZE := 1
const STRONG := 2
const GALE := 3
const NAMES := ["calm", "breeze", "strong", "gale"]
const DESCRIPTIONS := ["Calm", "Breeze", "Strong wind", "Gale"]
## Natural tier chances, calm to gale. Heavy rain may lift the tier one step.
const TIER_CHANCES := [0.40, 0.32, 0.20, 0.08]
const HEAVY_RAIN_STEP_UP := 0.5
## Mean speed per tier in m/s on fully exposed ground.
const SPEEDS := [0.0, 5.0, 12.0, 20.0]
## Gusts swing the mean speed by up to this fraction either way.
const GUST_SPREAD := 0.35
const GUST_FREQUENCY := 0.01 # per game second; ~2 real seconds at the default day
const VEER_FREQUENCY := 0.0004
const MAX_VEER := PI / 6.0
## Trees shelter the ground from wind; full canopy keeps this fraction out.
const TREE_SHELTER := 0.9
## Dust starts lifting above the first speed and is a full storm at the second.
const DUST_LIFT_SPEED := 7.0
const DUST_STORM_SPEED := 18.0
## Dryness below the first value raises no dust; above the second, all it can.
const DUST_DRY_MIN := 0.2
const DUST_DRY_FULL := 0.8
const _TIER_SALT := 0x57494e44
const _STEP_SALT := 0x53544550
const _HEADING_SALT := 0x48454144
const _GUST_SALT := 0x47555354
const _VEER_SALT := 0x56454552

## Session-only overrides (terminal, playgrounds); a load returns to nature.
var override_tier := -1
var override_heading := NAN
var weather: WorldWeather
var world_seed := 0
var _first_state := 0
var _gusts := FastNoiseLite.new()
var _veer := FastNoiseLite.new()
var _synced := false
var _state := 0
var _natural_tier := CALM
var _natural_heading := 0.0
var _source_strength := 0.0
var _source_heading := 0.0
var _segment_change_expected := false

func initialize(owner_weather: WorldWeather, seed_value: int) -> void:
	if weather != null and weather.changing.is_connected(_on_weather_changing):
		weather.changing.disconnect(_on_weather_changing)
	weather = owner_weather
	world_seed = seed_value
	_first_state = WorldWeather.initial_rng_state(seed_value)
	for pair: Array in [[_gusts, _GUST_SALT, GUST_FREQUENCY], [_veer, _VEER_SALT, VEER_FREQUENCY]]:
		var noise: FastNoiseLite = pair[0]
		noise.seed = hash([seed_value, pair[1]]) & 0x7fffffff
		noise.frequency = pair[2]
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_octaves = 3
	weather.changing.connect(_on_weather_changing)
	_synced = false
	_segment_change_expected = false

## A uniform [0, 1) value from the seed, the segment's RNG state and a salt.
static func roll(seed_value: int, state: int, salt: int) -> float:
	return float(hash([seed_value, state, salt]) & 0xffffff) / 16777216.0

static func tier_for(tier_roll: float, step_roll: float, heavy_rain: bool) -> int:
	var tier := CALM
	var threshold := 0.0
	for index in range(TIER_CHANCES.size()):
		threshold += TIER_CHANCES[index]
		tier = index
		if tier_roll < threshold: break
	if heavy_rain and step_roll < HEAVY_RAIN_STEP_UP: tier = mini(tier + 1, GALE)
	return tier

## The natural tier of a segment. The first segment of a run is always calm.
func natural_tier_for(state: int, target: Vector3) -> int:
	if state == _first_state: return CALM
	return tier_for(roll(world_seed, state, _TIER_SALT), roll(world_seed, state, _STEP_SALT), target.y >= 2.0)

func target_tier() -> int:
	if override_tier >= 0: return override_tier
	_sync()
	return _natural_tier

func set_override(tier: int) -> void:
	_sync()
	override_tier = clampi(tier, -1, GALE)
	_source_strength = float(target_tier())

## Continuous tier, 0 (calm) to 3 (gale), blended over WorldWeather.TRANSITION.
func strength() -> float:
	_sync()
	return lerpf(_source_strength, float(target_tier()), _blend())

## Mean speed in m/s before gusts and terrain exposure.
func mean_speed() -> float:
	var value := strength()
	var low := floori(value)
	if low >= GALE: return SPEEDS[GALE]
	return lerpf(SPEEDS[low], SPEEDS[low + 1], value - low)

## Gust level 0 to 1, shared by visuals, sound and physics.
func gust(seconds: float) -> float:
	return clampf(_gusts.get_noise_1d(seconds) * 0.5 + 0.5, 0.0, 1.0)

## Heading in radians the wind blows toward, clockwise from -Z.
func heading(seconds: float) -> float:
	if is_finite(override_heading): return override_heading
	_sync()
	var weight := _blend()
	# A settled segment reads its own heading exactly, so a restore matches it.
	var base := _natural_heading if weight >= 1.0 else lerp_angle(_source_heading, _natural_heading, weight)
	return wrapf(base + _veer.get_noise_1d(seconds) * MAX_VEER, 0.0, TAU)

func direction(seconds: float) -> Vector3:
	var angle := heading(seconds)
	return Vector3(sin(angle), 0.0, -cos(angle))

## Local wind speed in m/s; exposure comes from exposure_for().
func speed(seconds: float, exposure := 1.0) -> float:
	return mean_speed() * (1.0 + GUST_SPREAD * (gust(seconds) * 2.0 - 1.0)) * clampf(exposure, 0.0, 1.0)

func velocity(seconds: float, exposure := 1.0) -> Vector3:
	return direction(seconds) * speed(seconds, exposure)

## Dust 0 to 1 for a TerrainLandforms.appearance_at() value at this moment.
func dust_at(seconds: float, appearance: Vector3) -> float:
	return dust_amount(speed(seconds, exposure_for(appearance)), dryness_for(appearance), weather.sample().y)

## Dust at the mean wind, without gusts; the haze reads this so it does not pump.
func mean_dust_at(appearance: Vector3) -> float:
	return dust_amount(mean_speed() * exposure_for(appearance), dryness_for(appearance), weather.sample().y)

func description() -> String:
	return DESCRIPTIONS[target_tier()]

static func _blend_landform(table: Array, appearance: Vector3) -> float:
	return lerpf(table[int(appearance.x)], table[int(appearance.y)], appearance.z)

## 0 (wet, wooded) to 1 (bare and dry), from the landform moisture and trees.
static func dryness_for(appearance: Vector3) -> float:
	return (1.0 - _blend_landform(TerrainLandforms.MOISTURE, appearance)) * (1.0 - _blend_landform(TerrainLandforms.TREE_DENSITY, appearance))

## Fraction of the open-ground wind that reaches this landform.
static func exposure_for(appearance: Vector3) -> float:
	return 1.0 - _blend_landform(TerrainLandforms.TREE_DENSITY, appearance) * TREE_SHELTER

## Dust 0 to 1 from local wind speed, dryness and the rain sample (0 to 2).
## Any rain at full light-rain strength or more lays the dust completely.
static func dust_amount(local_speed: float, dryness: float, rain: float) -> float:
	var lift := smoothstep(DUST_LIFT_SPEED, DUST_STORM_SPEED, local_speed)
	return lift * smoothstep(DUST_DRY_MIN, DUST_DRY_FULL, dryness) * (1.0 - clampf(rain, 0.0, 1.0))

func _blend() -> float:
	return smoothstep(0.0, WorldWeather.TRANSITION, weather.transition_elapsed)

func _sync() -> void:
	var state: int = weather.rng.state
	if _synced and state == _state: return
	_state = state
	_natural_tier = natural_tier_for(state, weather.target)
	_natural_heading = roll(world_seed, state, _HEADING_SALT) * TAU
	# A restore or a first look settles at the segment's own wind; only a
	# segment change seen through `changing` blends from the outgoing wind.
	if not _synced or not _segment_change_expected:
		_source_strength = float(override_tier if override_tier >= 0 else _natural_tier)
		_source_heading = _natural_heading
	_synced = true
	_segment_change_expected = false

func _on_weather_changing() -> void:
	_sync()
	_source_strength = strength()
	_source_heading = lerp_angle(_source_heading, _natural_heading, _blend())
	_segment_change_expected = true
