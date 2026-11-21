extends Node3D
## Walk, sprint, crouch and jump across one pad of each footstep surface, then
## inside the parked RV and up its ladder onto the roof, to hear the player's own
## footfalls. Real terrain sorts road, shoulder, grass and dirt by itself; check
## that part in the generated world.

const SCENARIOS := ["Surfaces"]
## Pads in walking order from the start, left to right; each carries the surface tag.
const PADS := [
	["asphalt", Color("3a3c3d")], ["gravel", Color("8b8573")], ["dirt", Color("6b5a43")],
	["grass", Color("55663f")], ["wood", Color("8a6a46")], ["metal", Color("8d9396")],
	["concrete", Color("a7a49c")]]
const PAD_SIZE := Vector3(6.0, 0.06, 16.0)
const PAD_GAP := 1.0
const PAD_Z := -14.0

var controls := PlaygroundControls.new()
var player: CharacterBody3D


func _ready() -> void:
	get_window().title = "ApocalypseRV - Footsteps"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	print("PLAYGROUND scenario=%s" % scenario)
	PlaygroundStage.flat_lot(self)
	_lay_pads()
	PlaygroundStage.parked_rv(self, Vector3(-12, 1.6, 16))
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Pads ahead, left to right: asphalt, gravel, dirt, grass, wood, metal, concrete. The bare lot also plays concrete. The RV behind you has a wood cabin floor and a sheet-metal roof; climb its roof ladder. Hold Shift to sprint, Ctrl to crouch, Space to jump.")
	controls.readout("Surface", func(): return FootstepSurface.Kind.keys()[_footsteps().last_surface].capitalize() if _footsteps() else "-")
	controls.readout("Gait", func(): return str(_footsteps().gait()).capitalize() if _footsteps() else "-")
	controls.readout("Steps", func(): return str(_footsteps().steps_taken) if _footsteps() else "-")
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	player = PlaygroundStage.player(self, Vector3(0, 0.05, 2))


func _footsteps() -> Node:
	return player.get_node_or_null("Footsteps") if is_instance_valid(player) else null


func _lay_pads() -> void:
	var width := PADS.size() * (PAD_SIZE.x + PAD_GAP) - PAD_GAP
	for index in PADS.size():
		var x := -width * 0.5 + PAD_SIZE.x * 0.5 + index * (PAD_SIZE.x + PAD_GAP)
		var pad := StaticBody3D.new()
		pad.set_meta(FootstepSurface.META, PADS[index][0])
		pad.position = Vector3(x, PAD_SIZE.y * 0.5, PAD_Z)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = PAD_SIZE
		pad.add_child(shape)
		add_child(pad)
		RoadsideKit.part(self, PAD_SIZE, pad.position, PADS[index][1])
