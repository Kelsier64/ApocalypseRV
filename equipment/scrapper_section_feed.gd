extends RefCounted
## Visual sections share one original Item, payload and save owner.
const FEED = preload("res://equipment/scrapper_feed_motion.gd")
var pieces: Array[Dictionary] = []
var originals: Array[GeometryInstance3D] = []
var progress := 0.0

func setup(prop: Node3D, owner: Node3D, bounds: AABB, pose: Transform3D) -> void:
	var box := FEED.rotated_box(bounds,pose.basis)
	box.position += pose.origin
	var sources: Array[Dictionary] = []
	for mesh: MeshInstance3D in prop.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		originals.append(mesh)
		var frame := owner.global_transform.affine_inverse()*mesh.global_transform
		var source_bounds := FEED.rotated_box(mesh.get_aabb(),frame.basis)
		source_bounds.position += frame.origin
		sources.append({"mesh":mesh,"frame":frame,"bounds":source_bounds})
	for label: Label3D in prop.find_children("*","Label3D",true,false):
		if label.is_visible_in_tree(): originals.append(label)
	# Each full-size section fits between the frame even as it yaws.
	var columns := maxi(1,int(ceil(box.size.x/.32)))
	var rows := maxi(1,int(ceil(box.size.z/.32)))
	var layers := maxi(1,int(ceil(box.size.y/.38)))
	var size := Vector3(box.size.x/columns,box.size.y/layers,box.size.z/rows)
	for y in layers:
		for z in rows:
			for x in columns:
				var center := box.position + Vector3((x+.5)*size.x,(y+.5)*size.y,(z+.5)*size.z)
				var piece := Node3D.new()
				piece.name = "FeedSection"
				owner.add_child(piece)
				piece.transform = Transform3D(Basis.IDENTITY,center)
				var local_bounds := AABB(-size*.5,size)
				for source in sources:
					if not source.bounds.intersects(AABB(center-size*.5,size)): continue
					var clone := MeshInstance3D.new()
					clone.mesh = source.mesh.mesh
					clone.cast_shadow = source.mesh.cast_shadow
					piece.add_child(clone)
					clone.transform = piece.transform.affine_inverse()*source.frame
					# Convert whole-mesh overrides so each section owns its cut shader.
					for surface in clone.mesh.get_surface_count():
						var material: Material = source.mesh.get_active_material(surface)
						if material != null: clone.set_surface_override_material(surface,material)
				var cuts := FEED.apply_cut(piece,owner)
				for record in cuts:
					record.cut.set_shader_parameter("piece_mode",true)
					record.cut.set_shader_parameter("piece_low",local_bounds.position)
					record.cut.set_shader_parameter("piece_high",local_bounds.end)
				pieces.append({"node":piece,"bounds":local_bounds,"start":piece.transform,"pose":piece.transform,"surfaces":cuts})
	for mesh in originals: mesh.hide()
	advance(owner,0)

func advance(owner: Node3D, amount: float) -> void:
	progress = amount
	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		var delay := float(index)/maxf(1,pieces.size()-1)*.22
		var t := clampf((amount-delay)/(1-delay),0,1)
		var start: Transform3D = piece.start
		var turn := Basis(Vector3.UP,t*1.6 + sin(t*TAU*2)*.12)*Basis(Vector3.RIGHT,sin(t*PI)*.65)*Basis(Vector3.FORWARD,sin(t*TAU)*.3)
		var box := FEED.rotated_box(piece.bounds,turn)
		for attempt in 8:
			if box.size.x <= FEED.HALF_OPENING*2 and box.size.z <= FEED.HALF_OPENING*2: break
			turn = Basis(Quaternion.IDENTITY.slerp(turn.get_rotation_quaternion(),.5))
			box = FEED.rotated_box(piece.bounds,turn)
		var center := start.origin
		var align := smoothstep(.10,.48,t)
		center.x = lerpf(center.x,sin(index*2.4+t*TAU)*.035,align)
		center.z = lerpf(center.z,cos(index*1.7+t*TAU)*.035,align)
		# Lift clear of the rim before a section travels sideways into the hole.
		center.y = maxf(center.y,.87+box.size.y*.5)
		if t >= .48:
			center.x = clampf(center.x,-FEED.HALF_OPENING+box.size.x*.5,FEED.HALF_OPENING-box.size.x*.5)
			center.z = clampf(center.z,-FEED.HALF_OPENING+box.size.z*.5,FEED.HALF_OPENING-box.size.z*.5)
			center.y = lerpf(center.y,.68-box.size.y*.5,smoothstep(.48,1.0,t))
		piece.pose = Transform3D(turn,center-box.get_center())
		piece.node.transform = piece.pose
	sync(owner)

func sync(owner: Node3D) -> void:
	for piece in pieces:
		FEED.update_cut(piece.surfaces,owner)
		for record in piece.surfaces:
			record.cut.set_shader_parameter("world_to_piece",piece.node.global_transform.affine_inverse())

func dispose() -> void:
	for piece in pieces:
		FEED.restore_cut(piece.surfaces)
		if is_instance_valid(piece.node): piece.node.queue_free()
	pieces.clear()
	for mesh in originals:
		if is_instance_valid(mesh): mesh.show()
	originals.clear()
