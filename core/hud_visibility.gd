class_name HUDVisibility
extends CanvasModulate
## A presentation gate independent of each HUD's own visibility/state updates.
const GROUP := &"gameplay_hud_visibility"
static var hud_hidden := false

static func attach(layer: CanvasLayer) -> void:
	var gate := HUDVisibility.new()
	gate.name = "HUDVisibility"
	layer.add_child(gate)
	gate.add_to_group(GROUP)
	gate.refresh()

static func toggle(tree: SceneTree) -> void:
	hud_hidden = not hud_hidden
	for gate in tree.get_nodes_in_group(GROUP):
		gate.refresh()

static func set_cinematic(view: Viewport, active: bool) -> void:
	view.set_meta("cinematic_hud_hidden", active)
	for gate in view.get_tree().get_nodes_in_group(GROUP):
		if gate.get_viewport() == view: gate.refresh()

func refresh() -> void:
	color.a = 0.0 if hud_hidden or get_viewport().get_meta("cinematic_hud_hidden", false) else 1.0
