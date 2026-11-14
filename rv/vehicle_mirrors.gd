extends Node3D
## Side and cabin mirrors share the vehicle world; no extra simulation or audio listener.
## Each mirror hangs from one structure slot, vanishes with it, and renders only while
## the player drives. Mirrors refresh round-robin, each at refresh_hz.
const MIRROR_LAYER := 1 << 19
## The cabin mirror never shows the complete player model.
const INTERIOR_CULL_MASK := 0xFFFFF & ~MIRROR_LAYER & ~PlayerModelVisual.FULL_BODY_LAYER
const SIDE_CULL_MASK := 0xFFFFF & ~MIRROR_LAYER
# Cabin mirror, RV-local: a digital rear-view display hung from the windshield top
# frame and turned to the driver's eye. Its lens sits above the rear doors, outside
# the body, so the cabin never blocks the view behind the RV.
const INTERIOR_MOUNT := Vector3(0.0, 2.28, -5.6)
const DRIVER_EYE := Vector3(-0.58, 2.12, -4.1)
const REAR_LENS := Vector3(0.0, 2.45, 6.15)
const REAR_TARGET := Vector3(0.0, 0.6, 18.0)
const INTERIOR_FACE_WIDTH := 0.48
@export var render_enabled := true
@export var resolution := Vector2i(192, 256)
@export var interior_resolution := Vector2i(480, 168)
@export_range(1.0, 30.0) var refresh_hz := 15.0
var mirrors: Array[Dictionary] = []
var dirty := true
var elapsed := 0.0
var next_mirror := 0
@onready var rv: Chassis = get_parent()

func _ready() -> void:
	rv.structure_changed.connect(func(): dirty = true)
	for side in [-1.0, 1.0]:
		var rig := Node3D.new()
		rig.name = "LeftMirror" if side < 0 else "RightMirror"
		add_child(rig)
		rig.position = Vector3(side * 2.3, 1.93, -5.5)
		rig.basis = Basis.looking_at(Vector3(-0.58, 2.05, -3.97) - rig.position, Vector3.UP, true)
		var housing := RoadsideKit.part(rig, Vector3(0.43, 0.58, 0.09), Vector3.ZERO, Color("282e30"))
		housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var arm := RoadsideKit.part(rig, Vector3(0.5, 0.04, 0.04), Vector3(-side * 0.2, -0.18, -0.04), Color("565d5d"))
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var camera_position := Vector3(side * 2.3, 1.93, -5.45)
		var look := Basis.looking_at(Vector3(side * 3.1, 0.8, 8.0) - camera_position, Vector3.UP)
		_add_mirror("left_0" if side < 0 else "right_0", rig, rig, Vector2(0.38, 0.52), 0.051, resolution, 62.0, 0.15, SIDE_CULL_MASK, Transform3D(look, camera_position))
	_add_interior_mirror()

func _add_interior_mirror() -> void:
	var rig := Node3D.new()
	rig.name = "InteriorMirror"
	add_child(rig)
	rig.position = INTERIOR_MOUNT
	var dark := Color("1f2325")
	# Stem from the roof; the display head turns to face the driver.
	var stem := RoadsideKit.part(rig, Vector3(0.03, 0.2, 0.03), Vector3(0.0, 0.12, -0.07), dark)
	var plate := RoadsideKit.part(rig, Vector3(0.09, 0.015, 0.07), Vector3(0.0, 0.215, -0.08), dark)
	var head := Node3D.new()
	head.name = "Head"
	rig.add_child(head)
	head.basis = Basis.looking_at(DRIVER_EYE - INTERIOR_MOUNT, Vector3.UP, true)
	var face_size := Vector2(INTERIOR_FACE_WIDTH, INTERIOR_FACE_WIDTH * float(interior_resolution.y) / float(interior_resolution.x))
	var housing := RoadsideKit.part(head, Vector3(face_size.x + 0.03, face_size.y + 0.03, 0.04), Vector3.ZERO, dark)
	for part in [stem, plate, housing]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.layers = MIRROR_LAYER
	var lens := Transform3D(Basis.looking_at(REAR_TARGET - REAR_LENS, Vector3.UP), REAR_LENS)
	_add_mirror("front", rig, head, face_size, 0.021, interior_resolution, 28.0, 0.05, INTERIOR_CULL_MASK, lens)

func _add_mirror(slot: String, rig: Node3D, surface: Node3D, face_size: Vector2, face_offset: float, size: Vector2i, fov: float, near: float, cull_mask: int, lens: Transform3D) -> void:
	var viewport := SubViewport.new()
	viewport.name = rig.name + "View"
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = fov
	camera.near = near
	camera.far = 65.0
	camera.cull_mask = cull_mask
	viewport.add_child(camera)
	camera.current = true
	var face := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = face_size
	face.mesh = mesh
	face.position.z = face_offset
	face.layers = MIRROR_LAYER
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.uv1_scale.x = -1.0
	mat.uv1_offset.x = 1.0
	face.material_override = mat
	surface.add_child(face)
	mirrors.append({"slot": slot, "rig": rig, "viewport": viewport, "camera": camera, "panel": null, "face": face, "lens": lens})

## RV-local mirror by slot ("left_0", "right_0", "front"); empty when absent.
func mirror_for(slot: String) -> Dictionary:
	for mirror in mirrors:
		if mirror.slot == slot: return mirror
	return {}

func _process(delta: float) -> void:
	if dirty:
		for mirror in mirrors:
			mirror.panel = null
			for device in rv.get_structures():
				if device.get("mount_slot") == mirror.slot:
					mirror.panel = weakref(device)
		dirty = false
	var driver_camera := get_viewport().get_camera_3d()
	var driving := render_enabled and rv.is_player_driving and driver_camera != null and rv.is_ancestor_of(driver_camera)
	elapsed += delta
	var refresh := elapsed >= 1.0 / (refresh_hz * mirrors.size())
	if refresh: elapsed = 0.0
	for i in range(mirrors.size()):
		var mirror := mirrors[i]
		var panel: RVStructurePanel = mirror.panel.get_ref() if mirror.panel else null
		var mounted := is_instance_valid(panel) and panel.can_operate() and panel.get_connected_rv() == rv
		mirror.rig.visible = mounted
		if not mounted or not driving:
			mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_register_night_view(mirror.viewport, false)
			continue
		if mirror.viewport.world_3d != get_world_3d(): mirror.viewport.world_3d = get_world_3d()
		# SubViewport cameras do not inherit the RV transform; place them each frame.
		mirror.camera.global_transform = rv.global_transform * mirror.lens
		if refresh and i == next_mirror:
			mirror.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_register_night_view(mirror.viewport, true)
	if refresh: next_mirror = (next_mirror + 1) % mirrors.size()

func _register_night_view(viewport: SubViewport, active: bool) -> void:
	var effect := NightVisionEffect.find_for(self)
	if effect != null: effect.register_viewport(viewport, active)
