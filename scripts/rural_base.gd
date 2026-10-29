@tool
extends Node3D
## Настройка солнечного света для сцены. Держим ориентацию в скрипте,
## чтобы солнце было одинаковым и в редакторе, и в игре.

@export var sun_rotation_degrees := Vector3(-40.0, -55.0, 0.0)
@export var sun_color := Color(1.0, 0.94, 0.82)
@export var sun_energy: float = 1.18
@export var ambient_energy: float = 1.0
@export var saturation: float = 1.02

func _ready() -> void:
	_place_start()
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = sun_rotation_degrees
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.shadow_enabled = true
		# Тени только вокруг игрока: 110 м вместо 190 м и 2 PSSM-каскада.
		WorldPerformance.configure_sun(sun)

	# Мягче и натуральнее свет: без пересвета, из-за которого трава
	# выглядела неоново-зелёной, а земля — бледной заливкой.
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		WorldPerformance.configure_environment(env)
		env.tonemap_exposure = 0.98
		env.ambient_light_energy = ambient_energy
		env.adjustment_enabled = true
		env.adjustment_saturation = saturation
		env.adjustment_contrast = 1.05

	# Сцена уже сгенерировала поселение, ферму и декор: проходим по ним и
	# убираем тени у мелочи, включаем distance fade у фонарей и т.д.
	if not Engine.is_editor_hint():
		WorldPerformance.optimize_world(self)

func _place_start() -> void:
	var player := get_node_or_null("Player") as Node3D
	if player != null:
		# Берем X и Z из редактора, а высоту Y считаем по рельефу
		var py: float = RuralHeight.terrain_height(player.position.x, player.position.z)
		player.position.y = py + 0.15

	var vehicle := get_node_or_null("BaseVehicle") as Node3D
	if vehicle != null:
		# Берем X и Z из редактора, а высоту Y считаем по рельефу
		var vy: float = RuralHeight.terrain_height(vehicle.position.x, vehicle.position.z)
		vehicle.position.y = vy + 0.45
		# Строку с vehicle.rotation мы убрали, чтобы машина сохраняла ваш поворот
