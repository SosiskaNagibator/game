@tool
extends Node3D
## Настройка солнечного света для сцены. Держим ориентацию в скрипте,
## чтобы солнце было одинаковым и в редакторе, и в игре.

@export var sun_rotation_degrees := Vector3(-40.0, -55.0, 0.0)
@export var sun_color := Color(1.0, 0.94, 0.82)
@export var sun_energy: float = 1.18
@export var ambient_energy: float = 1.0
@export var saturation: float = 1.02

## Точка появления игрока — на лесовозном отвороте перед воротами базы,
## лицом к доку. Держим здесь, чтобы старт всегда был у скрытой базы.
const PLAYER_SPAWN := Vector2(-213.5, -126.0)
const PLAYER_YAW := 0.47
const VEHICLE_SPAWN := Vector2(-207.0, -116.5)
const VEHICLE_YAW := 0.47


func _ready() -> void:
	_place_start()
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = sun_rotation_degrees
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 190.0
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.4

	# Мягче и натуральнее свет: без пересвета, из-за которого трава
	# выглядела неоново-зелёной, а земля — бледной заливкой.
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 0.98
		env.ambient_light_energy = ambient_energy
		env.adjustment_enabled = true
		env.adjustment_saturation = saturation
		env.adjustment_contrast = 1.05


func _place_start() -> void:
	var player := get_node_or_null("Player") as Node3D
	if player != null:
		var py: float = RuralHeight.terrain_height(PLAYER_SPAWN.x, PLAYER_SPAWN.y)
		player.position = Vector3(PLAYER_SPAWN.x, py + 0.15, PLAYER_SPAWN.y)
		player.rotation = Vector3(0.0, PLAYER_YAW, 0.0)

	var vehicle := get_node_or_null("BaseVehicle") as Node3D
	if vehicle != null:
		var vy: float = RuralHeight.terrain_height(VEHICLE_SPAWN.x, VEHICLE_SPAWN.y)
		vehicle.position = Vector3(VEHICLE_SPAWN.x, vy + 0.45, VEHICLE_SPAWN.y)
		vehicle.rotation = Vector3(0.0, VEHICLE_YAW, 0.0)

