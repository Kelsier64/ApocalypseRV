extends RefCounted
class_name RainCover
## Toroidal world-space height cache. Query cost does not depend on rain density.
const GRID := 64
const EMPTY_HEIGHT := -100000.0
var cell_size: float
var cursor := 0
var origin := Vector2i.ZERO
var image: Image
var texture: ImageTexture
var samples := 0

func _init(size := 0.75) -> void:
	cell_size = size
	image = Image.create(GRID, GRID, false, Image.FORMAT_RGBAF)
	image.fill(Color(EMPTY_HEIGHT, 0, 0, 0))
	texture = ImageTexture.create_from_image(image)

func reset() -> void:
	image.fill(Color(EMPTY_HEIGHT, 0, 0, 0))
	cursor = 0

func update(center: Vector3, budget: int, query: Callable) -> void:
	var cell := Vector2i(floori(center.x / cell_size), floori(center.z / cell_size))
	origin = cell - Vector2i(GRID / 2, GRID / 2)
	samples = 0
	for i in range(budget):
		# Advance texture slots, not camera-relative rows. Otherwise vehicle motion
		# can alias the scan stride and repeatedly leave the same rows unvisited.
		var slot := Vector2i(cursor % GRID, cursor / GRID)
		var at := origin + Vector2i(posmod(slot.x - origin.x, GRID), posmod(slot.y - origin.y, GRID))
		cursor = (cursor + 1) % (GRID * GRID)
		var point := Vector3((at.x + 0.5) * cell_size, center.y, (at.y + 0.5) * cell_size)
		var hit: Dictionary = query.call(point + Vector3.UP * 128, point + Vector3.DOWN * 128)
		var height: float = hit.position.y if not hit.is_empty() else EMPTY_HEIGHT
		image.set_pixel(posmod(at.x, GRID), posmod(at.y, GRID), Color(height, at.x, at.y, 1))
		samples += 1
	texture.update(image)

func height_at(point: Vector3) -> float:
	var cell := Vector2i(floori(point.x / cell_size), floori(point.z / cell_size))
	var sample := image.get_pixel(posmod(cell.x, GRID), posmod(cell.y, GRID))
	if sample.a < 0.5 or absf(sample.g - cell.x) > 0.1 or absf(sample.b - cell.y) > 0.1: return INF
	return sample.r
