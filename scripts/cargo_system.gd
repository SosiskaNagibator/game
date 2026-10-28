extends Node3D
## Логистика базы Hollow Creek: погрузка и разгрузка.
##
## * Подъезжаете к доку (юго-запад базы), останавливаетесь — паллеты
##   сами переезжают из склада в кузов пикапа (до 6 штук).
## * Везёте груз к воротам склада, встаёте в жёлтую зону разгрузки —
##   паллеты уходят, а на счёт капают деньги.
## * Счётчики и подсказки видны в HUD слева сверху.
##
## Зоны совпадают с разметкой из farmstead.gd.

const CAPACITY := 6
const STOP_SPEED := 1.5
const LOAD_TIME := 1.2
const UNLOAD_TIME := 1.0
const CARGO_VALUE := 150

## Модель ящика (2.195 м в оригинале) и раскладка в кузове пикапа.
const CRATE_SCENE: PackedScene = preload(
	"res://assets/models/wooden_box/low_poly_wooden_box.glb"
)
const CRATE_SCALE := 0.28
## Нижняя грань модели в её локальных координатах (пивот у центра по X/Z).
const CRATE_BOTTOM_LOCAL := -0.1098
const BED_FLOOR_Y := 0.86
const BED_CENTER_Z := 1.66
const CRATE_ROW_SPACING := 0.64
const CRATE_COLUMN_X := 0.33

## Зона погрузки: настил весов перед погрузочным доком.
## Ноль — взять позицию от площадки скрытой базы.
@export var load_zone_center: Vector3 = Vector3.ZERO
@export var load_zone_radius: float = 6.0
## Зона разгрузки: жёлтая площадка перед воротами склада.
@export var unload_zone_center: Vector3 = Vector3.ZERO
@export var unload_zone_radius: float = 5.0
@export var load_time_per_crate: float = LOAD_TIME
@export var unload_time_per_crate: float = UNLOAD_TIME
@export var cargo_value: int = CARGO_VALUE
## Масса одного ящика, кг. Каждый погруженный ящик увеличивает массу машины.
@export_range(1.0, 500.0, 1.0) var cargo_box_mass: float = 75.0

var _loaded: int = 0
var _money: int = 0
var _delivered: int = 0
var _load_progress: float = 0.0
var _unload_progress: float = 0.0
var _message: String = ""
var _message_timer: float = 0.0

var _crate_owner: Node3D = null
var _crate_nodes: Array[Node3D] = []
## Масса машины без груза, чтобы всегда возвращаться к ней при разгрузке.
var _base_vehicle_mass: float = 0.0
var _status_label: Label = null
var _hint_label: Label = null


func _ready() -> void:
	add_to_group("cargo_system")
	if load_zone_center == Vector3.ZERO:
		load_zone_center = Vector3(
			RuralHeight.BASE_CENTER.x - 11.0, 0.0, RuralHeight.BASE_CENTER.y + 1.6
		)
	if unload_zone_center == Vector3.ZERO:
		unload_zone_center = Vector3(
			RuralHeight.BASE_CENTER.x + 4.0, 0.0, RuralHeight.BASE_CENTER.y + 13.0
		)
	_create_hud()


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CargoHUD"
	add_child(layer)

	_status_label = Label.new()
	_status_label.name = "CargoStatus"
	_status_label.anchor_left = 0.0
	_status_label.anchor_top = 0.0
	_status_label.anchor_right = 0.0
	_status_label.anchor_bottom = 0.0
	_status_label.offset_left = 24.0
	_status_label.offset_top = 16.0
	_status_label.offset_right = 640.0
	_status_label.offset_bottom = 56.0
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86, 0.95))
	_status_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	_status_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_status_label)

	_hint_label = Label.new()
	_hint_label.name = "CargoHint"
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_top = 0.0
	_hint_label.anchor_right = 0.0
	_hint_label.anchor_bottom = 0.0
	_hint_label.offset_left = 24.0
	_hint_label.offset_top = 54.0
	_hint_label.offset_right = 620.0
	_hint_label.offset_bottom = 118.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.66, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	_hint_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hint_label)

	_update_hud(false, false)


func _process(delta: float) -> void:
	_message_timer = maxf(_message_timer - delta, 0.0)

	if _crate_owner != null and not is_instance_valid(_crate_owner):
		_crate_owner = null
		_crate_nodes.clear()
		_loaded = 0

	var load_vehicle := _vehicle_in_zone(load_zone_center, load_zone_radius)
	var unload_vehicle: VehicleBody3D = null
	if load_vehicle == null:
		unload_vehicle = _vehicle_in_zone(unload_zone_center, unload_zone_radius)

	var focus: VehicleBody3D = load_vehicle if load_vehicle != null else unload_vehicle
	if focus != null and _crate_owner == null:
		_bind_vehicle(focus)

	var busy := false

	if (
		load_vehicle != null
		and _crate_owner == load_vehicle
		and _loaded < CAPACITY
		and _is_stopped(load_vehicle)
	):
		busy = true
		_load_progress += delta
		if _load_progress >= load_time_per_crate:
			_load_progress -= load_time_per_crate
			_loaded += 1
			_apply_cargo_mass()
			_apply_crate_visibility()
			if _loaded >= CAPACITY:
				_message = "Погрузка завершена"
				_message_timer = 2.0

	elif (
		unload_vehicle != null
		and _crate_owner == unload_vehicle
		and _loaded > 0
		and _is_stopped(unload_vehicle)
	):
		busy = true
		_unload_progress += delta
		if _unload_progress >= unload_time_per_crate:
			_unload_progress -= unload_time_per_crate
			_loaded -= 1
			_apply_cargo_mass()
			_apply_crate_visibility()
			_money += cargo_value
			_delivered += 1
			_message = "Отгружено: +$%d" % cargo_value
			_message_timer = 1.6

	if not busy:
		_load_progress = move_toward(_load_progress, 0.0, delta * 3.0)
		_unload_progress = move_toward(_unload_progress, 0.0, delta * 3.0)

	_update_hud(load_vehicle != null, unload_vehicle != null)


func _vehicle_in_zone(center: Vector3, radius: float) -> VehicleBody3D:
	for node in get_tree().get_nodes_in_group("vehicles"):
		if node is not VehicleBody3D:
			continue
		var vehicle: VehicleBody3D = node
		var offset := Vector2(
			vehicle.global_position.x - center.x,
			vehicle.global_position.z - center.z
		)
		if offset.length() <= radius:
			return vehicle
	return null


func _is_stopped(vehicle: VehicleBody3D) -> bool:
	return vehicle.linear_velocity.length() < STOP_SPEED


# --- Груз в кузове ---------------------------------------------------------


func _bind_vehicle(vehicle: VehicleBody3D) -> void:
	_crate_owner = vehicle
	# Запоминаем снаряжённую массу машины: груз всегда считается поверх неё.
	_base_vehicle_mass = vehicle.mass
	for node in _crate_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_crate_nodes.clear()

	for i in CAPACITY:
		var crate := _make_crate()
		crate.name = "CargoPallet_%d" % i
		vehicle.add_child(crate)
		crate.position = _slot_position(i)
		crate.visible = i < _loaded
		_crate_nodes.append(crate)

	_apply_cargo_mass()


func _slot_position(index: int) -> Vector3:
	var row: int = int(index / 2.0)
	var column: int = index % 2
	return Vector3(
		-CRATE_COLUMN_X + float(column) * CRATE_COLUMN_X * 2.0,
		BED_FLOOR_Y - CRATE_BOTTOM_LOCAL * CRATE_SCALE,
		BED_CENTER_Z + (float(row) - 1.0) * CRATE_ROW_SPACING
	)


func _make_crate() -> Node3D:
	var crate := CRATE_SCENE.instantiate() as Node3D
	crate.scale = Vector3.ONE * CRATE_SCALE
	return crate


## Масса машины = снаряжённая масса + масса всех погруженных ящиков.
func _apply_cargo_mass() -> void:
	if _crate_owner == null or not is_instance_valid(_crate_owner):
		return
	var vehicle := _crate_owner as VehicleBody3D
	if vehicle == null:
		return
	vehicle.mass = _base_vehicle_mass + float(_loaded) * cargo_box_mass


func _apply_crate_visibility() -> void:
	for i in _crate_nodes.size():
		_crate_nodes[i].visible = i < _loaded


func _update_hud(at_load: bool, at_unload: bool) -> void:
	if _status_label == null or _hint_label == null:
		return

	var heading := "СКЛАД  •  груз %d/%d" % [_loaded, CAPACITY]
	if _message_timer > 0.0 and not _message.is_empty():
		heading = _message
	_status_label.text = heading

	var load_time: float = maxf(load_time_per_crate, 0.1)
	var unload_time: float = maxf(unload_time_per_crate, 0.1)
	var stopped := _crate_owner != null and _is_stopped(_crate_owner)
	var hint: String = "Погрузка — док на юго-западе, разгрузка — площадка у ворот склада."

	if at_load:
		if _loaded >= CAPACITY:
			hint = "Кузов полон. Везите груз к воротам склада."
		elif not stopped:
			hint = "Остановите грузовик у дока для погрузки."
		else:
			hint = "Погрузка… %d%%" % int(_load_progress / load_time * 100.0)
	elif at_unload:
		if _loaded <= 0:
			hint = "Сначала загрузите паллеты на доке."
		elif not stopped:
			hint = "Остановите грузовик в зоне разгрузки."
		else:
			hint = "Разгрузка… %d%%" % int(_unload_progress / unload_time * 100.0)

	_hint_label.text = "Доставлено: %d   •   $%d\n%s" % [_delivered, _money, hint]
