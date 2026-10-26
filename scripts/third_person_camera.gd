extends Camera3D
## Камера от третьего лица для автомобиля.
##
## Вращается мышью вокруг машины на полный оборот, приближается/отдаляется
## колесом мыши. Включается и выключается клавишей V (действие "camera_toggle").

@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022
## Инверсия вертикали: мышь вверх — камера опускается.
@export var invert_y: bool = true
## Полное вращение по вертикали (орбита может пройти над машиной).
@export var full_rotation: bool = true
## Дистанция до машины по умолчанию.
@export_range(3.0, 12.0, 0.1) var distance: float = 6.5
## Минимальная и максимальная дистанция (колесо мыши).
@export_range(2.0, 8.0, 0.1) var min_distance: float = 3.5
@export_range(6.0, 16.0, 0.1) var max_distance: float = 11.0
## Ограничения наклона орбиты в градусах.
@export_range(-30.0, 10.0, 1.0) var min_pitch_deg: float = -10.0
@export_range(5.0, 75.0, 1.0) var max_pitch_deg: float = 60.0
## Начальный наклон орбиты (чем больше — тем выше камера).
@export_range(0.0, 60.0, 1.0) var start_pitch_deg: float = 14.0
## Скорость сглаживания движения камеры.
@export_range(1.0, 30.0, 0.5) var follow_smoothing: float = 10.0

# Точка, вокруг которой вращается камера (в локальных координатах машины).
var _target_local: Vector3 = Vector3(0.0, 1.15, 0.0)
var _yaw: float = 0.0
var _pitch: float = 14.0
var _current_distance: float = 6.5
var _initialized: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	reset_view()


func reset_view() -> void:
	_yaw = 0.0
	_pitch = start_pitch_deg
	_current_distance = distance
	_initialized = false


func _input(event: InputEvent) -> void:
	if not current:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Полный оборот вокруг машины без ограничения по горизонтали.
		# _yaw хранится в градусах, а mouse_sensitivity — в радианах на пиксель.
		var yaw_step: float = rad_to_deg(mouse_sensitivity)
		_yaw = wrapf(_yaw - event.relative.x * yaw_step, -180.0, 180.0)

		var direction: float = 1.0 if invert_y else -1.0
		_pitch += event.relative.y * mouse_sensitivity * 60.0 * direction

		if full_rotation:
			_pitch = wrapf(_pitch, -180.0, 180.0)
		else:
			_pitch = clampf(_pitch, min_pitch_deg, max_pitch_deg)
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_current_distance = clampf(_current_distance - 0.6, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_current_distance = clampf(_current_distance + 0.6, min_distance, max_distance)


func _process(delta: float) -> void:
	if not current:
		return

	var car := get_parent() as Node3D
	if car == null:
		return

	var yaw_rad: float = deg_to_rad(_yaw)
	var pitch_rad: float = deg_to_rad(_pitch)
	var horizontal: float = cos(pitch_rad)
	var local_offset := Vector3(
		sin(yaw_rad) * horizontal,
		sin(pitch_rad),
		cos(yaw_rad) * horizontal
	) * _current_distance

	var target_global: Vector3 = car.to_global(_target_local)
	var desired_global: Vector3 = car.to_global(_target_local + local_offset)

	# Не даём камере уйти под землю или за препятствие.
	desired_global = _avoid_obstacles(target_global, desired_global, car)

	if not _initialized:
		global_position = desired_global
		_initialized = true
	else:
		var weight: float = 1.0 - exp(-follow_smoothing * delta)
		global_position = global_position.lerp(desired_global, weight)

	look_at(target_global, Vector3.UP)


func _avoid_obstacles(from: Vector3, to: Vector3, car: Node3D) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [car.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit.position + hit.normal * 0.35
