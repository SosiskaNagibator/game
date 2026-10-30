class_name PoliceCheckpoint
extends Node3D
## Полицейский КПП: припаркованная патрульная машина у дороги.
##
## Никаких шлагбаумов: инспекция начинается, когда машина игрока въезжает
## в Area3D рядом с патрульной машиной. Зона предупреждения — отдельная
## сцена (warning_zone.tscn), КПП о ней ничего не знает.
##
## Сценарии:
##   * въехал медленнее 5 км/ч — 3 секунды проверки груза;
##   * едет 5–20 км/ч — просим остановиться; уехал, не встав, — уклонение;
##   * влетел быстрее 20 км/ч — 5 секунд на торможение, иначе погоня.
##
## Результат проверки берётся из CargoSystem.has_contraband().

signal inspection_started(vehicle: BaseVehicle)
signal inspection_finished(vehicle: BaseVehicle, clean: bool)
signal chase_started(vehicle: BaseVehicle, wanted_level: int)
## Игрок уехал из зоны, так и не пройдя проверку.
signal evasion_started(vehicle: BaseVehicle, wanted_level: int)
signal player_arrested(vehicle: BaseVehicle, wanted_level: int)

enum State { IDLE, WAITING, GRACE, INSPECTING, CLEAN, CHASE, ARRESTED }

const COLOR_STOP := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_INFO := Color(0.92, 0.94, 1.0, 1.0)
const COLOR_CLEAR := Color(0.45, 0.95, 0.52, 1.0)
const COLOR_ALERT := Color(1.0, 0.34, 0.28, 1.0)

@export_group("Проверка")
## Ниже этой скорости начинается инспекция, км/ч.
@export_range(0.5, 20.0, 0.5) var inspection_speed_kmh: float = 5.0
## Выше этой скорости машина должна остановиться, км/ч.
@export_range(5.0, 120.0, 1.0) var chase_speed_kmh: float = 20.0
## Сколько секунд даётся на торможение, если машина влетела быстрее 20 км/ч.
@export_range(1.0, 15.0, 0.5) var grace_period: float = 5.0
## Сколько секунд длится проверка груза.
@export_range(0.5, 15.0, 0.5) var inspection_duration: float = 3.0
## Держать машину обездвиженной, пока идёт проверка.
@export var hold_vehicle_during_inspection: bool = true
## Сколько секунд висит сообщение о результате.
@export_range(1.0, 10.0, 0.5) var message_duration: float = 3.0

@export_group("Розыск")
## Уровень розыска при попытке уехать с поста.
@export_range(1, 5, 1) var chase_wanted_level: int = 1
## Уровень розыска при найденной контрабанде.
@export_range(1, 5, 1) var arrest_wanted_level: int = 3
## Пауза перед экраном «Арестован» после ареста, секунды.
@export_range(0.0, 5.0, 0.1) var arrest_delay: float = 1.6
## Показывать экран «Арестован» при аресте.
@export var game_over_enabled: bool = true
## Заканчивать погоню экраном «Арестован» (по умолчанию — только розыск).
@export var chase_ends_in_game_over: bool = false

@export_group("Сцена")
## Сажать КПП на рельеф при старте (иначе используется Y из редактора).
@export var snap_to_ground: bool = true
## Небольшой запас над землёй, м.
@export var ground_offset: float = 0.02

var _state: State = State.IDLE
var _vehicle: BaseVehicle = null
var _passed_vehicle: BaseVehicle = null
var _inspection_left: float = 0.0
var _grace_left: float = 0.0
var _banner_timer: float = 0.0
var _wanted_level: int = 0
var _cargo_system: CargoSystem = null
var _police_car: PoliceCar = null
var _frozen_vehicle: BaseVehicle = null
var _frozen_was_frozen: bool = false
# Погоня уже идёт: КПП больше не начинает проверку при повторном въезде.
var _chase_active: bool = false

@onready var _zone: Area3D = $InspectionZone
@onready var _banner: Control = %Banner
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _progress: ProgressBar = %Progress
@onready var _game_over: Control = %GameOver
@onready var _game_over_title: Label = %GameOverTitle
@onready var _game_over_text: Label = %GameOverText
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	add_to_group("police_checkpoints")
	_police_car = _resolve_police_car()
	if snap_to_ground:
		global_position.y = (
			RuralHeight.terrain_height(global_position.x, global_position.z) + ground_offset
		)
		if _police_car != null:
			# Обочина ниже полотна дороги: сажаем машину отдельно по её XZ.
			var car_position := _police_car.global_position
			car_position.y = (
				RuralHeight.terrain_height(car_position.x, car_position.z) + ground_offset
			)
			_police_car.global_position = car_position

	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)
	_restart_button.pressed.connect(_on_restart_pressed)
	_hide_banner()
	_game_over.visible = false


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(_banner_timer - delta, 0.0)
		if _banner_timer <= 0.0:
			# Сообщение о погоне гаснет, но сама погоня продолжается:
			# состояние CHASE живёт до ареста.
			_hide_banner()
			if _state == State.CLEAN:
				_state = State.IDLE

	match _state:
		State.WAITING:
			_update_waiting()
		State.GRACE:
			_update_grace(delta)
		State.INSPECTING:
			_update_inspection(delta)


func _exit_tree() -> void:
	_release_frozen_vehicle()


# --- Публичный API ----------------------------------------------------------


## Текущий уровень розыска, который выдал этот КПП.
func get_wanted_level() -> int:
	return _wanted_level


## Идёт ли сейчас проверка груза.
func is_inspecting() -> bool:
	return _state == State.INSPECTING


## Идёт ли отсчёт на торможение (машина влетела быстрее 20 км/ч).
func is_grace_active() -> bool:
	return _state == State.GRACE


## Текущее состояние КПП (см. enum State).
func get_state() -> State:
	return _state


# --- Въезд и выезд из зоны проверки ----------------------------------------


func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as BaseVehicle
	if vehicle == null:
		return
	if _state == State.ARRESTED or _state == State.CHASE or _chase_active:
		return
	if vehicle == _passed_vehicle:
		return
	if _vehicle != null and _vehicle != vehicle:
		return

	_vehicle = vehicle
	var speed := _speed_kmh(vehicle)

	if speed > chase_speed_kmh:
		_begin_grace(vehicle)
	elif speed <= inspection_speed_kmh:
		_begin_inspection(vehicle)
	else:
		_begin_waiting(vehicle)


func _on_body_exited(body: Node3D) -> void:
	var vehicle := body as BaseVehicle
	if vehicle == null:
		return

	if vehicle == _passed_vehicle:
		_passed_vehicle = null

	if vehicle != _vehicle:
		return

	match _state:
		State.WAITING, State.GRACE, State.INSPECTING:
			# Уехал, так и не пройдя проверку.
			_release_frozen_vehicle()
			_start_chase(vehicle, true)
		State.CLEAN:
			_state = State.IDLE
		State.CHASE, State.ARRESTED:
			pass
		_:
			_state = State.IDLE

	_vehicle = null


# --- Требование остановиться ------------------------------------------------


## Машина едет 5–20 км/ч: просим остановиться.
func _begin_waiting(vehicle: BaseVehicle) -> void:
	_state = State.WAITING
	_show_banner(
		"ОСТАНОВИТЕСЬ ДЛЯ ПРОВЕРКИ",
		"Сбросьте скорость ниже %d км/ч и остановитесь." % int(inspection_speed_kmh),
		COLOR_STOP
	)


## Машина влетела быстрее 20 км/ч: даём grace_period секунд на торможение.
func _begin_grace(vehicle: BaseVehicle) -> void:
	_state = State.GRACE
	_grace_left = grace_period
	_show_banner(
		"ОСТАНОВИТЕСЬ! ПОЛИЦИЯ!",
		"У вас %d сек., чтобы остановиться." % int(ceil(grace_period)),
		COLOR_ALERT
	)
	_progress.visible = true
	_progress.value = 0.0
	if _police_car != null:
		_police_car.set_siren(true)


func _update_grace(delta: float) -> void:
	if not _has_vehicle():
		_state = State.IDLE
		_hide_banner()
		return

	if _speed_kmh(_vehicle) <= inspection_speed_kmh:
		# Успели затормозить — переходим к обычной проверке.
		_begin_inspection(_vehicle)
		return

	_grace_left = maxf(_grace_left - delta, 0.0)
	_progress.value = 1.0 - _grace_left / maxf(grace_period, 0.001)

	if _grace_left <= 0.0:
		_start_chase(_vehicle, false)


func _update_waiting() -> void:
	if not _has_vehicle():
		_state = State.IDLE
		return

	var speed := _speed_kmh(_vehicle)
	if speed > chase_speed_kmh:
		_begin_grace(_vehicle)
	elif speed <= inspection_speed_kmh:
		_begin_inspection(_vehicle)


# --- Проверка груза ---------------------------------------------------------


func _begin_inspection(vehicle: BaseVehicle) -> void:
	_state = State.INSPECTING
	_inspection_left = inspection_duration
	_progress.value = 0.0
	_show_banner(
		"ПРОВЕРКА ГРУЗА...",
		"Оставайтесь на месте: %d сек." % int(ceil(inspection_duration)),
		COLOR_INFO
	)
	if hold_vehicle_during_inspection:
		_freeze_vehicle(vehicle)
	# Машина остановилась — сирена больше не нужна.
	if _police_car != null:
		_police_car.set_siren(false)
	inspection_started.emit(vehicle)


func _update_inspection(delta: float) -> void:
	if not _has_vehicle():
		_release_frozen_vehicle()
		_state = State.IDLE
		_hide_banner()
		return

	var speed := _speed_kmh(_vehicle)
	if speed > chase_speed_kmh:
		_start_chase(_vehicle, false)
		return

	if speed > inspection_speed_kmh:
		# Машина покатилась — проверка начинается заново.
		_inspection_left = inspection_duration
		_progress.value = 0.0
		_show_banner(
			"ОСТАНОВИТЕСЬ ДЛЯ ПРОВЕРКИ",
			"Машина должна остановиться.",
			COLOR_STOP
		)
		return

	_inspection_left = maxf(_inspection_left - delta, 0.0)
	_progress.value = 1.0 - _inspection_left / maxf(inspection_duration, 0.001)

	if _inspection_left <= 0.0:
		_complete_inspection()


func _complete_inspection() -> void:
	var vehicle := _vehicle
	var clean := not _has_contraband(vehicle)
	inspection_finished.emit(vehicle, clean)

	if clean:
		_pass_inspection(vehicle)
	else:
		_arrest(vehicle)


func _pass_inspection(vehicle: BaseVehicle) -> void:
	_release_frozen_vehicle()
	_state = State.CLEAN
	_passed_vehicle = vehicle
	_show_banner(
		"ВСЁ ЧИСТО, ПРОЕЗЖАЙТЕ.",
		"Уровень розыска: %d" % _wanted_level,
		COLOR_CLEAR
	)
	_banner_timer = message_duration
	if _police_car != null:
		_police_car.set_siren(false)


func _arrest(vehicle: BaseVehicle) -> void:
	_state = State.ARRESTED
	_chase_active = false
	_wanted_level = maxi(_wanted_level, arrest_wanted_level)
	_show_banner(
		"КОНТРАБАНДА ОБНАРУЖЕНА!",
		"ВЫ АРЕСТОВАНЫ.",
		COLOR_ALERT
	)
	if _police_car != null:
		_police_car.stop_chase()
		_police_car.set_siren(true)
	player_arrested.emit(vehicle, _wanted_level)

	if not game_over_enabled:
		# Без экрана «Арестован» игрок может уехать, но остаётся в розыске.
		_release_frozen_vehicle()
		_banner_timer = message_duration
		return

	# Пауза перед экраном: игрок успевает прочитать, за что его взяли.
	await get_tree().create_timer(arrest_delay, true, false, true).timeout
	if not is_inside_tree():
		return
	_show_game_over("АРЕСТОВАН", "Вас арестовали за перевозку контрабанды.")


# --- Погоня -----------------------------------------------------------------


## evasion = true, если игрок уехал из зоны, не пройдя проверку.
func _start_chase(vehicle: BaseVehicle, evasion: bool = false) -> void:
	if _state == State.CHASE or _state == State.ARRESTED:
		return

	_release_frozen_vehicle()
	_state = State.CHASE
	_wanted_level = maxi(_wanted_level, chase_wanted_level)

	if evasion:
		_show_banner(
			"УКЛОНЕНИЕ ОТ ПРОВЕРКИ!",
			"Вы уехали с поста, не пройдя проверку. Уровень розыска: %d" % _wanted_level,
			COLOR_ALERT
		)
		evasion_started.emit(vehicle, _wanted_level)
	else:
		_show_banner(
			"ПОЛИЦЕЙСКАЯ ПОГОНЯ!",
			"Вы проскочили пост. Уровень розыска: %d" % _wanted_level,
			COLOR_ALERT
		)
	_banner_timer = message_duration
	_chase_active = true
	var police_car := _resolve_police_car()
	if police_car != null:
		# Единственная машина КПП выезжает на перехват — новых машин не спавним.
		police_car.start_chase(vehicle)
	chase_started.emit(vehicle, _wanted_level)

	if chase_ends_in_game_over:
		await get_tree().create_timer(arrest_delay, true, false, true).timeout
		if not is_inside_tree():
			return
		_show_game_over("АРЕСТОВАН", "Вы скрылись с полицейского поста.")


## Патрульная машина догнала игрока (сигнал PoliceCar.player_caught).
func _on_player_caught(vehicle: Node3D) -> void:
	if _state == State.ARRESTED:
		return

	var caught_vehicle := vehicle as BaseVehicle
	_state = State.ARRESTED
	_chase_active = false
	_wanted_level = maxi(_wanted_level, arrest_wanted_level)
	_show_banner(
		"ВАС ЗАДЕРЖАЛИ!",
		"Патрульная машина остановила вас. Уровень розыска: %d" % _wanted_level,
		COLOR_ALERT
	)
	if _police_car != null:
		_police_car.stop_chase()
		_police_car.set_siren(true)
	player_arrested.emit(caught_vehicle, _wanted_level)

	if not game_over_enabled:
		_banner_timer = message_duration
		return

	await get_tree().create_timer(arrest_delay, true, false, true).timeout
	if not is_inside_tree():
		return
	_show_game_over("АРЕСТОВАН", "Полицейская машина догнала вас на дороге.")


# --- Проверка груза ---------------------------------------------------------


func _has_contraband(vehicle: BaseVehicle) -> bool:
	if _cargo_system == null or not is_instance_valid(_cargo_system):
		_cargo_system = get_tree().get_first_node_in_group("cargo_system") as CargoSystem
	if _cargo_system == null:
		return false
	return _cargo_system.has_contraband(vehicle)


# --- Заморозка машины на время проверки ------------------------------------


func _freeze_vehicle(vehicle: BaseVehicle) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if _frozen_vehicle == vehicle:
		return
	_release_frozen_vehicle()

	_frozen_vehicle = vehicle
	_frozen_was_frozen = vehicle.freeze
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.freeze = true


func _release_frozen_vehicle() -> void:
	if _frozen_vehicle != null and is_instance_valid(_frozen_vehicle):
		_frozen_vehicle.freeze = _frozen_was_frozen
	_frozen_vehicle = null


# --- HUD --------------------------------------------------------------------


func _show_banner(title: String, subtitle: String, color: Color) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_subtitle.text = subtitle
	_banner.visible = true
	_progress.visible = _state in [State.INSPECTING, State.GRACE]
	if _state == State.INSPECTING:
		_progress.value = 0.0


func _hide_banner() -> void:
	_banner.visible = false


func _show_game_over(title: String, text: String) -> void:
	_game_over_title.text = title
	_game_over_text.text = text
	_game_over.visible = true
	_banner.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_restart_button.grab_focus()
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()


# --- Помощники --------------------------------------------------------------


## Найти припаркованную машину КПП (единственную в сцене — новых не спавним).
## Вызывается при старте погони, поэтому машина гарантированно уже в дереве.
func _resolve_police_car() -> PoliceCar:
	if _police_car != null and is_instance_valid(_police_car):
		return _police_car
	_police_car = get_node_or_null("PoliceCar") as PoliceCar
	if _police_car != null and not _police_car.player_caught.is_connected(_on_player_caught):
		_police_car.player_caught.connect(_on_player_caught)
	return _police_car


func _has_vehicle() -> bool:
	return _vehicle != null and is_instance_valid(_vehicle)


func _speed_kmh(vehicle: BaseVehicle) -> float:
	return vehicle.linear_velocity.length() * 3.6
