extends Node3D
## Standalone art inspection; F1 wide, F2 detail, F12 exports the current render.
func _ready() -> void:
	DisplayServer.window_set_title("Ruined concrete wall - ApocalypseRV")
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().msaa_3d = Viewport.MSAA_4X
	if "--capture" in OS.get_cmdline_user_args():
		for frame in range(90): await get_tree().process_frame
		await capture("preview.png")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode == KEY_F1: $Wide.make_current()
	if event.keycode == KEY_F2: $Detail.make_current()
	if event.keycode == KEY_F12: await capture("detail.png" if $Detail.current else "preview.png")

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://art_source/ruined_wall/" + filename
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("WALL_RENDER: ", path, " result=", error)
