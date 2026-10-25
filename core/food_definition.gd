extends ItemDefinition
class_name FoodDefinition
## Nutrition belongs to the trusted item resource, never to saved item data.

@export_range(1.0, 100.0) var nutrition: float = 20.0
@export_range(0.1, 10.0) var eat_seconds: float = 2.0
