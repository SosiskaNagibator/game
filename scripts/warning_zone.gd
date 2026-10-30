class_name PoliceWarningZone
extends Area3D
## Зона предупреждения о посте ДПС.
##
## Отдельная сцена: ставится на дорогу перед КПП как обычный узел.
## Положение, поворот и размер коробки задаются в редакторе, о полицейской
## машине зона ничего не знает.
##
## При въезде машины показывает крупное сообщение на 4 секунды. Повторно
## сообщение не показывается, пока не пройдёт cooldown — чтобы игрок,
## катаясь туда-сюда через зону, не получал его каждый раз.

signal warning_shown(vehicle: Node3D)

## Текст предупреждения.
@export_multiline var message: String = "ВПЕРЕДИ ПОСТ ПОЛИЦИИ! СБРОСЬТЕ СКОРОСТЬ"
## Сколько секунд висит сообщение.
@export_range(0.5, 10.0, 0.5) var display_time: float = 4.0
## Пауза между показами, секунды. 0 — показывать при каждом въезде.
@export_range(0.0, 120.0, 1.0) var cooldown: float = 20.0
## Показать только один раз за заезд.
@export var show_once: bool = false

var _time_left: float = 0.0
var _last_shown_ms: int = -10000000
## Одноразовый режим: сообщение ещё не показывали.
var _armed: bool = true

@onready var _panel: Control = %Warning
@onready var _label: Label = %WarningLabel


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_label.text = message
	_hide()


func _process(delta: float) -> void:
	if _time_left > 0.0:
		_time_left = maxf(_time_left - delta, 0.0)
		if _time_left <= 0.0:
			_hide()


# --- Публичный API ----------------------------------------------------------


## Висит ли сообщение прямо сейчас.
func is_message_visible() -> bool:
	return _panel.visible


## Показать сообщение вручную (например, из скрипта сюжета).
func show_warning() -> void:
	_armed = false
	_last_shown_ms = Time.get_ticks_msec()
	_label.text = message
	_time_left = display_time
	_panel.visible = true


## Сбросить кулдаун — следующая машина снова увидит предупреждение.
func reset_cooldown() -> void:
	_armed = true
	_last_shown_ms = -10000000
	_hide()


# --- Въезд в зону -----------------------------------------------------------


func _on_body_entered(body: Node3D) -> void:
	# Ящики и прочий реквизит тоже лежат на слое 1 — реагируем только на машину.
	if not body is BaseVehicle:
		return
	if not _can_show():
		return
	show_warning()
	warning_shown.emit(body)


func _can_show() -> bool:
	if show_once:
		return _armed
	if cooldown > 0.0:
		var elapsed := (Time.get_ticks_msec() - _last_shown_ms) * 0.001
		if elapsed < cooldown:
			return false
	return true


func _hide() -> void:
	_time_left = 0.0
	_panel.visible = false
