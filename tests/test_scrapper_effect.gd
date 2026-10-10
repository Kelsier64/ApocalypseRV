extends SceneTree
## Cosmetic lifecycle follows real powered work without changing input ownership.
const CHANNELS := ["MetalChips", "Dust", "FleshChunks", "BloodSpray", "Sparks"]
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var machine: Item
var effect: Node3D
var channel_ids: Dictionary = {}
var particle_ids: Dictionary = {}
var particle_budgets: Dictionary = {}
var effect_id := 0

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func steps(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func particles(label: String) -> CPUParticles3D:
	return effect.get_node_or_null(label) as CPUParticles3D

func sound() -> AudioStreamPlayer3D:
	return effect.get_node_or_null("GrindingSound") as AudioStreamPlayer3D

func stopped(note: String, cleared := false) -> void:
	check(not effect.working and not sound().playing, note + " stops continuous work and grinding sound")
	for label: String in CHANNELS: check(not particles(label).emitting, note + " stops new " + label + " particles")
	if cleared:
		for emitter: CPUParticles3D in effect.find_children("*", "CPUParticles3D", true, false):
			check(not emitter.emitting, note + " also clears its one-shot particle emitters")

func reused(note: String) -> void:
	check(effect.get_instance_id() == effect_id and effect.get_parent() == machine, note + " retains one effect owned by the machine")
	for label: String in CHANNELS:
		check(particles(label).get_instance_id() == channel_ids[label], note + " reuses its bounded " + label + " emitter")
	var all_particles := effect.find_children("*", "CPUParticles3D", true, false)
	check(all_particles.size() == particle_ids.size(), note + " creates no additional transient emitters")
	for emitter: CPUParticles3D in all_particles:
		check(particle_ids.get(String(emitter.name)) == emitter.get_instance_id() and particle_budgets.get(String(emitter.name)) == emitter.amount, note + " retains every continuous/burst emitter and its original budget")

func cosmetic_tree(node: Node) -> void:
	check(not node is CollisionObject3D and not node is CollisionShape3D and not node is Item, "VFX subtree contains no gameplay body, shape or Item")
	check(not node.is_in_group(Groups.ITEMS) and not node.is_in_group(Groups.MONSTERS) and not node.is_in_group(Groups.MONSTER_DAMAGEABLE), "VFX subtree does not register gameplay entities")
	for child in node.get_children(): cosmetic_tree(child)

func saved_input_only(expected_inputs: int) -> void:
	var state: Dictionary = machine.capture_service_state()
	check(state.keys().size() == 1 and state.has("inputs") and state.inputs.size() == expected_inputs, "Service snapshot persists only its real input queue")
	check(VehicleSnapshot.valid_device(VehicleSnapshot.device_state(machine)), "Cosmetic activity leaves the production device snapshot valid")

func fixture() -> bool:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position = Vector3(30, 0, 0)
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	await steps(3)
	rv.current_power = 20.0
	machine = rv.get_node("Scrapper")
	effect = machine.get("crush_effect") as Node3D
	check(machine.can_operate(), "Fixture uses the production powered RV-mounted recycler")
	check(effect != null and machine.get_node_or_null("CrushEffect") == effect, "Production recycler owns one CrushEffect child")
	if effect == null: return false
	effect_id = effect.get_instance_id()
	var total_budget := 0
	var channels_ready := true
	for label: String in CHANNELS:
		var emitter := particles(label)
		check(emitter != null, "Production VFX provides " + label + " particles")
		if emitter == null:
			channels_ready = false
			continue
		channel_ids[label] = emitter.get_instance_id()
	for emitter: CPUParticles3D in effect.find_children("*", "CPUParticles3D", true, false):
		particle_ids[String(emitter.name)] = emitter.get_instance_id()
		particle_budgets[String(emitter.name)] = emitter.amount
		total_budget += emitter.amount
		check(emitter.amount > 0 and emitter.amount <= 256, String(emitter.name) + " has a bounded fixed particle budget")
	check(total_budget <= 1024, "One recycler keeps its total particle budget bounded")
	check(sound() != null and sound().stream != null, "Grinding sound owns a reusable audio stream")
	if not channels_ready or sound() == null: return false
	cosmetic_tree(effect)
	stopped("Idle machine")
	saved_input_only(0)
	return true

func metal_work_and_output_retry() -> void:
	var input: Item = load("res://props/scrap.tscn").instantiate()
	input.position = Vector3(-20, 4, 0)
	WorldEntities.get_container(world).add_child(input)
	input.scrap_yields = {ItemNames.METAL_PARTS: Vector2(3, 3)}
	var materials_before := rv.get_all_items()
	machine.recycle_prop(input)
	await steps(2)
	check(input.processing_owner == machine and machine.props_being_crushed.size() == 1, "Metal effect fixture retains one production Item input")
	var timer_before: float = machine.props_being_crushed[0].timer
	var power_before := rv.current_power
	machine.step_work(0.0)
	await steps(2)
	stopped("Zero-duration service tick")
	check(machine.props_being_crushed[0].timer == timer_before and rv.current_power == power_before, "Zero-duration visual tick cannot advance the job or spend power")
	machine.step_work(.1)
	check(effect.working and not effect.organic, "Positive powered Item work activates metal effects")
	check(particles("MetalChips").emitting and particles("Dust").emitting and particles("Sparks").emitting, "Metal input enables its continuous material channels")
	check(not particles("FleshChunks").emitting and not particles("BloodSpray").emitting, "Metal input leaves organic channels inactive")
	check(sound().playing, "Actual powered work starts the grinding loop")
	check(is_equal_approx(rv.current_power, power_before - machine.power_draw_per_second * .1) and rv.get_all_items() == materials_before, "Visual work uses only the recycler's existing power draw and produces no early material")
	saved_input_only(1)
	reused("Metal work")
	var heartbeat_timer: float = machine.props_being_crushed[0].timer
	var heartbeat_bursts: int = effect.burst_count
	await steps(12)
	stopped("Stopped positive-work heartbeat")
	check(machine.props_being_crushed[0].timer == heartbeat_timer and effect.burst_count == heartbeat_bursts, "Cosmetic timeout cannot advance the input or repeat intake bursts")
	machine.step_work(.1)
	rv.current_power = 0.0
	await steps(3)
	stopped("Power lost without another service tick")
	var paused_timer: float = machine.props_being_crushed[0].timer
	var paused_position := input.global_position
	var paused_bursts: int = effect.burst_count
	machine.step_work(.4)
	await steps(2)
	check(machine.props_being_crushed[0].timer == paused_timer and input.global_position.is_equal_approx(paused_position) and rv.current_power == 0.0, "Unpowered input preserves progress and position")
	check(effect.burst_count == paused_bursts and rv.get_all_items() == materials_before, "Power pause adds neither visual transition bursts nor materials")
	rv.current_power = 20.0
	machine.step_work(.1)
	check(effect.working and sound().playing, "Restored power resumes the existing effect and loop")
	machine.enabled = false
	await steps(3)
	stopped("Disabled machine without another service tick")
	paused_timer = machine.props_being_crushed[0].timer
	power_before = rv.current_power
	machine.step_work(.2)
	await steps(2)
	check(machine.props_being_crushed[0].timer == paused_timer and rv.current_power == power_before, "Disabled visual job cannot advance or consume power")
	machine.enabled = true
	machine.step_work(.1)
	var intake_bursts: int = effect.burst_count
	var capacity_before := rv.material_capacity
	rv.material_capacity = 0
	machine.step_work(2.0)
	await steps(3)
	check(is_instance_valid(input) and input.processing_owner == machine and machine.props_being_crushed[0].timer <= 0.0, "Full output retains the completed real input for transactional retry")
	stopped("Completed job waiting for output space")
	var waiting_bursts: int = effect.burst_count
	var rolled_result: Dictionary = input.get_meta("recycle_result").duplicate(true)
	power_before = rv.current_power
	for retry in 3:
		machine.step_work(.3)
		await steps(2)
	check(rv.current_power == power_before and rv.get_all_items() == materials_before and effect.burst_count == waiting_bursts, "Repeated full-output retries add no power draw, deposit or repeated finish burst")
	check(input.get_meta("recycle_result") == rolled_result, "Cosmetic retries preserve the one rolled material payload")
	rv.material_capacity = capacity_before
	machine.step_work(.1)
	await steps(3)
	check(not is_instance_valid(input) and machine.props_being_crushed.is_empty(), "Available output space commits and removes the original input once")
	check(rv.get_item_count(ItemNames.METAL_PARTS) == int(materials_before.get(ItemNames.METAL_PARTS, 0)) + 3, "Metal VFX completion grants only the input's fixed material payload")
	check(effect.burst_count == intake_bursts + 1, "Completion emits exactly one finish burst across output retries")
	stopped("Committed idle machine")
	var finished_bursts: int = effect.burst_count
	machine.step_work(.5)
	await steps(2)
	check(effect.burst_count == finished_bursts, "Idle ticks cannot repeat completion effects")
	saved_input_only(0)
	reused("Metal completion and retries")

func organic_work_and_cancellation() -> void:
	var corpse: CorpseProp = load("res://props/corpse.tscn").instantiate()
	corpse.kind = "player"
	for part: StringName in PlayerBodyState.PARTS: corpse.body_state.sever(part)
	corpse.global_transform = machine.global_transform * Transform3D(Basis.IDENTITY, Vector3(0,.62,0))
	WorldEntities.get_container(world).add_child(corpse)
	await steps(3)
	check(corpse.initialized and corpse.bodies.size() == 3, "Organic fixture uses the real articulated player torso handed off by staged feeding")
	corpse.scrap_yields = {ItemNames.UNKNOWN_MATERIAL: Vector2(2, 2)}
	var materials_before := rv.get_all_items()
	machine.recycle_prop(corpse)
	await steps(3)
	machine.step_work(.1)
	check(effect.working and effect.organic and sound().playing, "Actual powered corpse work switches the reused effect to organic mode")
	check(particles("FleshChunks").emitting and particles("BloodSpray").emitting and not particles("MetalChips").emitting, "Corpse input activates organic channels and stops metal chips")
	check(corpse.processing and corpse.physical_feed and corpse.simulator.is_simulating_physics() and corpse.processing_owner == machine, "Organic effects preserve the recycler's sole ownership and physical torso feed")
	check(rv.get_all_items() == materials_before, "Organic particles do not create their own material yield")
	saved_input_only(1)
	reused("Organic transition")
	var bursts_before: int = effect.burst_count
	machine.prepare_pickup()
	await steps(4)
	stopped("Recycler service removal", true)
	check(machine.props_being_crushed.is_empty() and not corpse.processing and not is_instance_valid(corpse.processing_owner) and corpse.simulator.is_simulating_physics(), "Cancelling the machine releases the actual corpse into articulated physics")
	check(rv.get_all_items() == materials_before and effect.burst_count == bursts_before, "Cancellation adds no finish burst or material deposit")
	effect.stop(true)
	effect.stop(true)
	await steps(2)
	stopped("Repeated clear-tail stop", true)
	reused("Service cancellation")
	check(effect.burst_count == bursts_before, "Repeated effect cleanup does not create another transition")
	saved_input_only(0)

func presentation_and_owner_cleanup() -> void:
	var preview: Item = load("res://equipment/scrapper.tscn").instantiate()
	preview.presentation_only = true
	preview.position = Vector3(-30, 0, 0)
	world.add_child(preview)
	await steps(3)
	check(preview.get("crush_effect") == null and preview.get_node_or_null("CrushEffect") == null, "Presentation-only recycler creates no live effect or grinding sound")
	check(not preview.can_operate() and not preview.is_in_group(Groups.ITEMS), "Presentation remains outside gameplay services and Item discovery")
	var effect_ref: WeakRef = weakref(effect)
	machine.queue_free()
	await steps(3)
	check(effect_ref.get_ref() == null, "Deleting the recycler deletes its owned effect subtree")
	for child in WorldEntities.get_container(world).get_children():
		check(child.name != "CrushEffect", "Effect cleanup leaves no orphan entity in the world container")

func run() -> void:
	if await fixture():
		await metal_work_and_output_retry()
		await organic_work_and_cancellation()
		await presentation_and_owner_cleanup()
	world.queue_free()
	await steps(3)
	if failures.is_empty(): print("PASS: recycler VFX lifecycle, bounded cosmetic ownership, power gates and transactional output retries")
	quit(0 if failures.is_empty() else 1)
