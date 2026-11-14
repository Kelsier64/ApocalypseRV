extends RefCounted
class_name TerrainGrid
## One band's sampled surface on its render grid. Detail placement reads height,
## slope and exclusions from here instead of re-querying the analytic surface:
## it is orders of magnitude cheaper, and props rest on the triangles the player
## actually sees rather than a few centimetres above or below them.
const RESERVED := 1
## Reserved by something other than the carriageway margin (court, pad, water).
const OCCUPIED := 2
const WET := 4
var x0: float
var z0: float
var step_x: float
var step_z: float
var columns: int
var rows: int
var heights := PackedFloat32Array()
var edges := PackedFloat32Array()
var banks := PackedFloat32Array()
var flags := PackedByteArray()
# Result of the last probe(); members avoid allocating a Dictionary per query.
var height := 0.0
var normal := Vector3.UP
var edge := 0.0
var bank := 0.0
var reserved := false
var occupied := false
var wet := false

## `samples[j][i]` is WorldField.surface() at x = first_x + i * step_x, z = first_z - j * step_z.
static func from_samples(samples: Array, first_x: float, first_z: float, x_step: float, z_step: float) -> TerrainGrid:
	var grid := TerrainGrid.new()
	grid.x0 = first_x
	grid.z0 = first_z
	grid.step_x = x_step
	grid.step_z = z_step
	grid.rows = samples.size()
	grid.columns = samples[0].size()
	var total := grid.rows * grid.columns
	grid.heights.resize(total)
	grid.edges.resize(total)
	grid.banks.resize(total)
	grid.flags.resize(total)
	for j in range(grid.rows):
		var row: Array = samples[j]
		for i in range(grid.columns):
			var sample: Dictionary = row[i]
			var index := j * grid.columns + i
			grid.heights[index] = sample.height
			grid.edges[index] = float(sample.road.distance) - float(sample.road.width) * 0.5
			grid.banks[index] = sample.river_bank
			var water := is_finite(float(sample.water_height))
			grid.flags[index] = (RESERVED if sample.reserved else 0) | (OCCUPIED if sample.occupied or water else 0) | (WET if water else 0)
	return grid

## Samples a band directly, for callers that never built its ground mesh.
static func for_band(chunk: ChunkGenerator, gradual: bool) -> TerrainGrid:
	var field := chunk.field
	var step := field.profile.terrain_step
	var nx := roundi(field.profile.terrain_half_width * 2.0 / step)
	var x_step := field.profile.terrain_half_width * 2.0 / nx
	var nz := roundi(field.profile.chunk_length / step)
	var north := -chunk.band * field.profile.chunk_length
	var samples: Array = []
	for j in range(-1, nz + 2):
		var row: Array = []
		for i in range(-1, nx + 2):
			row.append(field.surface(-field.profile.terrain_half_width + i * x_step, north - j * step))
			if gradual and i % 32 == 0 and chunk.slice_exhausted(): await chunk._pause()
		samples.append(row)
	return from_samples(samples, -field.profile.terrain_half_width - x_step, north + step, x_step, step)

## Fills the result members for (x, z); false outside the grid.
func probe(x: float, z: float) -> bool:
	var u := (x - x0) / step_x
	var v := (z0 - z) / step_z
	var i := floori(u)
	var j := floori(v)
	if i < 0 or j < 0 or i >= columns - 1 or j >= rows - 1: return false
	u -= i
	v -= j
	var a := j * columns + i
	var b := a + columns
	var h00 := heights[a]
	var h10 := heights[a + 1]
	var h01 := heights[b]
	var h11 := heights[b + 1]
	# Same diagonal as the ground mesh: (i+1, j) to (i, j+1).
	var along_x: float
	var along_z: float
	if u + v <= 1.0:
		along_x = h10 - h00
		along_z = h01 - h00
		height = h00 + u * along_x + v * along_z
	else:
		along_x = h11 - h01
		along_z = h11 - h10
		height = h11 - (1.0 - u) * along_x - (1.0 - v) * along_z
	normal = Vector3(-along_x / step_x, 1.0, along_z / step_z).normalized()
	edge = lerpf(lerpf(edges[a], edges[a + 1], u), lerpf(edges[b], edges[b + 1], u), v)
	bank = lerpf(lerpf(banks[a], banks[a + 1], u), lerpf(banks[b], banks[b + 1], u), v)
	# A flag on any corner claims the whole cell: conservative by at most one step.
	var combined := flags[a] | flags[a + 1] | flags[b] | flags[b + 1]
	reserved = combined & RESERVED != 0
	occupied = combined & OCCUPIED != 0
	wet = combined & WET != 0
	return true
