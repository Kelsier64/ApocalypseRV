extends Control
## Discovered rooms only; no map of hidden branches or loot.
var interior: Node3D
var floor_index := 0

func _draw() -> void:
	if interior == null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.04,0.045,0.94))
	var font := ThemeDB.fallback_font
	var floor_label: String = "GROUND FLOOR" if interior.profile_id == &"megashelter" else "B%d" % (floor_index+1)
	draw_string(font,Vector2(16,28),floor_label,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	var visible_rooms: Array[int] = []
	var bounds := Rect2(Vector2(-5,-5),Vector2(10,10))
	for i in interior.rooms.size():
		var room: Dictionary = interior.layout.rooms[i]
		if room.id not in interior.explored: continue
		var box: AABB = room.transform * InteriorLayout.definition(interior.layout, i, interior.profile).describe().bounds
		if -floor_index*interior.layout.floor_spacing < box.position.y-0.1 or -floor_index*interior.layout.floor_spacing >= box.end.y-0.1: continue
		visible_rooms.append(i)
		bounds = bounds.merge(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)))
	var scale_factor := minf(540/maxf(bounds.size.x,1),340/maxf(bounds.size.y,1))
	var offset := Vector2(30,60) - bounds.position*scale_factor
	for i in visible_rooms:
		var room: Dictionary = interior.layout.rooms[i]
		var box: AABB = room.transform * InteriorLayout.definition(interior.layout, i, interior.profile).describe().bounds
		var rect := Rect2(Vector2(box.position.x,box.position.z)*scale_factor+offset,Vector2(box.size.x,box.size.z)*scale_factor)
		draw_rect(rect.grow(-1),Color("24555a") if i != interior.current_room else Color("a87c38"))
		if InteriorLayout.definition(interior.layout, i, interior.profile).role == &"stairs": _draw_stairs(rect)
	for edge: Dictionary in interior.layout.links:
		if edge.a not in visible_rooms or edge.b not in visible_rooms: continue
		var a: Vector3 = interior.layout.rooms[edge.a].transform.origin
		var b: Vector3 = interior.layout.rooms[edge.b].transform.origin
		draw_line(Vector2(a.x,a.z)*scale_factor+offset,Vector2(b.x,b.z)*scale_factor+offset,Color(0.7,0.8,0.7,0.5),2)

func _draw_stairs(rect: Rect2) -> void:
	var span := minf(18.0, minf(rect.size.x, rect.size.y) - 6.0)
	if span < 6.0: return
	var origin := rect.get_center() + Vector2(-span, span) * 0.5
	var points := PackedVector2Array([origin])
	for step in 3:
		points.append(origin + Vector2(step, -step - 1) * span / 3.0)
		points.append(origin + Vector2(step + 1, -step - 1) * span / 3.0)
	draw_polyline(points, Color("c3ccc5"), 2.0)
