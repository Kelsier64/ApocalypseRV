extends RefCounted
class_name ScavengeLoot
## Fresh generic scrap opportunities share this pool; saved actors keep their scene.
const LEGACY := "res://props/scrap.tscn"
const SCENES := [LEGACY,
	"res://props/scavenge_loot/bent_steel_plate.tscn",
	"res://props/scavenge_loot/broken_pipe_elbow.tscn",
	"res://props/scavenge_loot/rusted_brake_drum.tscn",
	"res://props/scavenge_loot/old_exhaust_muffler.tscn",
	"res://props/scavenge_loot/dented_paint_bucket.tscn",
	"res://props/scavenge_loot/discarded_electric_iron.tscn"]
const NAMES := ["Scrap", "Bent Steel Plate", "Broken Pipe Elbow", "Rusted Brake Drum",
	"Old Exhaust Muffler", "Dented Paint Bucket", "Discarded Electric Iron"]

static func scene_for(source_key: String) -> String:
	# A stable opportunity key owns the variant; never consume the caller's RNG.
	return SCENES[posmod(("scavenge_loot:" + source_key).hash(), SCENES.size())]

static func item_name(scene_path: String) -> String:
	var index := SCENES.find(scene_path)
	return NAMES[index] if index >= 0 else "Scrap"

static func bottom_offset(item: Item, legacy_offset: float) -> float:
	if item.scene_file_path == LEGACY or item.scene_file_path not in SCENES: return legacy_offset
	return -item.get_placement_bounds().position.y

static func marker_transform(item: Item, authored: Transform3D) -> Transform3D:
	# Existing markers locate the centre of the original 0.3 m scrap cube.
	var result := authored
	result.origin += authored.basis.y * (bottom_offset(item, 0.15) - 0.15)
	return result
