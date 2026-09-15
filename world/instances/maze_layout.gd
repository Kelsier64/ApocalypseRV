extends RefCounted
class_name MazeLayout
## Pure, deterministic topology. 27m spacing fits authored 9m and 18m rooms.
const SPACING := 27.0
const WIDTH := 10
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func generate(seed_value: int, count: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if count == 0:
		count = rng.randi_range(50, 100)
	count = clampi(count, 50, 100)
	var rooms: Array[Dictionary] = []
	var by_cell: Dictionary = {}
	for i in range(count):
		var cell := Vector2i(i % WIDTH, -int(i / WIDTH))
		by_cell[cell] = i
		rooms.append({"cell": cell, "large": i > 0 and rng.randf() < 0.3, "doors": []})
	var edges: Array[Vector2i] = []
	var stack: Array[int] = [0]
	var visited := {0: true}
	while not stack.is_empty():
		var a := stack[-1]
		var choices: Array[int] = []
		for dir in DIRECTIONS:
			var neighbor: int = by_cell.get(rooms[a].cell + dir, -1)
			if neighbor >= 0 and not visited.has(neighbor):
				choices.append(neighbor)
		if choices.is_empty():
			stack.pop_back()
			continue
		var b := choices[rng.randi_range(0, choices.size() - 1)]
		visited[b] = true
		stack.append(b)
		edges.append(Vector2i(mini(a, b), maxi(a, b)))
	# Add a few loops; the spanning tree already guarantees all rooms reachable.
	var extras: Array[Vector2i] = []
	for a in range(count):
		for dir in [Vector2i.RIGHT, Vector2i.UP]:
			var b: int = by_cell.get(rooms[a].cell + dir, -1)
			var edge := Vector2i(mini(a, b), maxi(a, b))
			if b >= 0 and not edges.has(edge):
				extras.append(edge)
	for i in range(mini(extras.size(), maxi(3, count / 12))):
		var index := rng.randi_range(0, extras.size() - 1)
		edges.append(extras.pop_at(index))
	for edge in edges:
		var delta: Vector2i = rooms[edge.y].cell - rooms[edge.x].cell
		rooms[edge.x].doors.append(DIRECTIONS.find(delta))
		rooms[edge.y].doors.append(DIRECTIONS.find(-delta))
	return {"seed": seed_value, "rooms": rooms, "edges": edges}
