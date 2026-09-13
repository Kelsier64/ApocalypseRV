extends Node3D

const CHUNK_SCENE = preload("res://world/chunk_generator.gd")
const CHUNKS_AHEAD = 3 # How many chunks to generate fully ahead of the player
const CHUNKS_BEHIND = 2 # How many chunks to keep behind before deleting
# Streaming decisions compare raw Z coordinates, which assumes the road keeps
# heading roughly along -Z. Clamp the accumulated heading so the random turn
# walk can never rotate the road far enough to break that assumption.
const MAX_ROAD_HEADING = 0.6 # Radians (~34 degrees) of total drift allowed

var active_chunks: Array = [] # Stores { "node": Node3D, "start_z": float, "end_z": float }
var next_transform: Transform3D = Transform3D.IDENTITY
var next_turn_angle: float = 0.0
var current_road_heading: float = 0.0
var terrain_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var poi_spawner: POISpawner

@export var player: Node3D
@export var world_seed: int = -1 # -1 = random world each run

func _ready():
	if player == null:
		player = get_tree().get_first_node_in_group(Groups.PLAYER)
		if player == null:
			push_warning("WorldGenerator: no player assigned or found in 'player' group; chunk streaming disabled.")
	_init_noise()
	poi_spawner = POISpawner.new()
	print("World Generator Started. Spawning initial chunks...")
	var chunk_length = 150.0

	# Generate behind chunks (straight)
	for i in range(CHUNKS_BEHIND, 0, -1):
		var chunk = Node3D.new()
		chunk.set_script(CHUNK_SCENE)
		add_child(chunk)
		# Starting far away in +Z and generating -Z towards origin
		var start_transform = Transform3D(Basis(), Vector3(0, 0, i * chunk_length))
		chunk.generate_chunk(start_transform, 0.0, terrain_noise, detail_noise, poi_spawner)
		active_chunks.append({
			"node": chunk,
			"start_z": start_transform.origin.z,
			"end_z": start_transform.origin.z - chunk_length
		})
	
	# Make the very first chunk perfectly straight so we have a good starting point
	next_transform = Transform3D.IDENTITY
	next_turn_angle = 0.0
	current_road_heading = 0.0

	# Generate current (where player is) and ahead
	for i in range(CHUNKS_AHEAD + 1):
		_spawn_next_chunk()

func _process(_delta):
	if not player:
		return
		
	if active_chunks.is_empty():
		return

	var player_z = player.global_position.z

	# Check if we need to spawn a new chunk ahead
	# active_chunks[-1] is the furthest chunk
	var furthest_chunk = active_chunks[-1]
	# If the distance from player to the end of the furthest chunk is less than our desired buffer...
	if (furthest_chunk["end_z"] - player_z) > -(CHUNKS_AHEAD * 150.0): 
		_spawn_next_chunk()
		
	# Check if we need to delete old chunks behind
	if active_chunks.size() > 0:
		var oldest_chunk = active_chunks[0]
		# If the end of the oldest chunk is way behind the player
		if (oldest_chunk["end_z"] - player_z) > (CHUNKS_BEHIND * 150.0):
			oldest_chunk["node"].queue_free()
			active_chunks.pop_front()
			print("Despawned old chunk. Active chunks: ", active_chunks.size())

	_despawn_entities_behind(player_z)

## Entities live in the shared WorldEntities container instead of their spawn
## chunk (see core/world_entities.gd), so apply the chunk despawn distance rule
## to them here: anything this far behind has lost its terrain already.
func _despawn_entities_behind(player_z: float) -> void:
	var despawn_distance := CHUNKS_BEHIND * 150.0
	for node in get_tree().get_nodes_in_group(Groups.MONSTERS):
		if node is Node3D and node.global_position.z - player_z > despawn_distance:
			node.queue_free()
	var container := WorldEntities.get_container(self)
	if container == null or not container.is_inside_tree():
		return
	for child in container.get_children():
		if child is Node3D and child.global_position.z - player_z > despawn_distance:
			child.queue_free()

func _spawn_next_chunk():
	var chunk = Node3D.new()
	chunk.set_script(CHUNK_SCENE)
	add_child(chunk)
	
	# The chunk generates itself and returns the transform for the NEXT chunk's start
	var end_transform = chunk.generate_chunk(next_transform, next_turn_angle, terrain_noise, detail_noise, poi_spawner)
	
	# Determine rough Z boundaries for streaming logic
	var start_z = next_transform.origin.z
	var end_z = end_transform.origin.z
	
	active_chunks.append({
		"node": chunk,
		"start_z": start_z,
		"end_z": end_z
	})
	
	# Setup for the next iteration
	next_transform = end_transform
	# Determine the next turn angle. Max angle is roughly +/- 15 degrees to keep things drivable
	# but we use noise/rand to make it snake. Clamped so the cumulative heading stays
	# within MAX_ROAD_HEADING of straight -Z (see constant above).
	next_turn_angle = clampf(
		randf_range(-0.25, 0.25),
		-MAX_ROAD_HEADING - current_road_heading,
		MAX_ROAD_HEADING - current_road_heading
	)
	current_road_heading += next_turn_angle
	
	print("Spawned chunk. Start Z: ", start_z, " End Z: ", end_z)

func _init_noise() -> void:
	var seed_base := world_seed
	if seed_base < 0:
		seed_base = randi()

	terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = seed_base
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.0005
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 5
	terrain_noise.fractal_lacunarity = 2.0
	terrain_noise.fractal_gain = 0.5

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = seed_base + 1
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.05
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_gain = 0.6
