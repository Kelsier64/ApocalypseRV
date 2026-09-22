extends Node3D
## Side-panel mirrors share the vehicle world; no extra simulation or audio listener.
const MIRROR_LAYER := 1 << 19
@export var render_enabled := true
@export var resolution := Vector2i(192, 256)
@export_range(1.0, 30.0) var refresh_hz := 15.0
var mirrors: Array[Dictionary] = []
var dirty := true
var elapsed := 0.0
var next_mirror := 0
@onready var rv: Chassis = get_parent()

func _ready() -> void:
	rv.equipment_changed.connect(func(): dirty = true)
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
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.gui_disable_input = true
		viewport.positional_shadow_atlas_size = 0
		add_child(viewport)
		var camera := Camera3D.new()
		camera.fov = 62.0
		camera.near = 0.15
		camera.far = 65.0
		camera.cull_mask = 0xFFFFF & ~MIRROR_LAYER
		viewport.add_child(camera)
		camera.current = true
		var face := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.38, 0.52)
		face.mesh = mesh
		face.position.z = 0.051
		face.layers = MIRROR_LAYER
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = viewport.get_texture()
		mat.uv1_scale.x = -1.0
		mat.uv1_offset.x = 1.0
		face.material_override = mat
		rig.add_child(face)
		mirrors.append({"side": side, "rig": rig, "viewport": viewport, "camera": camera, "panel": null, "face": face})

func _process(delta: float) -> void:
	if dirty:
		for mirror in mirrors:
			mirror.panel = null
			for device in rv.get_equipment():
				if device.get("mount_slot") == ("left_0" if mirror.side < 0 else "right_0"):
					mirror.panel = weakref(device)
		dirty = false
	var driver_camera := get_viewport().get_camera_3d()
	var driving := render_enabled and rv.is_player_driving and driver_camera != null and rv.is_ancestor_of(driver_camera)
	elapsed += delta
	var refresh := elapsed >= 1.0 / (refresh_hz * 2.0)
	if refresh: elapsed = 0.0
	for i in range(mirrors.size()):
		var mirror := mirrors[i]
		var panel: Equipment = mirror.panel.get_ref() if mirror.panel else null
		var mounted := is_instance_valid(panel) and panel.can_operate() and panel.get_connected_rv() == rv
		mirror.rig.visible = mounted
		if not mounted or not driving:
			mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		var side: float = mirror.side
		# Fixed slot coordinates, attached to each front side panel's availability.
		if mirror.viewport.world_3d != get_world_3d(): mirror.viewport.world_3d = get_world_3d()
		mirror.camera.global_position = rv.to_global(Vector3(side * 2.3, 1.93, -5.45))
		mirror.camera.look_at(rv.to_global(Vector3(side * 3.1, 0.8, 8.0)), rv.global_basis.y)
		if refresh and i == next_mirror:
			mirror.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if refresh: next_mirror = (next_mirror + 1) % mirrors.size()
