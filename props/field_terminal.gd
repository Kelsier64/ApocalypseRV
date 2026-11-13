extends Item
class_name FieldTerminal
## The physical display reads the equipped player. Item state stays generic.
const SCENE := "res://props/field_terminal.tscn"

@onready var display: SubViewport = $Display
@onready var screen: Control = $Display/Screen

func _ready() -> void:
	super._ready()
	var material := StandardMaterial3D.new()
	material.albedo_texture = display.get_texture()
	material.roughness = 0.38
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission = Color.WHITE
	material.emission_texture = material.albedo_texture
	material.emission_energy_multiplier = 0.8
	$Visuals/Glass.material_override = material
	set_process(presentation_only and not is_being_placed)

func _process(_delta: float) -> void:
	var holder := _holder()
	if holder == null or not enabled or condition <= 0.0 or not is_visible_in_tree():
		screen.show_reading("", "", PackedInt32Array(), PackedFloat32Array())
		return

	var clock := _owning_clock(holder)
	var day := ""
	var time := ""
	if clock != null:
		var minutes := floori(fposmod(clock.elapsed_seconds, WorldClock.DAY_SECONDS) / 60.0)
		day = "DAY %d" % clock.day_number()
		time = "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]

	var health: float = holder.current_player_health
	var stamina: float = holder.current_stamina
	var hunger: float = holder.survival.hunger
	var san: float = holder.survival.san
	screen.show_reading(day, time, PackedInt32Array([
		ceili(health), ceili(stamina), ceili(hunger), floori(san) if san < 0.0 else ceili(san),
	]), PackedFloat32Array([
		health / holder.max_player_health, stamina / holder.MAX_STAMINA,
		hunger / PlayerSurvival.MAX_HUNGER, san / PlayerSurvival.MAX_SAN,
	]))

func _holder() -> CharacterBody3D:
	var node := get_parent()
	while node != null:
		if node is CharacterBody3D and "held_item_node" in node:
			return node if node.held_item_node == self and not node.is_player_dead else null
		node = node.get_parent()
	return null

func _owning_clock(holder: Node3D) -> WorldClock:
	# Interior viewports sit under their outdoor world's instance manager.
	# Walk through them to keep displaying that run's clock indoors.
	var node: Node = holder
	while node != null:
		var clock := node.get_node_or_null("WorldClock") as WorldClock
		if clock != null: return clock
		node = node.get_parent()
	return null
