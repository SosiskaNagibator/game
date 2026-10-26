extends Camera3D
## Камера от первого лица для машины.
##
## Вращение мышью: Y — вокруг вертикали, X — наклон (ограничен ±80°).
## ESC — освободить мышь и поставить игру на паузу; повторное ESC — продолжить.

## Чувствительность мыши (радиан на пиксель).
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022
## Предел наклона камеры по вертикали в градусах.
@export_range(30.0, 89.0, 1.0) var max_pitch_deg: float = 80.0
## Имя действия для паузы (настраивается в Project Settings -> Input Map).
@export var pause_action: StringName = &"pause"

# Текущий наклон камеры в радианах.
var _pitch: float = 0.0


func _ready() -> void:
	# Камера должна работать и когда дерево на паузе — иначе ESC не "разморозит" игру.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# Пауза / снятие паузы по ESC.
	if event.is_action_pressed(pause_action):
		_toggle_pause()
		return

	# Остальные действия камеры — только когда она активна (игрок за рулём).
	if not current:
		return

	# Клик по окну возвращает захват мыши после паузы.
	if event is InputEventMouseButton and event.pressed:
		if not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Горизонталь: поворот камеры вокруг локальной оси Y (влево/вправо).
		rotation.y -= event.relative.x * mouse_sensitivity

		# Вертикаль: наклон с жёстким ограничением, чтобы камера не переворачивалась.
		var pitch_limit: float = deg_to_rad(max_pitch_deg)
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity,
			-pitch_limit,
			pitch_limit
		)
		rotation.x = _pitch
		rotation.z = 0.0


## Переключение паузы и режима мыши.
func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
