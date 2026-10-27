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
const CRATE_SIZE := 0.68
const STOP_SPEED := 1.5
const LOAD_TIME := 1.2
const UNLOAD_TIME := 1.0
const CARGO_VALUE := 150

## Зона погрузки: настил весов перед погрузочным доком.
@export var load_zone_center: Vector3 = Vector3(14.0, 0.0, 99.6)
@export var load_zone_radius: float = 6.0
## Зона разгрузки: жёлтая площадка перед воротами склада.
@export var unload_zone_center: Vector3 = Vector3(29.0, 0.0, 111.0)
@export var unload_zone_radius: float = 5.0
@export var load_time_per_crate: float = LOAD_TIME
@export var unload_time_per_crate: float = UNLOAD_TIME
@export var cargo_value: int = CARGO_VALUE

var _loaded: int = 0
var _money: int = 0
var _delivered: int = 0
var _load_progress: float = 0.0
var _unload_progress: float = 0.0
var _message: String = ""
var _message_timer: float = 0.0

var _crate_owner: Node3D = null
var _crate_nodes: Array[Node3D] = []
var _status_label: Label = null
var _hint_label: Label = null

var _crate_mat: StandardMaterial3D
var _slat_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("cargo_system")
	_create_materials()
	_create_hud()


func _create_materials() -> void:
	_crate_mat = StandardMaterial3D.new()
	_crate_mat.albedo_color = Color(0.53, 0.40, 0.24)
	_crate_mat.roughness = 0.9

	_slat_mat = StandardMaterial3D.new()
	_slat_mat.albedo_color = Color(0.30, 0.22, 0.13)
	_slat_mat.roughness = 0.95


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


func _slot_position(index: int) -> Vector3:
	var row: int = int(index / 2.0)
	var column: int = index % 2
	return Vector3(
		-0.55 + float(column) * 1.1,
		1.38,
		0.95 + float(row) * 0.75
	)


func _make_crate() -> Node3D:
	var root := Node3D.new()

	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CRATE_SIZE, CRATE_SIZE, CRATE_SIZE)
	box.mesh = mesh
	box.material_override = _crate_mat
	root.add_child(box)

	for y in [-0.3, 0.3]:
		var slat := MeshInstance3D.new()
		var slat_mesh := BoxMesh.new()
		slat_mesh.size = Vector3(CRATE_SIZE * 1.02, 0.07, CRATE_SIZE * 1.02)
		slat.mesh = slat_mesh
		slat.position = Vector3(0.0, y * CRATE_SIZE, 0.0)
		slat.material_override = _slat_mat
		root.add_child(slat)

	return root


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
