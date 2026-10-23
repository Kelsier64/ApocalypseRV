class_name HUDVisibility
extends CanvasModulate
## A presentation gate independent of each HUD's own visibility/state updates.
const GROUP := &"gameplay_hud_visibility"
static var hud_hidden := false

static func attach(layer: CanvasLayer) -> void:
	var gate := HUDVisibility.new()
	gate.name = "HUDVisibility"
	gate.color = Color(1, 1, 1, 0 if hud_hidden else 1)
	layer.add_child(gate)
	gate.add_to_group(GROUP)

static func toggle(tree: SceneTree) -> void:
	hud_hidden = not hud_hidden
	for gate in tree.get_nodes_in_group(GROUP):
		gate.color = Color(1, 1, 1, 0 if hud_hidden else 1)
