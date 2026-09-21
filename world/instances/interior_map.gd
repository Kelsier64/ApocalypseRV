extends Control
## Discovered rooms only; no map of hidden branches or loot.
var interior: Node3D
var floor_index := 0

func _draw() -> void:
	if interior == null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.04,0.045,0.94))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(16,28),"EXPLORED / LEVEL %d" % (floor_index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	var visible_rooms: Array[int] = []
	var bounds := Rect2(Vector2(-5,-5),Vector2(10,10))
	for i in interior.rooms.size():
		var room: Dictionary = interior.layout.rooms[i]
		if room.id not in interior.explored: continue
		var box: AABB = room.transform * interior.PROFILE.room(room.definition).describe().bounds
		if floor_index*6 < box.position.y-0.1 or floor_index*6 >= box.end.y-0.1: continue
		visible_rooms.append(i)
		bounds = bounds.merge(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)))
	var scale_factor := minf(540/maxf(bounds.size.x,1),340/maxf(bounds.size.y,1))
	var offset := Vector2(30,60) - bounds.position*scale_factor
	for i in visible_rooms:
		var room: Dictionary = interior.layout.rooms[i]
		var box: AABB = room.transform * interior.PROFILE.room(room.definition).describe().bounds
		var rect := Rect2(Vector2(box.position.x,box.position.z)*scale_factor+offset,Vector2(box.size.x,box.size.z)*scale_factor)
		draw_rect(rect.grow(-1),Color("24555a") if i != interior.current_room else Color("a87c38"))
		var label: String = room.id.trim_prefix("r")
		if room.definition == "stairs": label = "UP" if floor_index == 0 else "DOWN"
		if room.definition == "atrium" and floor_index > roundi(room.transform.origin.y/6): label = "VOID"
		draw_string(font,rect.position+Vector2(3,14),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	for edge: Dictionary in interior.layout.links:
		if edge.a not in visible_rooms or edge.b not in visible_rooms: continue
		if not edge.gate.is_empty() and not interior.shortcut_open: continue
		var a: Vector3 = interior.layout.rooms[edge.a].transform.origin
		var b: Vector3 = interior.layout.rooms[edge.b].transform.origin
		draw_line(Vector2(a.x,a.z)*scale_factor+offset,Vector2(b.x,b.z)*scale_factor+offset,Color(0.7,0.8,0.7,0.5),2)
