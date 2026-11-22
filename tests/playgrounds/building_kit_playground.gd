extends Node3D
## Walk the BuildingKit reference building to judge its look and scale: wall
## openings and frames, the cold-grey finishes, the canopy, the annex stair and
## the finish swatches. The Esc menu's Playground tab switches to a clay view.

const SCENARIOS := ["Street", "Store interior", "Upper landing"]
const SPAWNS := {
	"Street": [Vector3(2, 0.1, 14), 0.0],
	"Store interior": [Vector3(0, 0.15, -3.5), PI],
	"Upper landing": [Vector3(14.3, 3.35, -2.5), PI / 2.0],
}

var building: Node3D
var controls := PlaygroundControls.new()
var clay := StandardMaterial3D.new()


func _ready() -> void:
	get_window().title = "ApocalypseRV - Building Kit"
	var scenario := PlaygroundControls.scenario(SCENARIOS[0])
	PlaygroundStage.flat_lot(self)
	building = load("res://world/building_kit/samples/service_block.tscn").instantiate()
	add_child(building)
	clay.albedo_color = Color(0.55, 0.55, 0.55)
	clay.roughness = 1.0
	add_child(controls)
	controls.scenarios(SCENARIOS, scenario)
	controls.note("Play normally. No monsters or loot; the building is the kit's reference sample.")
	controls.toggle("Clay view", false, _set_clay)
	controls.readout("Kit", func(): return "%d pieces, %d triangles" % [building.kit.stats().pieces, building.kit.stats().triangles])
	for i in range(Engine.physics_ticks_per_second): await get_tree().physics_frame
	PlaygroundStage.player(self, SPAWNS[scenario][0], SPAWNS[scenario][1])


func _set_clay(on: bool) -> void:
	for geometry: GeometryInstance3D in building.find_children("*", "GeometryInstance3D", true, false):
		geometry.material_override = clay if on else null
