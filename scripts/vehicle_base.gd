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
@export_range(0.1, 1.0, 0.05) var high_speed_steer_factor: float = 0.30
## Скорость (км/ч), при которой достигается high_speed_steer_factor.
@export_range(30.0, 200.0, 5.0) var high_speed_steer_kmh: float = 80.0
## Предельное боковое ускорение, м/с². Ограничивает угол руля на скорости,
## чтобы машина не переворачивалась от резкого поворота. 0 — отключить.
@export_range(0.0, 20.0, 0.5) var max_lateral_accel: float = 9.0

@export_group("Устойчивость")
## Сила стабилизации крена кузова, Н·м на радиан.
@export_range(0.0, 40000.0, 100.0) var anti_roll_strength: float = 24000.0
## Демпфирование крена, Н·м на рад/с.
@export_range(0.0, 30000.0, 100.0) var anti_roll_damping: float = 9000.0
## Максимальный стабилизирующий момент, Н·м.
@export_range(0.0, 12000.0, 100.0) var max_anti_roll_torque: float = 8000.0
## Скорость (км/ч), с которой начинает работать стабилизация крена.
@export_range(0.0, 80.0, 1.0) var stability_start_kmh: float = 30.0
## Скорость (км/ч), на которой стабилизация выходит на полную силу.
@export_range(30.0, 180.0, 5.0) var stability_full_kmh: float = 95.0
## Прижимная сила: Н на (м/с)². Помогает держать колёса на дороге.
@export_range(0.0, 8.0, 0.1) var downforce_coefficient: float = 1.2

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
# Колёсная база, м (для ограничения угла руля на скорости).
var _wheelbase: float = 3.4

# Текущий (сглаженный) угол руля.
var _current_steer: float = 0.0

## Игрок, который сейчас управляет машиной. null — машина пустая.
var driver: Node = null

# Камеры машины: вид от первого лица и орбитальная камера от третьего лица.
var _first_person_camera: Camera3D = null
var _third_person_camera: Camera3D = null
var _third_person_active: bool = false

# Данные систем частиц и вращения колёс: wheel, dust, chips, mesh.
var _wheel_effects: Array[Dictionary] = []


func _ready() -> void:
	# Машина не должна "засыпать" на стоянке, иначе первый газ может не сработать.
	can_sleep = false
	_collect_wheels()
	_hide_body_wheels()

	_first_person_camera = get_vehicle_camera()
	_third_person_camera = get_node_or_null("ThirdPersonCamera") as Camera3D
	_setup_wheel_effects()


## Скрываем колёса, встроенные в модель кузова: ими управляют VehicleWheel3D.
func _hide_body_wheels() -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return

	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel := body.get_node_or_null(wheel_name)
		if wheel is Node3D:
			wheel.visible = false


## V — переключение вида от первого лица на камеру сзади и обратно.
func _unhandled_input(event: InputEvent) -> void:
	if not is_occupied():
		return
	if not InputMap.has_action("camera_toggle"):
		return
	if event.is_action_pressed("camera_toggle"):
		_set_third_person_view(not _third_person_active)
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
	_update_wheel_effects(delta)

	# Пустой машиной никто не управляет — держим её на стояночном тормозе.
	if not is_occupied():
		_apply_park_brake()
		return

	# Скорость вдоль "носа" машины (-Z), в м/с. Положительная — вперёд.
	var forward_speed: float = linear_velocity.dot(-global_transform.basis.z)

	_update_steering(delta, forward_speed)
	_update_engine_and_brakes(forward_speed)
	_update_stability(forward_speed)


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

	# Применяем угол только к рулевым колёсам.
	for wheel in _steering_wheels:
		wheel.steering = _current_steer


## Стабилизация кузова на скорости: гасим неестественный крен и добавляем прижим.
func _update_stability(forward_speed: float) -> void:
	var speed: float = absf(forward_speed)
	var speed_kmh: float = speed * 3.6
	if speed_kmh <= stability_start_kmh:
		return

	# Стабилизация нужна только когда колёса реально стоят на земле.
	var grounded: int = 0
	for wheel in _all_wheels:
		if wheel.is_in_contact():
			grounded += 1
	if grounded < 2:
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
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	# Положительный крен — правый борт поднят. Момент вокруг "носа" выравнивает кузов.
	var roll_angle: float = atan2(right.dot(Vector3.UP), up.dot(Vector3.UP))
	var roll_rate: float = angular_velocity.dot(forward)
	var torque: float = roll_angle * anti_roll_strength - roll_rate * anti_roll_damping
	torque = clampf(torque, -max_anti_roll_torque, max_anti_roll_torque)

	apply_torque(forward * torque * speed_ratio)

	if downforce_coefficient > 0.0:
		apply_central_force(-up * downforce_coefficient * speed * speed)


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
