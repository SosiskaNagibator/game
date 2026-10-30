class_name PoliceCar
extends StaticBody3D
## Припаркованная полицейская машина КПП.
##
## Машина не является транспортом: это статичное препятствие на обочине.
## Скрипт только включает проблесковые маячки, когда КПП начинает погоню
## или арест. Без сигнала маячки выключены и ничего не стоят по кадрам.

@export_group("Маячки")
## Горит ли сирена прямо сейчас.
@export var siren_enabled: bool = false
## Частота переключения красный/синий, Гц.
@export_range(0.5, 8.0, 0.1) var flash_rate: float = 2.6
## Яркость горящего маячка.
@export_range(0.5, 20.0, 0.1) var light_energy: float = 5.0
@export var red_light_color: Color = Color(1.0, 0.10, 0.06, 1.0)
@export var blue_light_color: Color = Color(0.12, 0.28, 1.0, 1.0)

var _phase: float = 0.0

@onready var _red_light: OmniLight3D = %RedLight
@onready var _blue_light: OmniLight3D = %BlueLight


func _ready() -> void:
	_red_light.light_color = red_light_color
	_blue_light.light_color = blue_light_color
	_apply_siren(false)
	set_process(siren_enabled)


func _process(delta: float) -> void:
	_phase += delta * flash_rate
	# Полный цикл: красный -> пауза -> синий -> пауза.
	var step: int = int(_phase) % 2
	_red_light.light_energy = light_energy if step == 0 else 0.0
	_blue_light.light_energy = light_energy if step == 1 else 0.0


## Включить/выключить сирену. Вызывается из checkpoint.gd.
func set_siren(on: bool) -> void:
	if siren_enabled == on:
		return
	siren_enabled = on
	_phase = 0.0
	set_process(on)
	_apply_siren(on)


func is_siren_on() -> bool:
	return siren_enabled


func _apply_siren(on: bool) -> void:
	if not on:
		_red_light.light_energy = 0.0
		_blue_light.light_energy = 0.0
