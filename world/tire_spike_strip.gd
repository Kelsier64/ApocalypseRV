extends Area3D
class_name TireSpikeStrip
## The Area only selects nearby chassis. Actual damage requires a grounded
## tire contact patch to cross the visible spikes, never body overlap alone.
const LENGTH := 2.4
const DEPTH := 0.45
const SPAWN_CHANCE := 0.08
var nearby: Array[Chassis] = []
var previous: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTH + 8.0, 5.0, 18.0)
	shape.shape = box
	shape.position.y = 1.5
	add_child(shape)
	RoadsideKit.part(self, Vector3(LENGTH, 0.06, DEPTH), Vector3(0, 0.03, 0), Color("73552f"))
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.065
	spike_mesh.height = 0.16
	spike_mesh.radial_segments = 4
	spike_mesh.material = RoadsideKit.material(Color("abb3ae"))
	for x in range(12):
		for z in [-0.12, 0.12]:
			var spike := MeshInstance3D.new()
			spike.mesh = spike_mesh
			spike.position = Vector3(-1.1 + x * 0.2, 0.12, z)
			add_child(spike)
	for x in [-1.05, 0.0, 1.05]:
		RoadsideKit.part(self, Vector3(0.12, 0.012, DEPTH), Vector3(x, 0.067, 0), Color("dab454"))
	body_entered.connect(_entered)
	body_exited.connect(_exited)
	set_physics_process(false)

func _entered(body: Node3D) -> void:
	if body is Chassis and not nearby.has(body):
		nearby.append(body)
		set_physics_process(true)

func _exited(body: Node3D) -> void:
	if body is Chassis:
		nearby.erase(body)
		previous.erase(body.get_instance_id())
		set_physics_process(not nearby.is_empty())

func crosses_spikes(from: Vector3, to: Vector3, tire_half_width: float = 0.25) -> bool:
	# Tire width counts, height remains tight so jumping/flying over is safe.
	var bounds := AABB(Vector3(-LENGTH / 2.0 - tire_half_width, -0.10, -DEPTH / 2.0 - 0.06), Vector3(LENGTH + tire_half_width * 2.0, 0.34, DEPTH + 0.12))
	var a := to_local(from)
	var b := to_local(to)
	return bounds.has_point(b) or bounds.intersects_segment(a, b) != null

func _physics_process(delta: float) -> void:
	for index in range(nearby.size() - 1, -1, -1):
		var rv: Chassis = nearby[index]
		if not is_instance_valid(rv):
			nearby.remove_at(index)
			continue
		var id := rv.get_instance_id()
		var old: Dictionary = previous.get(id, {})
		var next := {}
		for slot in range(4):
			var wheel: VehicleWheel3D = rv.installed_wheels[slot]
			if wheel == null or not wheel.is_in_contact(): continue
			var point := wheel.get_contact_point()
			var before: Vector3 = old.get(slot, point - ClimbMath.point_velocity(rv, point) * delta)
			next[slot] = point
			# Teleports must not damage tires across the whole skipped world.
			if before.distance_to(point) <= maxf(2.0, rv.linear_velocity.length() * delta * 2.0) and crosses_spikes(before, point):
				rv.puncture_wheel(slot)
		previous[id] = next
	if nearby.is_empty():
		previous.clear()
		set_physics_process(false)

static func placement(field: WorldField, band: int) -> Dictionary:
	# Separate RNG stream: no changes to loot, terrain, enemies or POI draws.
	# Keep the initial 450 m safe; repeat visits regenerate the same hazard.
	if band < 3: return {}
	var rng := field.rng_for(band, "tire_spike_strip")
	if rng.randf() >= SPAWN_CHANCE: return {}
	var distance := band * field.profile.chunk_length + rng.randf_range(25.0, 125.0)
	for site in field.stops_in_band(band):
		if absf(-site.road.origin.z - distance) < 45.0: return {}
	var frame := field.road_frame(distance)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# Mostly on the shoulder, with 1.8 m extending into the road edge.
	var center := frame.origin + frame.basis.x * side * (field.road_width(distance) / 2.0 - 0.6)
	center.y = field.height_at(center.x, center.z) + 0.04
	var along := frame.basis.z
	var ahead := center - along
	var behind := center + along
	along.y = (field.height_at(behind.x, behind.z) - field.height_at(ahead.x, ahead.z)) / 2.0
	along = along.normalized()
	var right := frame.basis.x
	var up := along.cross(right).normalized()
	return {"transform": Transform3D(Basis(right, up, along), center)}

static func build(chunk: Node3D, field: WorldField, band: int) -> void:
	var data := placement(field, band)
	if data.is_empty(): return
	var strip := TireSpikeStrip.new()
	strip.name = "TireSpikeStrip"
	chunk.add_child(strip)
	strip.global_transform = data.transform
