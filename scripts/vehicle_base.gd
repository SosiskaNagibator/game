class_name BaseVehicle
extends VehicleBody3D
## Базовый класс машины (Godot 4).
##
## Наследники (gazelle.gd, heavy_truck.gd) могут просто расширять этот класс:
##     extends BaseVehicle
## и переопределять экспортированные параметры в Инспекторе конкретной сцены.
##
## Управление:
##   accelerate  — газ (W / стрелка вверх)
##   brake       — тормоз / задний ход (S / стрелка вниз)
##   steer_left  — руль влево (A / стрелка влево)
##   steer_right — руль вправо (D / стрелка вправо)
##   handbrake   — ручник (Space)
##   radio_toggle — радио вкл/выкл (R)

## Единственная радиостанция в машине.
const RADIO_TRACK: AudioStream = preload(
	"res://assets/audio/radio/radio_music_1.ogg"
)

@export_group("Двигатель")
## Максимальная суммарная сила тяги на ведущих колёсах, Н.
## Для лёгкой Газели ~1500-3000, для тяжёлого грузовика ~8000-15000.
@export_range(0.0, 30000.0, 50.0) var max_engine_force: float = 1500.0
## Доля силы тяги заднего хода от max_engine_force.
@export_range(0.1, 1.0, 0.05) var reverse_force_multiplier: float = 0.6

@export_group("Руль")
## Максимальный угол поворота колёс в радианах (0.65 рад ≈ 37.2°).
@export_range(0.1, 1.2, 0.01, "radians_as_degrees") var max_steer_angle: float = 0.65
## Скорость сглаживания руля (чем больше — тем резче реакция).
@export_range(0.5, 20.0, 0.5) var steer_smoothing: float = 8.0
## Доля максимального угла руля на высокой скорости (защита от переворота).
@export_range(0.1, 1.0, 0.05) var high_speed_steer_factor: float = 0.75
## Скорость (км/ч), при которой достигается high_speed_steer_factor.
@export_range(30.0, 200.0, 5.0) var high_speed_steer_kmh: float = 120.0
## Предельное боковое ускорение, м/с². Ограничивает угол руля на скорости,
## чтобы машина не переворачивалась от резкого поворота. 0 — отключить.
## Высокий порог (25 м/с²) нужен, чтобы ограничение не «душило» руль заранее.
@export_range(0.0, 40.0, 0.5) var max_lateral_accel: float = 25.0

@export_group("Масса и центр масс")
## Высота центра масс в локальных координатах машины, м.
## Земля в этой сцене проходит примерно на y = -0.05, поэтому -0.5 — это COM
## ПОД дорогой (физически невозможно; именно это давало «плавучесть»).
## Порог опрокидывания: h_над_дорогой <= (полуколея * g) / max_lateral_accel
## = (0.86 * 9.81) / 25 = 0.337 м. При земле на -0.05 это local y <= 0.287.
## 0.20 оставляет запас и проверено: полный руль на ~64 км/ч, крен ~2.8°, без переворота.
@export_range(-1.0, 2.0, 0.01) var center_of_mass_height: float = 0.20

@export_group("Устойчивость")
## Пользовательский анти-крен. Выключите, чтобы проверить нативную физику
## подвески без вмешательства скрипта.
@export var anti_roll_enabled: bool = false
## Сила стабилизации крена кузова, Н·м на радиан.
## Снижена: анти-крен не должен спорить с пружинами и раскачивать кузов.
@export_range(0.0, 40000.0, 100.0) var anti_roll_strength: float = 16000.0
## Демпфирование крена, Н·м на рад/с.
## Выше силы — стабилизатор гасит раскачку, а не создаёт её.
@export_range(0.0, 30000.0, 100.0) var anti_roll_damping: float = 18000.0
## Максимальный стабилизирующий момент, Н·м.
@export_range(0.0, 12000.0, 100.0) var max_anti_roll_torque: float = 6000.0
## Во сколько раз ослабляется анти-крен на ручнике (0 — полностью выключен).
## Позволяет кузову свободно крениться и заходить в занос.
@export_range(0.0, 1.0, 0.05) var handbrake_anti_roll_factor: float = 0.15
## Скорость (км/ч), с которой начинает работать стабилизация крена.
@export_range(0.0, 80.0, 1.0) var stability_start_kmh: float = 30.0
## Скорость (км/ч), на которой стабилизация выходит на полную силу.
@export_range(30.0, 180.0, 5.0) var stability_full_kmh: float = 95.0
## Прижимная сила: Н на (м/с)². Помогает держать колёса на дороге.
@export_range(0.0, 8.0, 0.1) var downforce_coefficient: float = 1.6

@export_group("Тормоза")
## Сила торможения рабочей тормозной системы на каждое колесо, Н.
@export_range(0.0, 300.0, 1.0) var max_brake_force: float = 30.0
## Сила торможения ручника на задние колёса, Н.
## Высокая — задние колёса должны блокироваться и скользить, а не плавно тормозить.
@export_range(0.0, 400.0, 1.0) var handbrake_force: float = 110.0
## Дополнительное замедление рабочей тормозной системы, м/с².
## Делает тормозной путь предсказуемым независимо от массы машины.
@export_range(0.0, 15.0, 0.1) var brake_deceleration: float = 3.5
## Замедление ручником, м/с².
## Небольшое: ручник нужен для заноса, а не для остановки машины.
@export_range(0.0, 10.0, 0.1) var handbrake_deceleration: float = 0.3
## Замедление двигателем при отпущенном газе, м/с².
@export_range(0.0, 5.0, 0.1) var engine_braking_deceleration: float = 0.9

@export_group("Аэродинамика")
## Сопротивление воздуха: Н на (м/с)². Вместе с двигателем задаёт максималку.
@export_range(0.0, 5.0, 0.05) var drag_coefficient: float = 1.1
## Сопротивление качению: Н на (м/с). Работает только когда колёса на земле.
@export_range(0.0, 200.0, 1.0) var rolling_resistance: float = 26.0
## Скорость, после которой двигатель перестаёт тянуть, км/ч.
@export_range(40.0, 250.0, 5.0) var max_speed_kmh: float = 125.0

@export_group("Сцепление и помощники")
## Доля сцепления задних колёс на ручнике (0.1–0.2 — глубокий управляемый занос).
@export_range(0.0, 1.0, 0.05) var handbrake_grip_factor: float = 0.15
## Антипробуксовка: насколько снижать тягу при пробуксовке (0 — выключено).
@export_range(0.0, 0.9, 0.05) var traction_control: float = 0.35

@export_group("Свет")
## Автоматически включать фары ночью (через DayNightCycle.is_night()).
@export var headlights_auto: bool = true
## Держать фары включёнными всегда.
@export var headlights_always_on: bool = false
## Яркость фар.
@export_range(0.5, 12.0, 0.1) var headlight_energy: float = 3.2

@export_group("Радио")
## Громкость радио, дБ.
@export_range(-40.0, 6.0, 0.5) var radio_volume_db: float = -8.0
## Расстояние, на котором радио ещё слышно, м.
@export_range(1.0, 100.0, 1.0) var radio_max_distance: float = 45.0

# Все колёса машины (заполняется в _ready).
var _all_wheels: Array[VehicleWheel3D] = []
# Колёса, у которых в Инспекторе включён "Use as Steering".
var _steering_wheels: Array[VehicleWheel3D] = []
# Колёса, у которых в Инспекторе включён "Use as Traction" (ведущие).
var _traction_wheels: Array[VehicleWheel3D] = []
# Задние колёса (определяются по локальной оси +Z).
var _rear_wheels: Array[VehicleWheel3D] = []
# Колёсная база, м (для ограничения угла руля на скорости).
var _wheelbase: float = 3.4

# Текущий (сглаженный) угол руля.
var _current_steer: float = 0.0
# Половина колеи передних колёс, м (для руля Аккермана).
var _half_track: float = 0.86
# Фары машины (создаются в _ready).
var _headlights: Array[SpotLight3D] = []
# Базовое сцепление каждого колеса, чтобы возвращать его после ручника.
var _base_friction: Dictionary = {}
var _headlights_on: bool = false
# Масса пустой машины: по ней считается предельная сила тормозов.
var _empty_mass: float = 0.0
# Автомагнитола (создаётся в _ready).
var _radio: AudioStreamPlayer3D = null
var _radio_on: bool = false
# Кэш DayNightCycle: не ищем ноду в группе каждый физический кадр.
var _day_night: Node = null
var _headlight_check_timer: float = 0.0
# Пыль/камешки выключены, пока машина пустая.
var _wheel_fx_idle: bool = false

## Игрок, который сейчас управляет машиной. null — машина пустая.
var driver: Node = null

# Камеры машины: вид от первого лица и орбитальная камера от третьего лица.
var _first_person_camera: Camera3D = null
var _third_person_camera: Camera3D = null
var _third_person_active: bool = false

# Данные систем частиц и вращения колёс: wheel, dust, chips, mesh.
var _wheel_effects: Array[Dictionary] = []


func _ready() -> void:
	# Центр масс задаём в локальных координатах кузова. ВАЖНО: у этой машины
	# земля проходит примерно на y = -0.05, поэтому отрицательная высота
	# (-0.5) находится под дорогой и ломает физику крена/тангажа.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, center_of_mass_height, 0.0)
	# Запоминаем снаряжённую массу: груз будет добавляться к ней.
	_empty_mass = mass
	# Машина не должна "засыпать" на стоянке, иначе первый газ может не сработать.
	can_sleep = false
	add_to_group("vehicles")
	_collect_wheels()
	_hide_body_wheels()

	_first_person_camera = get_vehicle_camera()
	_third_person_camera = get_node_or_null("ThirdPersonCamera") as Camera3D
	_setup_wheel_effects()
	_setup_headlights()
	_setup_radio()
	_day_night = get_tree().get_first_node_in_group("day_night")


## Скрываем колёса, встроенные в модель кузова: ими управляют VehicleWheel3D.
func _hide_body_wheels() -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return

	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel := body.get_node_or_null(wheel_name)
		if wheel is Node3D:
			wheel.visible = false


## V — переключение вида, R — радио.
func _unhandled_input(event: InputEvent) -> void:
	if not is_occupied():
		return
	if InputMap.has_action("camera_toggle") and event.is_action_pressed("camera_toggle"):
		_set_third_person_view(not _third_person_active)
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("radio_toggle") and event.is_action_pressed("radio_toggle"):
		toggle_radio()
		get_viewport().set_input_as_handled()


## Включить/выключить вид от третьего лица.
func _set_third_person_view(enabled: bool) -> void:
	if _first_person_camera == null:
		_first_person_camera = get_vehicle_camera()
	if _third_person_camera == null:
		_third_person_camera = get_node_or_null("ThirdPersonCamera") as Camera3D

	_third_person_active = enabled and _third_person_camera != null

	if not is_occupied():
		return

	if _first_person_camera != null:
		_first_person_camera.current = not _third_person_active
	if _third_person_camera != null:
		_third_person_camera.current = _third_person_active
		if _third_person_active and _third_person_camera.has_method("reset_view"):
			_third_person_camera.reset_view()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Собираем колёса один раз при старте и распределяем их по спискам.
func _collect_wheels() -> void:
	for child in get_children():
		if child is not VehicleWheel3D:
			continue

		var wheel: VehicleWheel3D = child
		_all_wheels.append(wheel)
		_base_friction[wheel] = wheel.wheel_friction_slip

		if wheel.use_as_steering:
			_steering_wheels.append(wheel)
		if wheel.use_as_traction:
			_traction_wheels.append(wheel)
		# В Godot перед машины — это -Z, значит зад — это +Z.
		if wheel.position.z > 0.0:
			_rear_wheels.append(wheel)

	if _steering_wheels.size() >= 2:
		_half_track = absf(
			_steering_wheels[0].position.x - _steering_wheels[1].position.x
		) * 0.5

	if _steering_wheels.is_empty():
		push_warning("BaseVehicle: ни одному колесу не включён 'Use as Steering'.")
	if _traction_wheels.is_empty():
		push_warning("BaseVehicle: ни одному колесу не включён 'Use as Traction'.")

	if not _steering_wheels.is_empty() and not _rear_wheels.is_empty():
		_wheelbase = absf(_rear_wheels[0].position.z - _steering_wheels[0].position.z)


# --- Эффекты колёс --------------------------------------------------------


## Создаём для каждого колеса пыль и мелкие камешки, летящие из-под шины.
func _setup_wheel_effects() -> void:
	if _all_wheels.is_empty():
		return

	var dust_mesh: Mesh = _make_dust_mesh()
	var chip_mesh: Mesh = _make_chip_mesh()
	var dust_process: ParticleProcessMaterial = _make_dust_process()
	var chip_process: ParticleProcessMaterial = _make_chip_process()

	for wheel in _all_wheels:
		var ground_local: Vector3 = wheel.position + Vector3(
			0.0, -wheel.wheel_radius + 0.04, 0.12
		)

		var dust := GPUParticles3D.new()
		dust.name = "WheelDust"
		dust.amount = 72
		dust.lifetime = 2.4
		dust.local_coords = false
		dust.emitting = true
		dust.amount_ratio = 0.0
		dust.process_material = dust_process
		dust.draw_pass_1 = dust_mesh
		dust.visibility_aabb = AABB(Vector3(-80.0, -20.0, -80.0), Vector3(160.0, 50.0, 160.0))
		dust.position = ground_local
		add_child(dust)

		var chips := GPUParticles3D.new()
		chips.name = "WheelChips"
		chips.amount = 20
		chips.lifetime = 0.75
		chips.local_coords = false
		chips.emitting = true
		chips.amount_ratio = 0.0
		chips.process_material = chip_process
		chips.draw_pass_1 = chip_mesh
		chips.visibility_aabb = AABB(Vector3(-80.0, -20.0, -80.0), Vector3(160.0, 50.0, 160.0))
		chips.position = ground_local
		add_child(chips)

		var wheel_mesh: MeshInstance3D = null
		if wheel.get_child_count() > 0:
			wheel_mesh = wheel.get_child(0) as MeshInstance3D

		_wheel_effects.append({
			"wheel": wheel,
			"dust": dust,
			"chips": chips,
			"mesh": wheel_mesh,
		})


## Обновляем интенсивность пыли и вращаем визуальные диски колёс.
func _update_wheel_effects(delta: float) -> void:
	var speed: float = linear_velocity.length()
	var speed_factor: float = clampf((speed - 1.0) / 10.0, 0.0, 1.0)
	var handbrake: bool = Input.is_action_pressed("handbrake")

	for effect in _wheel_effects:
		var wheel: VehicleWheel3D = effect["wheel"]
		var dust: GPUParticles3D = effect["dust"]
		var chips: GPUParticles3D = effect["chips"]
		var wheel_mesh: MeshInstance3D = effect["mesh"]

		if wheel_mesh != null:
			wheel_mesh.rotate_x(-wheel.get_rpm() * TAU / 60.0 * delta)

		var target_dust: float = 0.0
		var target_chips: float = 0.0

		if wheel.is_in_contact():
			var skid: float = 1.0 - clampf(wheel.get_skidinfo(), 0.0, 1.0)
			var is_rear: bool = wheel.position.z > 0.0
			var side_factor: float = 1.0 if is_rear else 0.65

			target_dust = speed_factor * side_factor * (0.45 + 0.55 * skid)
			if handbrake and is_rear:
				target_dust = maxf(target_dust, speed_factor * 0.95)

			target_chips = speed_factor * speed_factor * side_factor * (0.20 + 0.80 * skid)

		var dust_weight: float = clampf(delta * 5.0, 0.0, 1.0)
		dust.amount_ratio = lerpf(dust.amount_ratio, clampf(target_dust, 0.0, 1.0), dust_weight)
		dust.emitting = dust.amount_ratio > 0.015

		var chip_weight: float = clampf(delta * 7.0, 0.0, 1.0)
		chips.amount_ratio = lerpf(chips.amount_ratio, clampf(target_chips, 0.0, 1.0), chip_weight)
		chips.emitting = chips.amount_ratio > 0.02


## Погасить всю пыль/камешки разом (машина пустая или только что остановилась).
func _stop_wheel_effects() -> void:
	for effect in _wheel_effects:
		var dust: GPUParticles3D = effect["dust"]
		var chips: GPUParticles3D = effect["chips"]
		dust.emitting = false
		chips.emitting = false
		dust.amount_ratio = 0.0
		chips.amount_ratio = 0.0


func _make_dust_mesh() -> Mesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.92))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.42))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	quad.material = material
	return quad


func _make_chip_mesh() -> Mesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = material
	return quad


func _make_dust_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.28
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 38.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.0, 0.18, 0.0)
	process.damping_min = 0.12
	process.damping_max = 0.45
	process.scale_min = 0.9
	process.scale_max = 2.4
	process.color = Color(0.78, 0.70, 0.57, 0.75)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.12, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.62, Color(1.0, 1.0, 1.0, 0.6))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))

	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	ramp.width = 64
	process.color_ramp = ramp
	return process


func _make_chip_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.direction = Vector3(0.0, 0.5, 1.0)
	process.spread = 22.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.35
	process.scale_max = 1.0
	process.color = Color(0.44, 0.37, 0.27, 1.0)
	return process


func _physics_process(delta: float) -> void:
	if is_occupied():
		_wheel_fx_idle = false
		_update_wheel_effects(delta)
	else:
		# Пустая машина стоит: не гоняем частицы и RPM-запросы каждый тик.
		if not _wheel_fx_idle:
			_wheel_fx_idle = true
			_stop_wheel_effects()
	_update_headlights(delta)

	# Пустой машиной никто не управляет — держим её на стояночном тормозе.
	if not is_occupied():
		_apply_park_brake()
		return

	# Скорость вдоль "носа" машины (-Z), в м/с. Положительная — вперёд.
	var forward_speed: float = linear_velocity.dot(-global_transform.basis.z)

	_update_handbrake_grip(delta)
	_update_steering(delta, forward_speed)
	_update_engine_and_brakes(forward_speed)
	_update_aero()
	_update_stability(forward_speed)


# --- Свет -----------------------------------------------------------------


## Две фары в передней части кузова. Включаются автоматически ночью.
func _setup_headlights() -> void:
	for side in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.name = "HeadlightL" if side < 0.0 else "HeadlightR"
		light.position = Vector3(0.62 * side, 0.78, -2.45)
		# Чуть вниз и в стороны, как настоящие фары.
		light.rotation_degrees = Vector3(-4.0, 5.0 * side, 0.0)
		light.light_color = Color(1.0, 0.95, 0.82)
		light.light_energy = headlight_energy
		light.spot_range = 55.0
		light.spot_angle = 33.0
		light.spot_angle_attenuation = 0.9
		light.spot_attenuation = 1.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_headlights.append(light)


func _update_headlights(delta: float) -> void:
	if headlights_always_on:
		_set_headlights(true)
		return

	# Проверяем ночь 2 раза в секунду, а не каждый физический тик.
	_headlight_check_timer -= delta
	if _headlight_check_timer > 0.0:
		return
	_headlight_check_timer = 0.5

	if not headlights_auto:
		_set_headlights(false)
		return

	if _day_night == null or not is_instance_valid(_day_night):
		_day_night = get_tree().get_first_node_in_group("day_night")
	var on := false
	if _day_night != null and _day_night.has_method("is_night"):
		on = _day_night.is_night()
	_set_headlights(on)


func _set_headlights(on: bool) -> void:
	if on == _headlights_on:
		return
	_headlights_on = on
	for light in _headlights:
		light.visible = on


# --- Радио ----------------------------------------------------------------


## Автомагнитола: пространственный источник звука в салоне.
func _setup_radio() -> void:
	_radio = AudioStreamPlayer3D.new()
	_radio.name = "Radio"
	_radio.stream = RADIO_TRACK
	_radio.position = Vector3(0.0, 1.1, 0.2)
	_radio.volume_db = radio_volume_db
	_radio.unit_size = 8.0
	_radio.max_distance = radio_max_distance
	_radio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_radio)


## Включить или выключить радио (клавиша R).
func toggle_radio() -> void:
	if _radio == null:
		return
	_radio_on = not _radio_on
	if _radio_on:
		_radio.play()
	else:
		_radio.stop()


func is_radio_on() -> bool:
	return _radio_on


## Плавный поворот руля (lerp) + возврат в центр + ограничение на скорости.
func _update_steering(delta: float, forward_speed: float) -> void:
	# get_axis: "steer_right" -> -1, "steer_left" -> +1.
	var steer_input: float = Input.get_axis("steer_right", "steer_left")

	# Чем быстрее едем, тем меньше максимальный угол колёс.
	var speed_kmh: float = absf(forward_speed) * 3.6
	var speed_ratio: float = clampf(speed_kmh / high_speed_steer_kmh, 0.0, 1.0)
	var steer_limit: float = max_steer_angle * lerpf(1.0, high_speed_steer_factor, speed_ratio)

	# Физический предел: не даём рулю запрашивать большее боковое ускорение,
	# чем машина может безопасно перенести без опрокидывания.
	var speed: float = absf(forward_speed)
	if max_lateral_accel > 0.0 and speed > 1.0:
		var safe_steer: float = atan(_wheelbase * max_lateral_accel / (speed * speed))
		steer_limit = minf(steer_limit, safe_steer)

	var target_steer: float = steer_input * steer_limit

	# Сглаживание: руль плавно идёт к цели и так же плавно возвращается в центр.
	# На скорости руль реагирует мягче, чтобы резкий рывок не опрокинул машину.
	var smoothing: float = lerpf(steer_smoothing, steer_smoothing * 0.6, speed_ratio)
	var weight: float = clampf(smoothing * delta, 0.0, 1.0)
	_current_steer = lerp(_current_steer, target_steer, weight)

	# Применяем угол к рулевым колёсам (с геометрией Аккермана).
	_apply_steering_angles(_current_steer)


## Руль Аккермана: внутреннее колесо поворачивает сильнее внешнего.
## Так машина катится по дуге без бокового скольжения шин.
func _apply_steering_angles(angle: float) -> void:
	if _steering_wheels.is_empty():
		return
	if absf(angle) < 0.01 or _half_track < 0.05:
		for wheel in _steering_wheels:
			wheel.steering = angle
		return

	var turn_direction: float = signf(angle)
	var turn_radius: float = _wheelbase / tan(absf(angle))
	var angle_limit: float = max_steer_angle * 1.15

	for wheel in _steering_wheels:
		var is_left: bool = wheel.position.x < 0.0
		var is_inner: bool = (is_left and turn_direction > 0.0) or (not is_left and turn_direction < 0.0)
		var radius: float = (
			turn_radius - _half_track if is_inner else turn_radius + _half_track
		)
		radius = maxf(radius, 1.0)
		var wheel_angle: float = atan(_wheelbase / radius)
		wheel.steering = clampf(wheel_angle * turn_direction, -angle_limit, angle_limit)


## Стабилизация кузова на скорости: гасим неестественный крен.
func _update_stability(forward_speed: float) -> void:
	if not anti_roll_enabled:
		return

	var speed: float = absf(forward_speed)
	var speed_kmh: float = speed * 3.6
	if speed_kmh <= stability_start_kmh:
		return

	# Стабилизация нужна только когда колёса реально стоят на земле.
	if _grounded_wheels() < 2:
		return

	var up: Vector3 = global_transform.basis.y
	# Если машина уже почти на крыше — не дёргаем её искусственно.
	if up.dot(Vector3.UP) < 0.2:
		return

	var speed_ratio: float = clampf(
		(speed_kmh - stability_start_kmh) / maxf(stability_full_kmh - stability_start_kmh, 1.0),
		0.0,
		1.0
	)
	# На ручнике анти-крен почти выключаем: кузов должен свободно крениться,
	# иначе стабилизатор «борется» с заносом и машина просто тормозит.
	var handbrake: bool = Input.is_action_pressed("handbrake")
	var stability_scale: float = handbrake_anti_roll_factor if handbrake else 1.0

	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	# Положительный крен — правый борт поднят. Момент вокруг "носа" выравнивает кузов.
	var roll_angle: float = atan2(right.dot(Vector3.UP), up.dot(Vector3.UP))
	var roll_rate: float = angular_velocity.dot(forward)
	var torque: float = roll_angle * anti_roll_strength - roll_rate * anti_roll_damping
	torque = clampf(torque, -max_anti_roll_torque, max_anti_roll_torque)

	apply_torque(forward * torque * speed_ratio * stability_scale)


## Аэродинамика: сопротивление воздуха, качение и прижимная сила.
func _update_aero() -> void:
	var speed: float = linear_velocity.length()
	if speed < 0.05:
		return

	var grounded: int = _grounded_wheels()

	# Сопротивление воздуха растёт как квадрат скорости — оно же ограничивает
	# максималку, поэтому двигатель не «тянет» машину бесконечно.
	apply_central_force(-linear_velocity / speed * drag_coefficient * speed * speed)

	if grounded >= 2:
		# Сопротивление качению: пропорционально скорости, только на земле.
		apply_central_force(-linear_velocity * rolling_resistance)

		# Прижимная сила помогает держать колёса на дороге на скорости.
		if downforce_coefficient > 0.0:
			apply_central_force(
				-global_transform.basis.y * downforce_coefficient * speed * speed
			)


func _grounded_wheels() -> int:
	var grounded: int = 0
	for wheel in _all_wheels:
		if wheel.is_in_contact():
			grounded += 1
	return grounded


## Ручник: задние колёса теряют часть сцепления — машина уходит в занос.
## Сцепление сбрасываем быстро, а возвращаем плавно: так занос можно удержать,
## а после отпускания ручника задняя ось не «прилипает» мгновенно.
func _update_handbrake_grip(delta: float) -> void:
	var handbrake: bool = Input.is_action_pressed("handbrake")
	var factor: float = handbrake_grip_factor if handbrake else 1.0
	var rate: float = (70.0 if handbrake else 14.0) * delta
	for wheel in _rear_wheels:
		var base: float = float(_base_friction.get(wheel, wheel.wheel_friction_slip))
		wheel.wheel_friction_slip = move_toward(
			wheel.wheel_friction_slip, base * factor, rate
		)


## Газ, рабочий тормоз, задний ход и ручник.
func _update_engine_and_brakes(forward_speed: float) -> void:
	# get_axis: "brake" -> -1, "accelerate" -> +1.
	var throttle: float = Input.get_axis("brake", "accelerate")
	var handbrake: bool = Input.is_action_pressed("handbrake")

	var engine_force: float = 0.0
	var brake_force: float = 0.0
	# Центральное замедление: гарантирует предсказуемый тормозной путь
	# независимо от того, как физический движок считает силу колодок.
	var deceleration: float = 0.0

	if throttle > 0.01:
		# Едем назад — педаль газа работает как тормоз.
		if forward_speed < -1.0:
			brake_force = max_brake_force * throttle
			deceleration = brake_deceleration * throttle
		else:
			engine_force = throttle * _engine_force_at_speed(forward_speed)
	elif throttle < -0.01:
		# Едем вперёд — педаль тормоза тормозит, иначе включается задний ход.
		if forward_speed > 1.0:
			brake_force = max_brake_force * -throttle
			deceleration = brake_deceleration * -throttle
		else:
			engine_force = (
				throttle * _engine_force_at_speed(forward_speed) * reverse_force_multiplier
			)
	else:
		# Газ отпущен — двигатель понемногу тормозит машину.
		if absf(forward_speed) > 2.0:
			deceleration = engine_braking_deceleration

	# Антипробуксовка: не даём ведущим колёсам бесконечно буксовать.
	engine_force *= _traction_factor()

	# Ручник снимает тягу и добавляет лишь небольшое замедление, чтобы машина
	# не «якорилась»: занос должен продолжаться по инерции.
	if handbrake:
		engine_force = 0.0
		deceleration = maxf(deceleration, handbrake_deceleration)

	# Центральная сила торможения направлена против движения.
	# Считаем её по массе пустой машины: с грузом тормозной путь растёт,
	# а не остаётся одинаковым за счёт искусственного масштабирования.
	if deceleration > 0.0 and absf(forward_speed) > 0.15:
		var direction: float = signf(forward_speed)
		var brake_mass: float = _empty_mass if _empty_mass > 0.0 else mass
		apply_central_force(global_transform.basis.z * deceleration * brake_mass * direction)

	# Сила тяги делится между ведущими колёсами, чтобы max_engine_force
	# оставалась суммарной силой, а не силой на каждое колесо.
	# Знак инвертирован: в Godot положительный engine_force толкает кузов
	# вдоль +Z, а «нос» машины (капот/фары) смотрит в -Z.
	var driven_count: int = maxi(_traction_wheels.size(), 1)
	for wheel in _traction_wheels:
		wheel.engine_force = -engine_force / driven_count

	# Рабочий тормоз — на все колёса.
	for wheel in _all_wheels:
		wheel.brake = brake_force

	# Ручник — дополнительно на задние колёса (пробуксовка/блокировка).
	if handbrake:
		for wheel in _rear_wheels:
			wheel.brake = maxf(wheel.brake, handbrake_force)


## Тяга двигателя: падает к максимальной скорости, как у реальной коробки.
func _engine_force_at_speed(forward_speed: float) -> float:
	var speed_kmh: float = absf(forward_speed) * 3.6
	var ratio: float = clampf(speed_kmh / maxf(max_speed_kmh, 1.0), 0.0, 1.0)
	var falloff: float = 1.0 - 0.85 * ratio * ratio
	return max_engine_force * maxf(falloff, 0.08)


## Коэффициент тяги антипробуксовки (1 — полная тяга).
func _traction_factor() -> float:
	if traction_control <= 0.0:
		return 1.0
	var worst: float = 1.0
	var measured: bool = false
	for wheel in _traction_wheels:
		if wheel.is_in_contact():
			measured = true
			worst = minf(worst, wheel.get_skidinfo())
	if not measured or worst >= 0.75:
		return 1.0
	return lerpf(1.0 - traction_control, 1.0, clampf(worst / 0.75, 0.0, 1.0))


# --- Взаимодействие с игроком ---------------------------------------------


## Занята ли машина водителем.
func is_occupied() -> bool:
	return is_instance_valid(driver)


## Посадить игрока за руль. Вызывается из player.gd.
func enter_vehicle(player: Node) -> void:
	driver = player
	_current_steer = 0.0
	sleeping = false
	_set_third_person_view(false)


## Высадить игрока: машина остаётся на стояночном тормозе.
func exit_vehicle() -> void:
	_set_third_person_view(false)
	driver = null
	_apply_park_brake()


## Камера от первого лица, установленная в машине.
func get_vehicle_camera() -> Camera3D:
	return get_node_or_null("Camera3D") as Camera3D


## Точка, где игрок окажется после выхода из машины (сбоку от кузова).
## Сначала проверяется левый борт, затем правый. Позиция "прижимается" к земле.
func get_exit_position(prefer_left: bool = true) -> Vector3:
	var sides: Array[float] = [-1.0, 1.0]
	if not prefer_left:
		sides = [1.0, -1.0]

	for side in sides:
		var candidate: Vector3 = to_global(Vector3(side * 2.0, 0.3, 0.3))
		if _is_exit_clear(candidate):
			return _snap_to_ground(candidate)

	# Оба борта чем-то заняты — высаживаем в любом случае слева.
	return _snap_to_ground(to_global(Vector3(sides[0] * 2.0, 0.3, 0.3)))


## Свободно ли место для капсулы игрока в указанной точке.
func _is_exit_clear(point: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), point + Vector3.UP * 0.9)
	params.exclude = [get_rid()]

	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


## Опускаем точку выхода на землю лучом сверху вниз.
func _snap_to_ground(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 1.5,
		point + Vector3.DOWN * 3.0
	)
	query.exclude = [get_rid()]

	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position + Vector3.UP * 0.05

	return point + Vector3.UP * 0.05


## Стояночный тормоз для пустой машины.
func _apply_park_brake() -> void:
	for wheel in _all_wheels:
		wheel.engine_force = 0.0
		wheel.brake = maxf(max_brake_force, 20.0)
	# После выхода из машины возвращаем задним колёсам обычное сцепление,
	# иначе машина останется «на ручнике» до следующей поездки.
	for wheel in _rear_wheels:
		var base: float = float(_base_friction.get(wheel, wheel.wheel_friction_slip))
		wheel.wheel_friction_slip = base
