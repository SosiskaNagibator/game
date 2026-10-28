extends CharacterBody3D
## Игрок от первого лица: ходьба, бег, прыжок, приседание,
## вход в машину и выход из неё.
##
## Управление:
##   W/A/S/D      — движение
##   Shift        — бег
##   Space        — прыжок
##   Ctrl         — присесть (удерживать)
##   E            — сесть в машину / выйти из машины
##   V            — вид от третьего лица (в машине)
##   Esc          — пауза (обрабатывается камерой машины)

@export_group("Передвижение")
## Скорость ходьбы, м/с.
@export var walk_speed: float = 4.5
## Скорость бега, м/с.
@export var sprint_speed: float = 7.5
## Скорость в приседе, м/с.
@export var crouch_speed: float = 2.2
## Ускорение разгона/торможения, м/с².
@export var acceleration: float = 12.0
## Начальная скорость прыжка, м/с.
@export var jump_velocity: float = 5.0
## Доля высоты капсулы в приседе (0.55 = 55% от роста).
@export_range(0.35, 0.8, 0.01) var crouch_height_ratio: float = 0.55
## Скорость изменения высоты капсулы при приседании.
@export var crouch_speed_change: float = 4.0

@export_group("Камера")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022
@export_range(30.0, 89.0, 1.0) var max_pitch_deg: float = 85.0

@export_group("Взаимодействие")
## С какого расстояния от центра машины можно в неё сесть.
@export var enter_range: float = 6.0

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _hint: Label = $HUD/Hint

# Ресурс капсулы (меняем высоту при приседании).
var _capsule: CapsuleShape3D
var _stand_height: float = 1.8
var _crouch_height: float = 1.0
# Наклон камеры в радианах.
var _pitch: float = 0.0
# Игрок сейчас за рулём?
var _driving: bool = false
var _landscape_editing: bool = false
# Машина, которой управляет игрок.
var _vehicle: BaseVehicle = null
# Подсказка от других систем (перестановка деревьев и т.п.).
var _hint_override: String = ""


func _ready() -> void:
	_capsule = _collision.shape as CapsuleShape3D
	_stand_height = _capsule.height
	_crouch_height = _stand_height * crouch_height_ratio
	_camera.position.y = _stand_height - 0.2
	_pitch = _camera.rotation.x

	_hint.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# В редакторе ландшафта мышь занята установкой объектов, но ходить можно (B).
	if _driving:
		return

	_apply_gravity(delta)
	_update_crouch(delta)
	_update_movement(delta)
	move_and_slide()


func _process(_delta: float) -> void:
	# За рулём подсказку показывает сама машина.
	if _driving:
		return

	# Подсказка от другой системы важнее подсказки про машину.
	if not _hint_override.is_empty():
		_hint.text = _hint_override
		_hint.visible = true
		return

	_hint.text = "[E] Сесть в машину"
	_hint.visible = _find_nearest_vehicle() != null


func _input(event: InputEvent) -> void:
	if _landscape_editing:
		return

	# E — сесть в машину или выйти из неё.
	if event.is_action_pressed("interact"):
		if _driving:
			_leave_vehicle()
		else:
			_enter_nearest_vehicle()
		return

	# Клик по окну возвращает захват мыши (например, после паузы).
	if event is InputEventMouseButton and event.pressed:
		if not _landscape_editing and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if _driving:
		return

	# Вращение камеры мышью: игрок поворачивается вокруг Y, камера наклоняется по X.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)

		var pitch_limit: float = deg_to_rad(max_pitch_deg)
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity,
			-pitch_limit,
			pitch_limit
		)
		_camera.rotation.x = _pitch
		_camera.rotation.z = 0.0


# --- Движение --------------------------------------------------------------


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity


func _get_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _update_movement(delta: float) -> void:
	# get_vector: вперёд = -Y (move_forward — отрицательное действие).
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)

	# Направление относительно текущего поворота игрока.
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed: float = walk_speed
	if _capsule.height < _stand_height * 0.9:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed

	var target: Vector3 = direction * speed
	# В воздухе управление слабее.
	var accel: float = acceleration if is_on_floor() else acceleration * 0.3
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)


# --- Приседание ------------------------------------------------------------


func _update_crouch(delta: float) -> void:
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	var target_height: float = _crouch_height if wants_crouch else _stand_height

	# Не даём встать, если над головой потолок.
	if not wants_crouch and _capsule.height < _stand_height - 0.01 and not _has_headroom():
		target_height = _capsule.height

	var new_height: float = move_toward(_capsule.height, target_height, crouch_speed_change * delta)
	_capsule.height = new_height
	_collision.position.y = new_height * 0.5
	_camera.position.y = lerpf(_camera.position.y, new_height - 0.2, 10.0 * delta)


func _has_headroom() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * (_capsule.height - 0.05),
		global_position + Vector3.UP * (_stand_height + 0.05)
	)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Машина ----------------------------------------------------------------


func _find_nearest_vehicle() -> BaseVehicle:
	var nearest: BaseVehicle = null
	var nearest_distance: float = enter_range

	for node in get_tree().get_nodes_in_group("vehicles"):
		if node is not BaseVehicle:
			continue

		var vehicle: BaseVehicle = node
		if vehicle.is_occupied():
			continue

		var distance: float = global_position.distance_to(vehicle.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = vehicle

	return nearest


func _enter_nearest_vehicle() -> void:
	var vehicle: BaseVehicle = _find_nearest_vehicle()
	if vehicle == null:
		return

	var vehicle_camera: Camera3D = vehicle.get_vehicle_camera()
	if vehicle_camera == null:
		push_warning("Player: у машины нет Camera3D.")
		return

	_vehicle = vehicle
	_driving = true
	vehicle.enter_vehicle(self)

	# Переключаем камеру и прячем игрока.
	_camera.current = false
	vehicle_camera.current = true
	visible = false
	_collision.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)

	_hint.text = "[E] Выйти из машины    [V] Сменить вид"
	_hint.visible = true


func _leave_vehicle() -> void:
	if _vehicle == null:
		return

	var vehicle: BaseVehicle = _vehicle
	var exit_position: Vector3 = vehicle.get_exit_position()

	vehicle.exit_vehicle()
	_vehicle = null
	_driving = false

	global_position = exit_position
	velocity = Vector3.ZERO
	visible = true
	_collision.set_deferred("disabled", false)
	set_physics_process(true)

	var vehicle_camera: Camera3D = vehicle.get_vehicle_camera()
	if vehicle_camera != null:
		vehicle_camera.current = false
	_camera.current = true

	_hint.text = "[E] Сесть в машину"


# --- Публичный API для других систем ----------------------------------------


## Камера от первого лица (нужна для наведения на объекты).
func get_camera() -> Camera3D:
	return _camera


## Игрок сейчас за рулём?
func is_driving() -> bool:
	return _driving


func set_landscape_editing(enabled: bool) -> void:
	_landscape_editing = enabled
	if enabled:
		velocity = Vector3.ZERO


## Показать подсказку поверх стандартных (деревья, склад и т.п.).
func set_hint_override(text: String) -> void:
	_hint_override = text


## Убрать внешнюю подсказку.
func clear_hint_override() -> void:
	_hint_override = ""
