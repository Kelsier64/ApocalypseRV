extends SceneTree
## Writes every trailer narration line as a WAV for the edit, spelled from the dispatch
## word bank with the same gaps as in-game broadcasts, plus captions.txt with each
## line's duration and subtitle text. Glitched lines are written broken, as the speaker plays them.
##
##   godot --headless --path . --script res://scripts/promo_narration.gd
##
## Output goes to .godot/promo/narration/ (ignored by Git; rerun to regenerate).

const BROADCAST := preload("res://tests/playgrounds/promo/promo_broadcast.gd")
const SCHEDULE := preload("res://core/audio/broadcast_schedule.tscn")
const OUTPUT := "res://.godot/promo/narration"

func _initialize() -> void:
	var schedule := SCHEDULE.instantiate() as BroadcastSchedule
	var lines := BROADCAST.narration()
	var failed := lines.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var captions := PackedStringArray()
	var ids := lines.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for id in ids:
		var tokens := BROADCAST.tokens(BROADCAST.text(lines[id]))
		var missing := schedule.voice.missing(tokens)
		if not missing.is_empty():
			push_error("Line %s needs words the bank lacks: %s" % [id, ", ".join(missing)])
			failed = true
			continue
		var clip := BROADCAST.clip(schedule, lines[id])
		var path := "%s/%02d.wav" % [OUTPUT, int(id)]
		if clip == null or clip.save_to_wav(path) != OK:
			push_error("Could not write " + path)
			failed = true
			continue
		captions.append("%02d\t%.2f s\t%s" % [int(id), clip.get_length(), schedule.caption])
	var file := FileAccess.open(OUTPUT + "/captions.txt", FileAccess.WRITE)
	if file: file.store_string("\n".join(captions) + "\n")
	schedule.free()
	print("Narration: %d lines in %s" % [captions.size(), ProjectSettings.globalize_path(OUTPUT)])
	quit(1 if failed else 0)
