extends Node3D

const CHUNK_SCENE = preload("res://world/chunk_generator.gd")
const CHUNKS_AHEAD = 3 # How many chunks to generate fully ahead of the player
const CHUNKS_BEHIND = 2 # How many chunks to keep behind before deleting

var active_chunks: Array = [] # Stores { "node": Node3D, "start_z": float, "end_z": float }
var next_transform: Transform3D = Transform3D.IDENTITY
var next_turn_angle: float = 0.0
var terrain_noise: FastNoiseLite
var detail_noise: FastNoiseLite

@export var player: Node3D

func _ready():
	_init_noise()
	print("World Generator Started. Spawning initial chunks...")
	var chunk_length = 150.0

	# Generate behind chunks (straight)
	for i in range(CHUNKS_BEHIND, 0, -1):
		var chunk = Node3D.new()
		chunk.set_script(CHUNK_SCENE)
		add_child(chunk)
		# Starting far away in +Z and generating -Z towards origin
		var start_transform = Transform3D(Basis(), Vector3(0, 0, i * chunk_length))
		chunk.generate_chunk(start_transform, 0.0, terrain_noise, detail_noise)
		active_chunks.append({
			"node": chunk,
			"start_z": start_transform.origin.z,
			"end_z": start_transform.origin.z - chunk_length
		})
	
	# Make the very first chunk perfectly straight so we have a good starting point
	next_transform = Transform3D.IDENTITY
	next_turn_angle = 0.0
	
	# Generate current (where player is) and ahead
	for i in range(CHUNKS_AHEAD + 1):
		_spawn_next_chunk()

func _process(_delta):
	if not player:
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

func _spawn_next_chunk():
	var chunk = Node3D.new()
	chunk.set_script(CHUNK_SCENE)
	add_child(chunk)
	
	# The chunk generates itself and returns the transform for the NEXT chunk's start
	var end_transform = chunk.generate_chunk(next_transform, next_turn_angle, terrain_noise, detail_noise)
	
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
	# but we use noise/rand to make it snake
	next_turn_angle = randf_range(-0.25, 0.25)
	
	print("Spawned chunk. Start Z: ", start_z, " End Z: ", end_z)

func _init_noise() -> void:
	terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = 1337
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.0005
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 5
	terrain_noise.fractal_lacunarity = 2.0
	terrain_noise.fractal_gain = 0.5

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 7331
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.05
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_gain = 0.6
