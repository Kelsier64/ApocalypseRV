extends RefCounted
class_name Groups
## Single source of truth for the string groups that wire systems together.
## Renaming a group is a cross-system contract change: monster targeting,
## equipment/RV resolution, and the tests all key off these values.

const RV := "rv"
const CHASSIS := "chassis"
const EQUIPMENT := "equipment"
const MONSTER_DAMAGEABLE := "monster_damageable"
const RV_POWER_GENERATORS := "rv_power_generators"
const CRAFTING_STATIONS := "crafting_stations"
const PLAYER := "player"
const MONSTERS := "monsters"
