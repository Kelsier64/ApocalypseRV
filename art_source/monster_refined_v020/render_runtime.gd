extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1200,900)
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var a = load('res://enemies/raker.tscn').instantiate()
	var p = load('res://player/player.tscn').instantiate()
	world.add_child(a)
	world.add_child(p)
	a.set_physics_process(false)
	p.set_physics_process(false)
	p.position = Vector3(0,0,-1)
	a.target_player=p
	a.grab.victim=p
	a.grab.phase=a.grab.Phase.HOLD
	a.grab.elapsed=.5
	var v = a.get_node('BodyMesh')
	v.set_process(false)
	v.pose_modifier.active=true
	v.pose_modifier.tracking_weight=1
	v.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	v.animation_player.speed_scale=.001
	v.animation_player.play('game/grab_stand_hold',0)
	v.animation_player.seek(.5,true)
	v.animation_player.advance(0)
	v.pose_modifier._process_modification_with_delta(1)
	var env=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.15,.18,.2)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.8
	world.add_child(env)
	var light=DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees=Vector3(-40,-45,0)
	var cam=Camera3D.new()
	world.add_child(cam)
	cam.current=true
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.size=2.4
	for angle in ['front','side','hands','hinges']:
		var goal=Vector3(0,1.2,-.5)
		cam.position=Vector3(0,2,-4) if angle=='front' else Vector3(4,1.8,-.5)
		if angle=='hands':
			goal=Vector3(0,1.0,-.9)
			cam.position=Vector3(0,2.8,-2)
			cam.size=1.1
		if angle=='hinges':
			goal=Vector3(-.23,1.13,-1.05)
			cam.position=goal+Vector3(-2,.15,.1)
			cam.size=.5
		cam.look_at(goal)
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png('res://art_source/monster_refined_v020/runtime-grip-'+angle+'.png')
	quit()
