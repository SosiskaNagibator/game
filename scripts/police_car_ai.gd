class_name PoliceCar
extends CharacterBody3D
## Патрульная машина КПП: стоит на обочине, а по команде КПП бросается в погоню.
##
## Корень — CharacterBody3D, а не VehicleBody3D: для погони важнее устойчивость,
## чем честная физика подвески. Машина ведёт себя как «умный» кинематический
## объект: едет вперёд, плавно доворачивает по маршруту и не переворачивается.
##
## Состояния:
##   * PARKED  — стоит на месте и не тратит физику;
##   * CHASING — едет к машине игрока через NavigationAgent3D.
##
## Если в уровне нет запечённого NavigationRegion3D, включается запасной режим:
## машина едет к цели напрямую по вектору.

## Машину игрока догнали: КПП должен оформить арест.
signal player_caught(vehicle: Node3D)

enum State { PARKED, CHASING }

@export_group("Погоня")
## Максимальная скорость преследования, м/с.
@export_range(5.0, 60.0, 0.5) var chase_speed: float = 30.0
## Ускорение и торможение до целевой скорости, м/с².
@export_range(1.0, 40.0, 0.5) var acceleration: float = 12.0
## Скорость доворота корпуса (экспоненциальное сглаживание), 1/с.
@export_range(0.5, 12.0, 0.1) var turn_speed: float = 4.0
## Во сколько раз падает скорость в крутом повороте.
@export_range(0.1, 1.0, 0.05) var min_turn_speed_factor: float = 0.45
## Дистанция от переднего бампера до цели, на которой начинается захват, м.
@export_range(0.5, 10.0, 0.1) var catch_distance: float = 3.0
## Сколько секунд нужно продержаться в этой дистанции, чтобы арестовать.
@export_range(0.2, 10.0, 0.1) var catch_time: float = 2.0
## Вынос «носа» машины от центра корпуса, м (для замера дистанции захвата).
@export_range(0.0, 4.0, 0.05) var nose_offset: float = 2.2
## Гравитация, м/с².
@export_range(0.0, 40.0, 0.1) var gravity: float = 9.8

@export_group("Маячки")
## Горит ли сирена прямо сейчас.
@export var siren_enabled: bool = false
## Частота переключения красный/синий, Гц.
@export_range(0.5, 8.0, 0.1) var flash_rate: float = 2.6
## Яркость горящего маячка.
@export_range(0.5, 20.0, 0.1) var light_energy: float = 5.0
@export var red_light_color: Color = Color(1.0, 0.10, 0.06, 1.0)
@export var blue_light_color: Color = Color(0.12, 0.28, 1.0, 1.0)

@export_group("Сирена")
## Свой звук сирены. Если пусто — генерируется двухсекундный «вой» на старте погони.
@export var siren_stream: AudioStream = null
## Громкость сирены, дБ.
@export_range(-40.0, 6.0, 0.5) var siren_volume_db: float = -6.0
## Расстояние, на котором сирену ещё слышно, м.
@export_range(1.0, 200.0, 1.0) var siren_max_distance: float = 120.0

## Текущее состояние (см. enum State).
var state: State = State.PARKED
## Машина игрока, за которой идёт охота. Пока null — цели нет.
var target_node: Node3D = null

var _speed: float = 0.0
var _catch_timer: float = 0.0
var _caught: bool = false
var _phase: float = 0.0
var _nav_check_left: float = 0.0
var _nav_has_regions: bool = false
var _generated_siren: AudioStreamWAV = null

@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _siren_audio: AudioStreamPlayer3D = $SirenAudio
@onready var _red_light: OmniLight3D = %RedLight
@onready var _blue_light: OmniLight3D = %BlueLight


func _ready() -> void:
	_red_light.light_color = red_light_color
	_blue_light.light_color = blue_light_color
	_apply_siren(false)
	set_process(false)
	# Пока машина припаркована, агент не должен искать путь.
	_agent.target_position = global_position


func _process(delta: float) -> void:
	_phase += delta * flash_rate
	# Полный цикл: красный -> пауза -> синий -> пауза.
	var step: int = int(_phase) % 2
	_red_light.light_energy = light_energy if step == 0 else 0.0
	_blue_light.light_energy = light_energy if step == 1 else 0.0


func _physics_process(delta: float) -> void:
	if state != State.CHASING:
		velocity = Vector3.ZERO
		return
	if not _has_target():
		stop_chase()
		return

	var target_position: Vector3 = target_node.global_position
	_refresh_navigation(delta)
	_agent.target_position = target_position

	var direction: Vector3 = _path_direction(target_position)
	var target_speed: float = chase_speed

	if direction.length_squared() > 0.0001:
		var yaw_error: float = absf(
			wrapf(_yaw_for(direction) - global_rotation.y, -PI, PI)
		)
		var turn_ratio: float = clampf(yaw_error / PI, 0.0, 1.0)
		target_speed *= lerpf(1.0, min_turn_speed_factor, turn_ratio)
		_smooth_look_at(direction, delta)

	# У самой цели сбрасываем газ: иначе машина протаранит игрока и проскочит.
	var distance: float = _catch_distance(target_position)
	if distance < 20.0:
		target_speed = minf(target_speed, maxf(2.0, distance * 1.5))

	_speed = move_toward(_speed, target_speed, acceleration * delta)

	# Едем строго вдоль носа машины: так CharacterBody3D не «дрифтует» боком.
	var forward: Vector3 = -global_transform.basis.z
	velocity.x = forward.x * _speed
	velocity.z = forward.z * _speed

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()
	_update_catch(delta, target_position)


# --- Публичный API ----------------------------------------------------------


## Начать погоню за машиной игрока. Вызывается из checkpoint.gd.
func start_chase(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	target_node = target
	state = State.CHASING
	_speed = 0.0
	_catch_timer = 0.0
	_caught = false
	_nav_check_left = 0.0
	_agent.target_position = target.global_position
	set_siren(true)


## Вернуть машину в состояние «припаркована».
func stop_chase() -> void:
	state = State.PARKED
	target_node = null
	velocity = Vector3.ZERO
	_speed = 0.0
	_catch_timer = 0.0
	_caught = false


## Идёт ли сейчас погоня.
func is_chasing() -> bool:
	return state == State.CHASING


## Включить/выключить сирену вместе со звуком. Вызывается из checkpoint.gd.
func set_siren(on: bool) -> void:
	if siren_enabled == on:
		return
	siren_enabled = on
	_phase = 0.0
	set_process(on)
	_apply_siren(on)

	if on:
		_siren_audio.stream = _ensure_siren_stream()
		_siren_audio.volume_db = siren_volume_db
		_siren_audio.max_distance = siren_max_distance
		_siren_audio.play()
	else:
		_siren_audio.stop()


func is_siren_on() -> bool:
	return siren_enabled


func _apply_siren(on: bool) -> void:
	if not on:
		_red_light.light_energy = 0.0
		_blue_light.light_energy = 0.0


# --- Навигация --------------------------------------------------------------


func _has_target() -> bool:
	return target_node != null and is_instance_valid(target_node)


## Раз в полсекунды проверяем, есть ли в уровне запечённая навигационная сетка.
func _refresh_navigation(delta: float) -> void:
	_nav_check_left -= delta
	if _nav_check_left > 0.0:
		return
	_nav_check_left = 0.5
	var map: RID = _agent.get_navigation_map()
	_nav_has_regions = map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty()


## Куда ехать: следующая точка маршрута или напрямую к цели, если пути нет.
func _path_direction(target_position: Vector3) -> Vector3:
	var direct: Vector3 = target_position - global_position
	direct.y = 0.0

	if _nav_has_regions and not _agent.is_navigation_finished():
		var next_point: Vector3 = _agent.get_next_path_position()
		var to_next: Vector3 = next_point - global_position
		to_next.y = 0.0
		# Точка «под нами» означает, что путь пуст или уже пройден.
		if to_next.length_squared() > 0.04:
			return to_next.normalized()

	# Запасной режим: навмеша нет, путь не построен или цель вне её.
	return direct.normalized()


## Плавный доворот к направлению движения.
##
## look_at() крутит узел мгновенно, поэтому сначала сглаживаем только угол
## рыскания, а затем отдаём его look_at(): так корпус разворачивается без
## «щелчка» и заодно выравнивается по крену/тангажу на склонах.
func _smooth_look_at(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	var weight: float = 1.0 - exp(-turn_speed * delta)
	var yaw: float = lerp_angle(global_rotation.y, target_yaw, weight)
	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	look_at(global_position + forward, Vector3.UP)


## Угол рыскания, при котором нос машины (локальная -Z) смотрит вдоль direction.
func _yaw_for(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


# --- Захват -----------------------------------------------------------------


## Дистанция от переднего бампера до цели: при контакте сзади центры машин
## расходятся на длину кузова, а бампер до игрока — меньше трёх метров.
func _catch_distance(target_position: Vector3) -> float:
	var nose: Vector3 = global_position - global_transform.basis.z * nose_offset
	return nose.distance_to(target_position)


func _update_catch(delta: float, target_position: Vector3) -> void:
	if _caught:
		return

	if _catch_distance(target_position) <= catch_distance:
		_catch_timer += delta
		if _catch_timer >= catch_time:
			_caught = true
			state = State.PARKED
			velocity = Vector3.ZERO
			_speed = 0.0
			player_caught.emit(target_node)
	else:
		# Отпустили газ и оторвались — таймер быстро сгорает.
		_catch_timer = maxf(_catch_timer - delta * 2.0, 0.0)


# --- Звук -------------------------------------------------------------------


func _ensure_siren_stream() -> AudioStream:
	if siren_stream != null:
		return siren_stream
	if _generated_siren == null:
		_generated_siren = _build_siren_stream()
	return _generated_siren


## Запасная сирена: двухсекундный плавный «вой» 650 → 1300 → 650 Гц.
## Генерируется один раз, чтобы не тащить в проект отдельный аудиофайл.
func _build_siren_stream() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 2.0
	var frames: int = int(RATE * DURATION)
	var fade_frames: float = float(RATE) * 0.06
	var data := PackedByteArray()
	data.resize(frames * 2)

	var phase: float = 0.0
	for i in frames:
		var t: float = float(i) / float(RATE)
		var cycle: float = t / DURATION
		var frequency: float = 650.0 + 650.0 * (0.5 - 0.5 * cos(TAU * cycle))
		phase += TAU * frequency / float(RATE)
		# Плавные края делают петлю бесшовной (без щелчка на стыке).
		var envelope: float = minf(
			minf(float(i) / fade_frames, float(frames - i) / fade_frames), 1.0
		)
		var sample: int = int(
			clampf(sin(phase) * 0.30 * envelope, -1.0, 1.0) * 32767.0
		)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
