extends SceneTree
## Production RV, seed 42, real-time wheel drive; reports rendered frame timing.
## Run alone for comparable results. Headless timing does not measure the GPU.
func _init() -> void: run.call_deferred()

func run() -> void:
	root.title = "ApocalypseRV - Driving Performance Benchmark"
	root.size = Vector2i(1024, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play(60000):
		push_error("FAIL: benchmark world not ready")
		quit(1)
		return
	var rv: Chassis = world.get_node("NewRv/Chassis")
	var player: Node3D = world.get_node("Player")
	rv.get_node("DriverSeat").interact_hold(player)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	rv.allow_test_controls = true
	rv.set_engine_running(true)
	rv.set_gear(4)
	var clock: WorldClock = world.get_node("WorldClock")
	clock.weather_running = false
	clock.weather.set_weather(Vector3.ZERO, true)
	clock.set_time(1, 8)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("BENCHMARK engine=%s adapter=%s resolution=%s seed=42 weather=overcast vsync=off" % [Engine.get_version_info().string, RenderingServer.get_video_adapter_name(), root.size])
	await sample("parked", 4.0, rv)
	rv.handbrake = false
	rv.control_override = {"throttle": 1.0}
	await sample("driving", 24.0, rv)
	rv.control_override = {"brake": 1.0}
	var generator := world.get_node("WorldGenerator")
	generator.set_process(false)
	# Finish the active generator before shutdown. Do not free the world out
	# from under navigation's pending synchronization coroutines.
	while generator.building: await process_frame
	quit()

func sample(label: String, seconds: float, rv: Chassis) -> void:
	var frames: Array[float] = []
	var gpu_ms := 0.0
	var render_ms := 0.0
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < seconds * 1000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		render_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
	frames.sort()
	var count := frames.size()
	print("PROFILE %s frames=%d wall=%.2f mean=%.2f p95=%.2f p99=%.2f max=%.2f render=%.2f gpu=%.2f position=%s speed=%.2f" % [label, count, (previous - started) / 1000000.0, (previous - started) / 1000.0 / count, frames[int(count * 0.95)], frames[int(count * 0.99)], frames[-1], render_ms / count, gpu_ms / count, rv.global_position, rv.linear_velocity.length()])
