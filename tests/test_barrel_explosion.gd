extends SceneTree
## Production Player/panels/RV: blast geometry, shields, hurt gate and cuts.
const PLAYER := preload("res://player/player.tscn")
const PANEL := preload("res://equipment/rv_side_panel.tscn")
const RV := preload("res://rv/new_rv.tscn")
var failures: Array[String] = []
var arena: Node3D
var actor: CharacterBody3D

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok: failures.append(detail); push_error("FAIL: " + detail)

func steps(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func fresh(position: Vector3 = Vector3.ZERO, body: Dictionary = {}) -> void:
	actor.ragdoll_control.stop()
	actor.is_player_dead = false
	actor.damage_cooldown = 0.0
	var state := {"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis.IDENTITY, position)}
	if not body.is_empty(): state["body"] = body
	actor.restore_checkpoint_state(state)
	actor.set_physics_process(false)

func present_limbs() -> int:
	var count := 0
	for limb: StringName in [&"left_arm", &"right_arm", &"left_leg", &"right_leg"]:
		if actor.body_state.has_part(limb): count += 1
	return count

func blast(origin: Vector3, contacted: Node3D = null, tuning: BarrelManSettings = null) -> Node3D:
	var source := Node3D.new()
	arena.add_child(source)
	source.global_position = origin
	BarrelExplosion.explode(source, origin, contacted, tuning)
	return source

func clear_effects() -> void:
	for group in ["player_detached_parts", "barrel_explosion_effects"]:
		for effect: Node in get_nodes_in_group(group): effect.queue_free()
	await steps()

func geometry() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 8)
	var pose := Transform3D(Basis(Vector3.UP, PI * 0.3).scaled(Vector3(2, 1, 0.5)), Vector3(9, 3, -5))
	var point := pose * Vector3(3, 0, 0)
	var near: Vector3 = BarrelExplosion.closest_shape_point(box, pose, point).point
	check(near.is_equal_approx(pose * Vector3(2, 0, 0)), "Rotated/scaled box uses true shape surface")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3; capsule.height = 1.8
	check(BarrelExplosion.closest_shape_point(capsule, Transform3D.IDENTITY, Vector3(2, 0.9, 0)).point.distance_to(Vector3(2, 0.9, 0)) > 1.7, "Capsule projects to rounded cap rather than AABB corner")
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.4; cylinder.height = 1.0
	check(BarrelExplosion.closest_shape_point(cylinder, Transform3D.IDENTITY, Vector3(1, 0, 0)).point == Vector3(0.4, 0, 0), "Cylinder projects to radial surface")
	check(is_equal_approx(BarrelExplosion.falloff(1.5, 1.5, 4, 70), 70), "Player full damage includes 1.5 m boundary")
	check(is_equal_approx(BarrelExplosion.falloff(2.75, 1.5, 4, 70), 35), "Player outer damage decreases linearly")
	check(BarrelExplosion.falloff(4, 1.5, 4, 70) == 0, "Outer radius is excluded")

func damage_gate_and_cuts() -> void:
	fresh()
	actor.velocity = Vector3(3, 0, -2)
	var impulse := Vector3(4, 3, 0)
	check(actor.apply_explosion_hit(70, 2, impulse), "Intact player accepts one blast")
	check(actor.current_player_health == 30 and present_limbs() == 2 and actor.body_state.has_part(&"head"), "One hit removes two different surviving limbs without head")
	check(not actor.apply_explosion_hit(70, 2, impulse), "Hurt cooldown rejects health and cuts together")
	check(actor.current_player_health == 30 and present_limbs() == 2, "Cooldown cannot cut additional limbs")
	for effect: Node in get_nodes_in_group("player_detached_parts"):
		check(effect.launch_velocity.is_equal_approx(Vector3(7, 3, -2)), "Detached limbs inherit pre-cut motion and blast impulse")
	await clear_effects()
	fresh()
	check(not actor.apply_explosion_hit(0, 2) and not actor.apply_explosion_hit(NAN, 2), "Nonpositive/nonfinite damage never cuts")
	actor.sever_part(&"left_arm")
	actor.sever_part(&"right_arm")
	actor.sever_part(&"left_leg")
	actor.damage_cooldown = 0
	check(actor.apply_explosion_hit(10, 2) and present_limbs() == 0, "Two requested cuts use only the single remaining limb")
	check(actor.body_state.has_part(&"head") and actor.current_player_health == 90, "No eligible limbs never promotes to head loss or extra HP damage")
	actor.damage_cooldown = 0
	check(actor.apply_explosion_hit(10, 2) and actor.current_player_health == 80, "Limbless player still takes ordinary blast damage")
	await clear_effects()
	fresh()
	actor.current_player_health = 20
	var cuts_before_death: Array[bool] = []
	var observe := func() -> void: cuts_before_death.append(not actor.is_player_dead)
	actor.body_state_changed.connect(observe)
	check(actor.apply_explosion_hit(70, 2, impulse), "Fatal blast is accepted")
	actor.body_state_changed.disconnect(observe)
	check(actor.is_player_dead and actor.current_player_health == 0 and present_limbs() == 2, "Fatal health commits after both sever operations")
	check(cuts_before_death == [true, true], "Both body changes happen while the player is still alive")
	check(not actor.apply_explosion_hit(70, 2) and present_limbs() == 2, "Dead player rejects subsequent blast/cuts")
	await clear_effects()
	fresh()

func blast_distances_and_worlds() -> void:
	await steps()
	var shape: CapsuleShape3D = actor.body_collision_shape.shape
	var center: Vector3 = actor.body_collision_shape.global_position
	var distance := 0.8
	var source := blast(center + Vector3.RIGHT * (shape.radius + distance))
	check(actor.current_player_health == 30 and present_limbs() == 2, "0.8 m surface boundary cuts two limbs")
	var effects_before := get_nodes_in_group("barrel_explosion_effects").size()
	actor.damage_cooldown = 0
	BarrelExplosion.explode(source, source.global_position)
	check(actor.current_player_health == 30 and present_limbs() == 2 and get_nodes_in_group("barrel_explosion_effects").size() == effects_before, "Duplicate explosion damages and emits once even after hurt gate expires")
	source.queue_free()
	await clear_effects()
	fresh()
	await steps()
	shape = actor.body_collision_shape.shape
	center = actor.body_collision_shape.global_position
	blast(center + Vector3.RIGHT * (shape.radius + 1.5)).queue_free()
	check(actor.current_player_health == 30 and present_limbs() == 3, "1.5 m surface boundary cuts one limb")
	await clear_effects()
	fresh()
	await steps()
	shape = actor.body_collision_shape.shape
	center = actor.body_collision_shape.global_position
	blast(center + Vector3.RIGHT * (shape.radius + 2.75)).queue_free()
	check(is_equal_approx(actor.current_player_health, 65) and present_limbs() == 4, "Farther visible body has linear damage and keeps limbs (HP %s, limbs %s)" % [actor.current_player_health, present_limbs()])
	await clear_effects()
	fresh()
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var indoor := Node3D.new()
	viewport.add_child(indoor)
	var other: CharacterBody3D = PLAYER.instantiate()
	indoor.add_child(other)
	other.set_physics_process(false)
	await steps()
	blast(actor.body_collision_shape.global_position).queue_free()
	check(other.current_player_health == 100 and other.body_state.has_part(&"left_leg"), "Independent World3D player ignores colocated outdoor explosion")
	viewport.queue_free()
	await clear_effects()
	fresh(Vector3(50, 0, 0))

func shields_and_deduplication() -> void:
	var panel: RVStructurePanel = PANEL.instantiate()
	panel.position = Vector3(0, 1, 0)
	arena.add_child(panel)
	var duplicate_shape := CollisionShape3D.new()
	duplicate_shape.shape = panel.get_node("Collision").shape
	panel.add_child(duplicate_shape)
	var damage_calls: Array[int] = []
	panel.damaged.connect(func() -> void: damage_calls.append(1))
	var cargo: Item = load("res://equipment/generator.tscn").instantiate()
	arena.add_child(cargo)
	cargo.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(1, 0.6, -0.3)), arena, panel)
	var cargo_health: float = cargo.current_health
	fresh(Vector3(0, 0, 1.0))
	await steps()
	blast(Vector3(0, 1, -1)).queue_free()
	check(panel.is_destroyed and damage_calls.size() == 1, "Two colliders belonging to one production panel pay shell damage once")
	check(actor.current_player_health == 100 and present_limbs() == 4, "Complete panel shields player even when the same blast destroys it")
	await steps()
	check(not cargo.is_fixed and cargo.support_lost and cargo.current_health == cargo_health, "Immune Item drops through its existing support-loss contract after shell destruction")
	blast(Vector3(0, 1, -1)).queue_free()
	check(actor.current_player_health < 100, "Existing broken panel no longer shields next blast")
	panel.queue_free()
	cargo.queue_free()
	await clear_effects()
	# Closest torso ray is blocked, but the actual upper capsule is exposed.
	fresh(Vector3(0, 0, 1))
	var low_wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var short_box := BoxShape3D.new()
	short_box.size = Vector3(4, 1.2, 0.2)
	collision.shape = short_box
	low_wall.add_child(collision)
	low_wall.position = Vector3(0, 0.6, 0)
	arena.add_child(low_wall)
	await steps()
	blast(Vector3(0, 1, -1)).queue_free()
	check(actor.current_player_health < 100, "An exposed upper capsule takes blast damage even when its nearest point is behind a shield")
	low_wall.queue_free()
	await clear_effects()
	fresh(Vector3(50, 0, 0))

func production_rv_and_item() -> void:
	var shell: Node3D = RV.instantiate()
	shell.position = Vector3(0, 2, 0)
	arena.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	await steps(3)
	var engine_before: float = rv.get_engine().health
	# Capture vehicle motion once before either cut can revoke driving.
	fresh()
	var seat: Node3D = rv.get_node("DriverSeat")
	seat.interact_hold(actor)
	check(actor.seated_in == seat, "Production seat accepts intact player for momentum test")
	rv.linear_velocity = Vector3(3, 0, -2)
	rv.angular_velocity = Vector3(0, 0.2, 0)
	var inherited := ClimbMath.point_velocity(rv, actor.global_position)
	var seated_impulse := Vector3(4, 3, 0)
	actor.apply_explosion_hit(70, 2, seated_impulse)
	actor.set_physics_process(false)
	for effect: Node in get_nodes_in_group("player_detached_parts"):
		check(effect.launch_velocity.is_equal_approx(inherited + seated_impulse), "Both seated cuts retain velocity captured before forced exit")
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	await clear_effects()
	fresh(Vector3(50, 0, 0))
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(16, 16, 0.3)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	wall.position = rv.to_global(Vector3(0, 1.4, 7.0))
	arena.add_child(wall)
	await steps()
	blast(rv.to_global(Vector3(0, 1.4, 8.0))).queue_free()
	check(rv.get_engine().health == engine_before, "An uncontacted RV behind a complete external shield receives no engine transfer")
	wall.queue_free()
	await steps()
	var rear := rv.to_global(Vector3(0, 1.4, 6.0))
	var source := blast(rear, rv)
	check(is_equal_approx(rv.get_engine().health, engine_before - 60), "Rear contact beyond chassis center radius damages engine exactly once")
	actor.damage_cooldown = 0
	BarrelExplosion.explode(source, rear, rv)
	check(is_equal_approx(rv.get_engine().health, engine_before - 60), "Repeat callback cannot charge engine again")
	source.queue_free()
	var item: Item = load("res://equipment/generator.tscn").instantiate()
	item.position = Vector3(15, 1, 0)
	arena.add_child(item)
	item.freeze = true
	await steps()
	var health: float = item.current_health
	item.confirm_placement(Transform3D(Basis.IDENTITY, rv.to_global(Vector3(15, 1, 0))), rv, rv)
	var engine_at_item: float = rv.get_engine().health
	blast(item.global_position, item).queue_free()
	check(item.current_health == health and not item.is_destroyed, "Production Item is immune at the center of the explosion")
	check(rv.get_engine().health == engine_at_item, "An Item-only blast never transfers damage to a distant RV ancestor")
	var item_child := StaticBody3D.new()
	item.add_child(item_child)
	blast(item.global_position, item_child).queue_free()
	check(rv.get_engine().health == engine_at_item, "An Item child collider cannot bypass Item immunity through contact ancestry")
	var monster: Monster = load("res://enemies/raker.tscn").instantiate()
	monster.position = Vector3(20, 0, 0)
	arena.add_child(monster)
	monster.set_physics_process(false)
	var monster_health: float = monster.current_health
	blast(monster.global_position + Vector3.UP * 0.8).queue_free()
	check(monster.current_health == monster_health and not monster.is_dead, "Other monsters never receive blast damage or start a chain")
	monster.is_dead = true
	BarrelExplosion.explode(monster, monster.global_position + Vector3.UP * 0.8)
	check(monster.has_meta("barrel_blast_resolved"), "Resolver accepts a source latched dead earlier in the same physics frame")
	monster.queue_free()
	item.queue_free()
	shell.queue_free()
	await clear_effects()

func cosmetic_lifecycle() -> void:
	# A translated entity container must be placed before the effect's ready-time
	# floor ray; otherwise the visual may sample ground at the domain origin.
	var domain := Node3D.new()
	domain.position = Vector3(80, 4, -30)
	domain.set_meta("entity_domain", true)
	arena.add_child(domain)
	var container := WorldEntities.get_container(domain)
	container.position = Vector3(-6, 2, 7)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8, .2, 8)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position = Vector3(2, -.1, -3)
	domain.add_child(floor_body)
	await steps()
	var origin := domain.to_global(Vector3(2, 1.3, -3))
	var source := Node3D.new()
	source.position = domain.to_local(origin)
	domain.add_child(source)
	BarrelExplosion.explode(source, origin)
	check(container.get_child_count() == 1, "A blast creates one effect in its translated entity domain")
	if container.get_child_count() != 1:
		domain.queue_free()
		await steps()
		return
	var first = container.get_child(0)
	first.set_process(false)
	check(first.global_position.is_equal_approx(origin), "Effect retains the blast's world origin under a translated WorldEntities")
	check(first.ring != null, "Ready-time ground wave finds the floor below the actual blast origin")
	if first.ring != null:
		check(first.ring.global_position.is_equal_approx(domain.to_global(Vector3(2, .045, -3))), "Ground wave lies just above the sampled floor")
	check(first.find_children("*", "CollisionObject3D", true, false).is_empty(), "Explosion visuals have no collision bodies or trigger Areas")
	first._process(.75)
	var first_age: float = first.age
	var fire_age: float = first.fire_material.get_shader_parameter("age")
	var smoke_age: float = first.smoke_material.get_shader_parameter("age")
	var second_source := Node3D.new()
	second_source.position = domain.to_local(origin + Vector3.RIGHT)
	domain.add_child(second_source)
	BarrelExplosion.explode(second_source, second_source.global_position)
	check(container.get_child_count() == 2, "A second source creates an independent overlapping effect")
	if container.get_child_count() == 2:
		var second = container.get_child(1)
		second.set_process(false)
		check(first.fire_material != second.fire_material and first.smoke_material != second.smoke_material, "Overlapping bursts keep separate animated fire and smoke materials")
		second._process(.2)
		check(is_equal_approx(first.age, first_age) and is_equal_approx(first.fire_material.get_shader_parameter("age"), fire_age) and is_equal_approx(first.smoke_material.get_shader_parameter("age"), smoke_age), "Starting and advancing another burst does not reset the first burst's age or materials")
	first._process(first.DURATION - first.age - .01)
	check(not first.is_queued_for_deletion(), "Effect remains alive until its cosmetic duration finishes")
	first._process(.02)
	check(first.is_queued_for_deletion(), "Completed effect queues its particles, light and sound for cleanup")
	await steps()
	check(not is_instance_valid(first), "Completed effect is released without wall-clock waiting")
	domain.queue_free()
	await steps()

func run() -> void:
	seed(817303)
	arena = Node3D.new()
	root.add_child(arena)
	current_scene = arena
	actor = PLAYER.instantiate()
	arena.add_child(actor)
	actor.set_physics_process(false)
	await steps()
	geometry()
	await damage_gate_and_cuts()
	await blast_distances_and_worlds()
	await shields_and_deduplication()
	await production_rv_and_item()
	await cosmetic_lifecycle()
	arena.queue_free()
	await steps(6)
	if failures.is_empty(): print("PASS: barrel blast surface geometry, hurt gate, cuts/death order, shields, deduplication, RV rear-contact damage, World3D/Item isolation and cosmetic lifecycle")
	quit(0 if failures.is_empty() else 1)
