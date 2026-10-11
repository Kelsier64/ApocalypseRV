extends RefCounted
class_name PistolRules
## Shared first-pass tuning; ammunition belongs to ItemState, never the preview.
const PISTOL_SCENE := "res://props/pistol.tscn"
const AMMO_SCENE := "res://props/pistol_ammo.tscn"
const MAGAZINE_CAPACITY := 12
const BOX_CAPACITY := 24
const DAMAGE := 25.0
const SHOT_INTERVAL := 0.3
const RANGE := 60.0
const RELOAD_SECONDS := 1.5
const AIM_SECONDS := 0.15
const AIM_FOV_SCALE := 0.8
