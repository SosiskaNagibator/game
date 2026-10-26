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

@export_group("Двигатель")
## Максимальная суммарная сила тяги на ведущих колёсах, Н.
## Для лёгкой Газели ~1500-3000, для тяжёлого грузовика ~8000-15000.
@export_range(0.0, 30000.0, 50.0) var max_engine_force: float = 1500.0
## Доля силы тяги заднего хода от max_engine_force.
@export_range(0.1, 1.0, 0.05) var reverse_force_multiplier: float = 0.6

@export_group("Руль")
## Максимальный угол поворота колёс в радианах (0.5 рад ≈ 28.6°).
@export_range(0.1, 1.2, 0.01, "radians_as_degrees") var max_steer_angle: float = 0.5
## Скорость сглаживания руля (чем больше — тем резче реакция).
@export_range(0.5, 20.0, 0.5) var steer_smoothing: float = 5.0
## Доля максимального угла руля на высокой скорости (защита от переворота).
@export_range(0.1, 1.0, 0.05) var high_speed_steer_factor: float = 0.45
## Скорость (км/ч), при которой достигается high_speed_steer_factor.
@export_range(30.0, 200.0, 5.0) var high_speed_steer_kmh: float = 90.0

@export_group("Тормоза")
## Сила торможения рабочей тормозной системы на каждое колесо, Н.
@export_range(0.0, 300.0, 1.0) var max_brake_force: float = 30.0
## Сила торможения ручника на задние колёса, Н.
@export_range(0.0, 300.0, 1.0) var handbrake_force: float = 80.0

# Все колёса машины (заполняется в _ready).
var _all_wheels: Array[VehicleWheel3D] = []
# Колёса, у которых в Инспекторе включён "Use as Steering".
var _steering_wheels: Array[VehicleWheel3D] = []
# Колёса, у которых в Инспекторе включён "Use as Traction" (ведущие).
var _traction_wheels: Array[VehicleWheel3D] = []
# Задние колёса (определяются по локальной оси +Z).
var _rear_wheels: Array[VehicleWheel3D] = []

# Текущий (сглаженный) угол руля.
var _current_steer: float = 0.0

## Игрок, который сейчас управляет машиной. null — машина пустая.
var driver: Node = null


func _ready() -> void:
	# Машина не должна "засыпать" на стоянке, иначе первый газ может не сработать.
	can_sleep = false
	_collect_wheels()


## Собираем колёса один раз при старте и распределяем их по спискам.
func _collect_wheels() -> void:
	for child in get_children():
		if child is not VehicleWheel3D:
			continue

		var wheel: VehicleWheel3D = child
		_all_wheels.append(wheel)

		if wheel.use_as_steering:
			_steering_wheels.append(wheel)
		if wheel.use_as_traction:
			_traction_wheels.append(wheel)
		# В Godot перед машины — это -Z, значит зад — это +Z.
		if wheel.position.z > 0.0:
			_rear_wheels.append(wheel)

	if _steering_wheels.is_empty():
		push_warning("BaseVehicle: ни одному колесу не включён 'Use as Steering'.")
	if _traction_wheels.is_empty():
		push_warning("BaseVehicle: ни одному колесу не включён 'Use as Traction'.")


func _physics_process(delta: float) -> void:
	# Пустой машиной никто не управляет — держим её на стояночном тормозе.
	if not is_occupied():
		_apply_park_brake()
		return

	# Скорость вдоль "носа" машины (-Z), в м/с. Положительная — вперёд.
	var forward_speed: float = linear_velocity.dot(-global_transform.basis.z)

	_update_steering(delta, forward_speed)
	_update_engine_and_brakes(forward_speed)


## Плавный поворот руля (lerp) + возврат в центр + ограничение на скорости.
func _update_steering(delta: float, forward_speed: float) -> void:
	# get_axis: "steer_right" -> -1, "steer_left" -> +1.
	var steer_input: float = Input.get_axis("steer_right", "steer_left")

	# Чем быстрее едем, тем меньше максимальный угол колёс.
	var speed_kmh: float = absf(forward_speed) * 3.6
	var speed_ratio: float = clampf(speed_kmh / high_speed_steer_kmh, 0.0, 1.0)
	var steer_limit: float = max_steer_angle * lerpf(1.0, high_speed_steer_factor, speed_ratio)

	var target_steer: float = steer_input * steer_limit

	# Сглаживание: руль плавно идёт к цели и так же плавно возвращается в центр.
	var weight: float = clampf(steer_smoothing * delta, 0.0, 1.0)
	_current_steer = lerp(_current_steer, target_steer, weight)

	# Применяем угол только к рулевым колёсам.
	for wheel in _steering_wheels:
		wheel.steering = _current_steer


## Газ, рабочий тормоз, задний ход и ручник.
func _update_engine_and_brakes(forward_speed: float) -> void:
	# get_axis: "brake" -> -1, "accelerate" -> +1.
	var throttle: float = Input.get_axis("brake", "accelerate")

	var engine_force: float = 0.0
	var brake_force: float = 0.0

	if throttle > 0.01:
		# Едем назад — педаль газа работает как тормоз.
		if forward_speed < -1.0:
			brake_force = max_brake_force * throttle
		else:
			engine_force = throttle * max_engine_force
	elif throttle < -0.01:
		# Едем вперёд — педаль тормоза тормозит, иначе включается задний ход.
		if forward_speed > 1.0:
			brake_force = max_brake_force * -throttle
		else:
			engine_force = throttle * max_engine_force * reverse_force_multiplier

	# Ручник: блокируем задние колёса и снимаем тягу.
	var handbrake: bool = Input.is_action_pressed("handbrake")
	if handbrake:
		engine_force = 0.0

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


# --- Взаимодействие с игроком ---------------------------------------------


## Занята ли машина водителем.
func is_occupied() -> bool:
	return is_instance_valid(driver)


## Посадить игрока за руль. Вызывается из player.gd.
func enter_vehicle(player: Node) -> void:
	driver = player
	_current_steer = 0.0
	sleeping = false


## Высадить игрока: машина остаётся на стояночном тормозе.
func exit_vehicle() -> void:
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
