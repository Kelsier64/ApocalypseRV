extends Node3D
## Hear each monster's sound rules in play: when it stays silent, when it gives
## itself away, and the tells before it strikes. The monsters are real and can
## kill; Restart from the Playground tab.

const SCENARIOS := ["Raker", "Barrel man", "Black apparition", "White apparition", "Slender Speaker"]
const RAKER := preload("res://enemies/raker.tscn")
const BARREL_MAN := preload("res://enemies/barrel_man.tscn")
const BLACK := preload("res://enemies/black_apparition/black_apparition.tscn")
const WHITE := preload("res://enemies/white_apparition/white_apparition.tscn")
const SLENDER := preload("res://enemies/slender_speaker/slender_speaker.tscn")
## Half the side of the hand-made navigation square the giant walks on, inside the lot.
const SLENDER_NAV_HALF := 165.0
const NOTES := {
	"Raker": "A Raker wanders 25 m ahead and hunts you when it notices you. Listen for steps, growls and clicks, then the tell before each sweep and grab. It can grab, bite and kill.",
	"Barrel man": "One barrel 14 m ahead is a barrel man. It should be silent until you come within 8 m, clang as it stands, slosh as it runs and hiss for 2 s before it blasts.",
	"Black apparition": "Daylight lot; the apparition stays put until you stare at it for 2 s or press Enrage. Up close it breathes; enraged it shrieks and runs at you. Touch kills.",
	"White apparition": "Press Appear: it appears 35-55 m behind you with a soft breath. Unseen it leaves after 6-10 s, so turn and look at it for about a second, then face away and listen to the whisper close in. Pressing Appear again sends the current one away first. Looking drains SAN; touch kills.",
	"Slender Speaker": "The giant patrols a 22 m loop 60 m ahead. It sees you up to 220 m away, then runs at you and grabs; on foot that kills. Turn off its loudspeaker to hear the steps alone, and let it ignore you to hear patrol steps from far away.",
}

var controls := PlaygroundControls.new()
var player: CharacterBody3D
var monster: Node3D
var clock: WorldClock
var scenario := ""
var white_presses := 0
var slender_map: RID
var slender_music := true
var slender_ignores := false


func _ready() -> void:
	get_window().title = "ApocalypseRV - Monster Audio"
	scenario = PlaygroundControls.scenario(SCENARIOS[0])
	print("PLAYGROUND scenario=%s" % scenario)
	PlaygroundStage.flat_lot(self)
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note(NOTES.get(scenario, ""))
	_build_controls()
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	player = PlaygroundStage.player(self, Vector3(0, 0.05, 0))
	await get_tree().physics_frame
	match scenario:
		"Raker": _spawn_raker()
		"Barrel man": _spawn_barrel_man()
		"Black apparition": _appear_black(12.0)
		"White apparition": _setup_white()
		"Slender Speaker": _spawn_slender(60.0)


func _exit_tree() -> void:
	if has_meta("slender_region"): NavigationServer3D.free_rid(get_meta("slender_region"))
	if slender_map.is_valid(): NavigationServer3D.free_rid(slender_map)


func _build_controls() -> void:
	controls.section(scenario)
	match scenario:
		"Raker":
			controls.buttons([["Spawn 25 m ahead", _spawn_raker], ["Spawn 8 m ahead", _spawn_raker.bind(8.0)]])
			controls.buttons([["Windup tell", _raker_tell.bind("attack_left")], ["Lunge tell", _raker_tell.bind("grab_stand_reach")]])
		"Barrel man":
			controls.button("Reset the barrel", _spawn_barrel_man)
		"Black apparition":
			controls.buttons([["Appear 4 m ahead", _appear_black.bind(4.0)], ["Appear 12 m ahead", _appear_black.bind(12.0)]])
			controls.button("Enrage", func(): if monster is BlackApparition and monster.phase == BlackApparition.Phase.OBSERVING: monster._frenzy())
		"White apparition":
			controls.button("Appear behind you", _appear_white)
		"Slender Speaker":
			controls.buttons([["Spawn 40 m ahead", _spawn_slender.bind(40.0)], ["Spawn 90 m ahead", _spawn_slender.bind(90.0)]])
			controls.toggle("Loudspeaker music", slender_music, _set_slender_music)
			controls.toggle("Ignores you", slender_ignores, _set_slender_ignores)
	controls.readout("State", _state)
	controls.readout("Distance", func(): return "%.1f m" % player.global_position.distance_to(monster.global_position) if _ready_to_read() else "-")


func _ready_to_read() -> bool:
	return is_instance_valid(player) and is_instance_valid(monster) and monster.is_inside_tree()


func _ahead(distance: float) -> Vector3:
	var forward := -player.global_basis.z.slide(Vector3.UP).normalized() if is_instance_valid(player) else Vector3.FORWARD
	var point := (player.global_position if is_instance_valid(player) else Vector3.ZERO) + forward * distance
	return Vector3(point.x, 0.05, point.z)


func _replace(next: Node3D, at: Vector3) -> void:
	if is_instance_valid(monster): monster.queue_free()
	monster = next
	# Place it before _ready: monsters record their home position there.
	monster.position = at
	add_child(monster)


func _spawn_raker(distance := 25.0) -> void:
	var raker: Raker = RAKER.instantiate()
	raker.loot_drops = {}
	_replace(raker, _ahead(distance))


func _raker_tell(clip: String) -> void:
	if monster is Raker: monster.attack_started.emit(clip, 1.0)


func _spawn_barrel_man() -> void:
	_replace(BARREL_MAN.instantiate(), _ahead(14.0))


func _appear_black(distance: float) -> void:
	if not is_instance_valid(player): return
	if not monster is BlackApparition:
		_replace(BLACK.instantiate(), _ahead(distance))
		monster.configure(player, false)
	monster.emerge(_ahead(distance), player.camera)


func _setup_white() -> void:
	# The white apparition only stands on streamed terrain, so lay one chunk of it.
	var chunk := ChunkGenerator.new()
	add_child(chunk)
	var surface := MeshInstance3D.new()
	surface.name = "Ground"
	chunk.add_child(surface)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(400, 0.2, 400)
	body.add_child(shape)
	body.position.y = -0.09
	surface.add_child(body)
	clock = WorldClock.new()
	clock.set_process(false)
	clock.elapsed_seconds = 14.0 * 3600.0
	add_child(clock)
	var white: WhiteApparition = WHITE.instantiate()
	_replace(white, Vector3(0, 0, 200))
	white.configure(player, clock)


func _appear_white() -> void:
	if not monster is WhiteApparition or not is_instance_valid(player): return
	# Send a present one away first, so every press gives a fresh appearance.
	if monster.is_present(): monster._enter_hidden()
	white_presses += 1
	var result := "Appeared" if monster._try_emerge(player.camera) else "No place to appear; step away from the lot edge"
	controls.set_meta("white_result", "%s (press %d)" % [result, white_presses])


func _spawn_slender(distance: float) -> void:
	if not slender_map.is_valid(): slender_map = _slender_navigation()
	var giant: SlenderSpeaker = SLENDER.instantiate()
	_replace(giant, _ahead(distance))
	giant.set_giant_navigation_map(slender_map)
	giant.settings = giant.settings.duplicate()
	giant.set_meta("sight_range", giant.settings.sight_range)
	_set_slender_ignores(slender_ignores)
	_set_slender_music(slender_music)


## One flat navigation square over the lot, built by hand instead of baked.
func _slender_navigation() -> RID:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(map, Vector3.UP)
	var mesh := NavigationMesh.new()
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
	var h := SLENDER_NAV_HALF
	mesh.vertices = PackedVector3Array([Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.map_set_active(map, true)
	set_meta("slender_region", region)
	return map


func _set_slender_music(on: bool) -> void:
	slender_music = on
	if not monster is SlenderSpeaker or monster.patrol_music == null: return
	if on: monster._start_patrol_music()
	else: monster.patrol_music.halt()


func _set_slender_ignores(on: bool) -> void:
	slender_ignores = on
	if monster is SlenderSpeaker: monster.settings.sight_range = 0.0 if on else monster.get_meta("sight_range")


func _state() -> String:
	if not _ready_to_read(): return "-"
	if monster is Raker: return "Dead" if monster.is_dead else Monster.State.keys()[monster.ai_state].capitalize()
	if monster is BarrelMan:
		var fuse := " (fuse %.1f s)" % monster.proximity_fuse_remaining if monster.proximity_fuse_remaining >= 0.0 else ""
		return BarrelMan.Phase.keys()[monster.phase].capitalize() + fuse
	if monster is SlenderSpeaker: return SlenderSpeaker.Phase.keys()[monster.phase].capitalize()
	if monster is BlackApparition: return BlackApparition.Phase.keys()[monster.phase].capitalize()
	if monster is WhiteApparition:
		return ("Present" if monster.is_present() else "Hidden") + "  " + str(controls.get_meta("white_result", ""))
	return "-"
