extends Node3D
## Interactive official recipe and control transfer with the real RV energy loop.
var rv: Chassis
var station: CraftingStation
var player: CharacterBody3D
var label: Label
var feedback := ""
var last_player_origin := Vector3.ZERO

func _ready() -> void:
	set_meta("entity_domain", true)
	DisplayServer.window_set_title("Printed Player - E control transfer")
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.045, .065, .09)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(.75, .84, .95)
	settings.ambient_light_energy = .7
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	ground.add_child(collision)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.14, .18, .22)
	material.roughness = .9
	plane.material = material
	mesh.mesh = plane
	ground.add_child(mesh)
	add_child(ground)
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true # Its production physics callback still advances energy/jobs.
	rv.set_engine_running(false)
	station = rv.get_node("CraftingStation")
	station.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(-5, 0, 0)), rv)
	player = load("res://player/player.tscn").instantiate()
	add_child(player)
	player.global_transform = Transform3D(Basis(Vector3.UP, PI), station.global_position + Vector3(0, -.25, -1.9))
	player.camera.look_at(station.spawn_marker.global_position + Vector3.UP * .9)
	player.camera.current = true
	last_player_origin = player.global_position
	var canvas := CanvasLayer.new()
	canvas.layer = 4
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(28, 160)
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
	var readiness_frames := 0
	while (rv.get_battery_socket() == null or rv.energy.battery == null or not station.can_operate()) and readiness_frames < 180:
		await get_tree().process_frame
		readiness_frames += 1
	queue_body()
	print("PRINTED_PLAYER_PLAYGROUND_READY real recipe20s, E switch, R print another, one production controller")
	if "--verify" in OS.get_cmdline_user_args(): _verify.call_deferred()

func queue_body() -> void:
	var recipe := RecipeCatalog.find("printed_player")
	rv.deposit_materials(recipe.costs)
	rv.current_power = rv.max_power
	feedback = "Body queued / 20 seconds" if station.request_craft(recipe.recipe_id) else station.last_error

func _process(_delta: float) -> void:
	if label == null: return
	var job_text := "Ready / look at the standing body and press E"
	if not station.jobs.is_empty(): job_text = "Printing / %.1f seconds" % station.jobs[0].remaining
	label.text = "PRINTED PLAYER / %s\nWASD move / mouse look / E switch bodies / R fabricate another\nHealth and limbs stay with each body. Equipment travels with you.\n%s" % [job_text, feedback]
	if player.global_position.distance_to(last_player_origin) > 1.0:
		print("PRINTED_PLAYER_MOVED controller=", player.get_instance_id(), " position=", player.global_position)
		last_player_origin = player.global_position

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and player.get_player_mode() == player.PlayerMode.NORMAL:
		queue_body()

func _verify() -> void:
	var elapsed := 0.0
	while not station.jobs.is_empty() and elapsed < 30:
		await get_tree().physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
	var body: PrintedPlayerBody
	for item in WorldEntities.get_container(self).get_children():
		if item is PrintedPlayerBody: body = item
	if body == null:
		push_error("Printed-player fixture did not complete its real recipe: " + station.last_error)
		get_tree().quit(1)
		return
	for frame in 5: await get_tree().physics_frame
	player.camera.look_at(body.global_position + Vector3.UP * .9)
	var ray := player.camera.get_node("InteractRay") as RayCast3D
	ray.force_raycast_update()
	if ray.get_collider() != body:
		push_error("Printed-player fixture E ray does not reach body")
		get_tree().quit(1)
		return
	var old_id := player.get_instance_id()
	var previous := player.global_position
	Input.action_press("interact")
	for frame in 3: await get_tree().physics_frame
	Input.action_release("interact")
	for frame in 3: await get_tree().physics_frame
	if player.get_instance_id() != old_id or player.global_position.distance_to(previous) < 1.0:
		push_error("Printed-player fixture native E transfer failed: " + body.last_transfer_error)
		get_tree().quit(1)
		return
	print("PASS: real-time recipe completed and actual E input switched the production controller to full-size printed body")
	get_tree().quit()
