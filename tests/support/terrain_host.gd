extends Node3D
## Test world root that owns a giant-scale navigation map, as the production
## world does, so chunks can publish both navigation layers.
var giant_navigation_map := RID()

func _init() -> void:
	giant_navigation_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(giant_navigation_map, 0.275)
	NavigationServer3D.map_set_cell_height(giant_navigation_map, 0.25)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(giant_navigation_map, 0.1)
	NavigationServer3D.map_set_edge_connection_margin(giant_navigation_map, 0.8)
	NavigationServer3D.map_set_active(giant_navigation_map, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and giant_navigation_map.is_valid():
		NavigationServer3D.free_rid(giant_navigation_map)
		giant_navigation_map = RID()
