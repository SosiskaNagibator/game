class_name CargoSystem
extends Node3D
## Логистика базы Hollow Creek: погрузка и разгрузка.
##
## * Подъезжаете к доку (юго-запад базы), останавливаетесь — паллеты
##   сами переезжают из склада в кузов пикапа (до 6 штук).
## * Везёте груз к воротам склада, встаёте в жёлтую зону разгрузки —
##   паллеты уходят, а на счёт капают деньги.
## * Ящики можно также брать и ставить вручную (player.gd): сетка кузова
##   общая для автоматической и ручной погрузки.
## * Счётчики и подсказки видны в HUD слева сверху.
##
## Зоны совпадают с разметкой из farmstead.gd.

const CAPACITY := 6
const STOP_SPEED := 1.5
const LOAD_TIME := 1.2
const UNLOAD_TIME := 1.0
const CARGO_VALUE := 150

## Модель ящика и раскладка в кузове пикапа.
## woodbox.glb — реальный куб ~0.615 м (локальный AABB меша раздут,
## поэтому размер берём по вершинам, а не по AABB).
const CRATE_SCENE: PackedScene = preload(
	"res://assets/models/wooden_box/woodbox.glb"
)
const CRATE_SCALE := 1.0
## Реальная ширина куба в метрах при CRATE_SCALE = 1.0.
const CRATE_VISUAL_SIZE := 0.6147
## Зазор между ящиками, чтобы они не слипались визуально.
const CRATE_GAP := 0.025
## Нижняя грань модели в её локальных координатах (пивот у центра по X/Z).
const CRATE_BOTTOM_LOCAL := -0.030735
const BED_FLOOR_Y := 0.86
const BED_CENTER_Z := 1.66
## Шаг сетки — по фактической ширине ящика, а не по раздутому AABB.
const CRATE_ROW_SPACING := CRATE_VISUAL_SIZE + CRATE_GAP
const CRATE_COLUMN_X := (CRATE_VISUAL_SIZE + CRATE_GAP) * 0.5

## Слой обычной физики и слой «только для наведения» (ящики в кузове).
## Игрок наводится лучом с маской 1 | 2.
const LAYER_WORLD := 1
const LAYER_INTERACTION := 2

## Состояние одного слота кузова.
class SlotState:
	var occupant: Node3D = null
	var mass: float = 0.0
	var automatic: bool = false

	func clear() -> void:
		occupant = null
		mass = 0.0
		automatic = false


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
@export_group("Контрабанда")
## Тестовый режим: контрабандой считается любой груз в кузове.
## Выключите, когда понадобится проверять флаг CargoBox.is_contraband.
@export var contraband_test_mode: bool = true

var _loaded: int = 0
var _money: int = 0
var _delivered: int = 0
var _load_progress: float = 0.0
var _unload_progress: float = 0.0
var _message: String = ""
var _message_timer: float = 0.0

## Машина, которую сейчас показывает HUD и обслуживает док.
var _crate_owner: VehicleBody3D = null
## Все ящики, стоящие в кузовах прямо сейчас (по всем машинам).
## Слоты хранят раскладку, а этот список — быстрый доступ к самим ящикам:
## по нему считается контрабанда и он же чистится при разгрузке.
var _loaded_boxes: Array[Node3D] = []
## Состояние каждого кузова: { "slots": Array[SlotState], "base_mass": float }.
var _vehicle_states: Dictionary = {}
var _status_label: Label = null
var _hint_label: Label = null
## HUD перерисовываем 10 раз в секунду: текст меняется медленно, а layout — дорогой.
var _hud_timer: float = 0.0


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
		_loaded = 0

	var load_vehicle := _vehicle_in_zone(load_zone_center, load_zone_radius)
	var unload_vehicle: VehicleBody3D = null
	if load_vehicle == null:
		unload_vehicle = _vehicle_in_zone(unload_zone_center, unload_zone_radius)

	var focus: VehicleBody3D = load_vehicle if load_vehicle != null else unload_vehicle
	if focus != null and focus != _crate_owner:
		_bind_vehicle(focus)

	if _crate_owner != null:
		_loaded = get_loaded_count(_crate_owner)

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
			var slot := _find_first_empty_slot(load_vehicle)
			if slot >= 0:
				_add_auto_crate(load_vehicle, slot)
			_loaded = get_loaded_count(load_vehicle)
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
			var slot := _find_last_occupied_slot(unload_vehicle)
			if slot >= 0:
				_remove_slot_occupant(unload_vehicle, slot)
			_loaded = get_loaded_count(unload_vehicle)
			_money += cargo_value
			_delivered += 1
			_message = "Отгружено: +$%d" % cargo_value
			_message_timer = 1.6

	if not busy:
		_load_progress = move_toward(_load_progress, 0.0, delta * 3.0)
		_unload_progress = move_toward(_unload_progress, 0.0, delta * 3.0)

	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
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


# --- Публичный API сетки кузова --------------------------------------------


## Сколько всего слотов в кузове.
func get_slot_count() -> int:
	return CAPACITY


## Позиция слота в локальных координатах машины.
## Индексы: 0..5, по два столбца на ряд (X), ряды идут по Z.
func get_slot_local_position(index: int) -> Vector3:
	if index < 0 or index >= CAPACITY:
		return Vector3.ZERO
	var row: int = int(index / 2.0)
	var column: int = index % 2
	return Vector3(
		-CRATE_COLUMN_X + float(column) * CRATE_COLUMN_X * 2.0,
		BED_FLOOR_Y - CRATE_BOTTOM_LOCAL * CRATE_SCALE,
		BED_CENTER_Z + (float(row) - 1.0) * CRATE_ROW_SPACING
	)


## Позиция слота в мировых координатах.
func get_slot_world_position(vehicle: Node3D, index: int) -> Vector3:
	if vehicle == null:
		return Vector3.ZERO
	return vehicle.to_global(get_slot_local_position(index))


## Полный трансформ для установки ящика: позиция слота + поворот кузова
## (и дополнительный поворот ящика вокруг вертикали).
func get_slot_world_transform(
	vehicle: Node3D, index: int, yaw_offset: float = 0.0
) -> Transform3D:
	if vehicle == null:
		return Transform3D()
	var basis := vehicle.global_transform.basis.orthonormalized()
	if not is_zero_approx(yaw_offset):
		basis = basis * Basis(Vector3.UP, yaw_offset)
	return Transform3D(basis, get_slot_world_position(vehicle, index))


## Занят ли слот. vehicle == null — слот свободен.
func is_slot_occupied(vehicle: Node3D, index: int) -> bool:
	return get_slot_occupant(vehicle, index) != null


## Кто стоит в слоте (ящик игрока или автоматическая паллета).
func get_slot_occupant(vehicle: Node3D, index: int) -> Node3D:
	var state := _get_state(vehicle, false)
	if state.is_empty():
		return null
	var slots: Array = state["slots"]
	if index < 0 or index >= slots.size():
		return null
	var slot := slots[index] as SlotState
	return slot.occupant if slot != null else null


## Ближайший слот к точке. only_empty = true — искать только свободный.
func find_nearest_slot(
	vehicle: Node3D, world_point: Vector3, only_empty: bool = false
) -> int:
	if vehicle == null:
		return -1
	var best := -1
	var best_distance := INF
	for i in CAPACITY:
		if only_empty and is_slot_occupied(vehicle, i):
			continue
		var distance := get_slot_world_position(vehicle, i).distance_squared_to(world_point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Ближайший свободный слот. -1 — кузов полон.
func find_nearest_empty_slot(vehicle: Node3D, world_point: Vector3) -> int:
	return find_nearest_slot(vehicle, world_point, true)


## Сколько слотов занято. Без аргумента — для машины, которую обслуживает HUD.
func get_loaded_count(vehicle: Node3D = null) -> int:
	if vehicle == null:
		return _loaded
	var state := _get_state(vehicle, false)
	if state.is_empty():
		return 0
	var count := 0
	for slot in state["slots"]:
		if slot != null and slot.occupant != null:
			count += 1
	return count


func get_capacity() -> int:
	return CAPACITY


## Зарегистрировать ящик в слоте: занять слот, обновить массу машины и счётчик.
## Вызывается из player.gd после того, как ящик уже поставлен в слот.
func register_box(
	vehicle: VehicleBody3D, box: Node3D, slot_index: int, yaw_offset: float = 0.0
) -> bool:
	if vehicle == null or box == null:
		return false
	if slot_index < 0 or slot_index >= CAPACITY:
		return false

	var state := _get_state(vehicle, true)
	var slots: Array = state["slots"]
	var slot := slots[slot_index] as SlotState
	if slot == null:
		return false
	if slot.occupant != null and slot.occupant != box:
		return false

	# Если ящик уже стоял в другом кузове/слоте — сначала освобождаем его.
	if box.has_meta("cargo_vehicle") and box.has_meta("cargo_slot"):
		var old_vehicle: Node = box.get_meta("cargo_vehicle")
		var old_slot: int = int(box.get_meta("cargo_slot"))
		if is_instance_valid(old_vehicle) and (old_vehicle != vehicle or old_slot != slot_index):
			_unregister_box_internal(box, false)
			state = _get_state(vehicle, true)
			slots = state["slots"]
			slot = slots[slot_index] as SlotState
			if slot == null or (slot.occupant != null and slot.occupant != box):
				return false

	var mass := cargo_box_mass
	var custom_mass: Variant = box.get("cargo_mass")
	if custom_mass != null:
		mass = float(custom_mass)

	slot.occupant = box
	slot.mass = mass
	slot.automatic = false
	box.set_meta("cargo_vehicle", vehicle)
	box.set_meta("cargo_slot", slot_index)
	box.set_meta("cargo_mass", mass)
	box.set_meta("cargo_yaw", yaw_offset)
	_track_box(box)

	_apply_cargo_mass(vehicle)
	if _crate_owner == null:
		_crate_owner = vehicle
	if _crate_owner == vehicle:
		_loaded = get_loaded_count(vehicle)
	return true


## Снять ящик с учёта: освободить слот, уменьшить массу машины и счётчик.
## Вызывается из player.gd при подборе ящика из кузова.
func unregister_box(box: Node3D) -> bool:
	return _unregister_box_internal(box, true)


func _unregister_box_internal(box: Node3D, update_focus: bool) -> bool:
	if box == null:
		return false
	if not box.has_meta("cargo_vehicle") or not box.has_meta("cargo_slot"):
		return false

	var vehicle: Node = box.get_meta("cargo_vehicle")
	var slot_index: int = int(box.get_meta("cargo_slot"))
	box.remove_meta("cargo_vehicle")
	box.remove_meta("cargo_slot")
	box.remove_meta("cargo_mass")
	box.remove_meta("cargo_yaw")
	_untrack_box(box)

	if not is_instance_valid(vehicle):
		return false
	var state := _get_state(vehicle, false)
	if state.is_empty():
		return false
	var slots: Array = state["slots"]
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot := slots[slot_index] as SlotState
	if slot != null and slot.occupant == box:
		slot.clear()

	_apply_cargo_mass(vehicle)
	if update_focus and _crate_owner == vehicle:
		_loaded = get_loaded_count(vehicle)
	return true


func is_box_registered(box: Node3D) -> bool:
	return (
		box != null
		and box.has_meta("cargo_vehicle")
		and box.has_meta("cargo_slot")
	)


# --- Контрабанда ------------------------------------------------------------


## Есть ли в кузовах контрабандный груз.
##
## Пока включён contraband_test_mode, контрабандой считается любой
## загруженный ящик — это удобно для проверки КПП. Позже достаточно
## выключить режим в Инспекторе: тогда проверяются флаги CargoBox.is_contraband.
## vehicle == null — проверить все машины; иначе — только указанную.
func has_contraband(vehicle: Node3D = null) -> bool:
	if contraband_test_mode:
		return get_cargo_count(vehicle) > 0
	return has_flagged_contraband(vehicle)


## Контрабанда по флагам CargoBox.is_contraband (уточнённая проверка).
func has_flagged_contraband(vehicle: Node3D = null) -> bool:
	if vehicle != null:
		var state := _get_state(vehicle, false)
		if state.is_empty():
			return false
		for slot in state["slots"]:
			if slot == null or slot.occupant == null:
				continue
			if slot.occupant.get("is_contraband") == true:
				return true
		return false

	_prune_loaded_boxes()
	for box in _loaded_boxes:
		if box == null or not is_instance_valid(box):
			continue
		# get() безопасен и для автоматических паллет: у них нет свойства,
		# вернётся null, то есть «не контрабанда».
		if box.get("is_contraband") == true:
			return true
	return false


## Сколько контрабандных ящиков сейчас в кузовах.
func get_contraband_count(vehicle: Node3D = null) -> int:
	if contraband_test_mode:
		return get_cargo_count(vehicle)

	var count := 0
	if vehicle != null:
		var state := _get_state(vehicle, false)
		if state.is_empty():
			return 0
		for slot in state["slots"]:
			if slot != null and slot.occupant != null:
				if slot.occupant.get("is_contraband") == true:
					count += 1
		return count

	_prune_loaded_boxes()
	for box in _loaded_boxes:
		if box != null and is_instance_valid(box) and box.get("is_contraband") == true:
			count += 1
	return count


## Сколько ящиков загружено. vehicle == null — по всем машинам сразу.
func get_cargo_count(vehicle: Node3D = null) -> int:
	if vehicle == null:
		_prune_loaded_boxes()
		return _loaded_boxes.size()
	return get_loaded_count(vehicle)


## Копия списка загруженных ящиков (по всем машинам).
func get_loaded_boxes() -> Array[Node3D]:
	_prune_loaded_boxes()
	var result: Array[Node3D] = []
	result.assign(_loaded_boxes)
	return result


func _track_box(box: Node3D) -> void:
	if box == null or not is_instance_valid(box):
		return
	_prune_loaded_boxes()
	if not _loaded_boxes.has(box):
		_loaded_boxes.append(box)


func _untrack_box(box: Node3D) -> void:
	if box == null:
		return
	_loaded_boxes.erase(box)


## Убираем ссылки на уже удалённые узлы, чтобы список не копил мусор.
func _prune_loaded_boxes() -> void:
	for i in range(_loaded_boxes.size() - 1, -1, -1):
		if not is_instance_valid(_loaded_boxes[i]):
			_loaded_boxes.remove_at(i)


# --- Внутреннее состояние кузова -------------------------------------------


func _bind_vehicle(vehicle: VehicleBody3D) -> void:
	_crate_owner = vehicle
	_get_state(vehicle, true)
	_ensure_cargo_area(vehicle)
	_loaded = get_loaded_count(vehicle)


## Возвращает (и при create=true создаёт) состояние кузова.
func _get_state(vehicle: Node3D, create: bool) -> Dictionary:
	if vehicle == null or not is_instance_valid(vehicle):
		return {}
	if _vehicle_states.has(vehicle):
		return _vehicle_states[vehicle]
	if not create:
		return {}

	var slots: Array = []
	slots.resize(CAPACITY)
	for i in CAPACITY:
		slots[i] = SlotState.new()

	var state := {
		"slots": slots,
		"base_mass": float(vehicle.get("mass")),
	}
	_vehicle_states[vehicle] = state
	return state


## Масса машины = снаряжённая масса + масса всех ящиков в слотах.
func _apply_cargo_mass(vehicle: Node3D) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var state := _get_state(vehicle, true)
	var total := 0.0
	for slot in state["slots"]:
		if slot != null and slot.occupant != null:
			total += slot.mass
	var base_mass: float = float(state.get("base_mass", 0.0))
	if base_mass <= 0.0:
		base_mass = float(vehicle.get("mass")) - total
		state["base_mass"] = base_mass
	vehicle.set("mass", base_mass + total)


func _find_first_empty_slot(vehicle: Node3D) -> int:
	for i in CAPACITY:
		if not is_slot_occupied(vehicle, i):
			return i
	return -1


func _find_last_occupied_slot(vehicle: Node3D) -> int:
	for i in range(CAPACITY - 1, -1, -1):
		if is_slot_occupied(vehicle, i):
			return i
	return -1


func _add_auto_crate(vehicle: VehicleBody3D, slot_index: int) -> void:
	var state := _get_state(vehicle, true)
	var slots: Array = state["slots"]
	var slot := slots[slot_index] as SlotState
	if slot == null or slot.occupant != null:
		return

	var crate := _make_crate()
	crate.name = "CargoPallet_%d" % slot_index
	vehicle.add_child(crate)
	crate.position = get_slot_local_position(slot_index)

	slot.occupant = crate
	slot.mass = cargo_box_mass
	slot.automatic = true
	_track_box(crate)
	_apply_cargo_mass(vehicle)


func _remove_slot_occupant(vehicle: VehicleBody3D, slot_index: int) -> void:
	var state := _get_state(vehicle, false)
	if state.is_empty():
		return
	var slots: Array = state["slots"]
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot := slots[slot_index] as SlotState
	if slot == null or slot.occupant == null:
		return

	var node := slot.occupant
	# Ручной ящик мог быть зарегистрирован: снимаем метаданные, чтобы
	# масса и счётчик не задвоились при queue_free.
	node.remove_meta("cargo_vehicle")
	node.remove_meta("cargo_slot")
	node.remove_meta("cargo_mass")
	node.remove_meta("cargo_yaw")
	slot.clear()
	_untrack_box(node)

	if is_instance_valid(node):
		node.queue_free()
	_apply_cargo_mass(vehicle)


## Гарантируем, что у машины есть Area3D кузова для наведения игрока.
## В BaseVehicle.tscn она уже есть; это запасной вариант для других сцен.
func _ensure_cargo_area(vehicle: Node3D) -> void:
	if vehicle == null or vehicle.get_node_or_null("CargoArea") != null:
		return

	var area := Area3D.new()
	area.name = "CargoArea"
	area.collision_layer = LAYER_INTERACTION
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group("cargo_area")
	area.set_meta("cargo_vehicle", vehicle)

	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.2, 2.3)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position = Vector3(0.0, 1.46, BED_CENTER_Z)
	area.add_child(collision)
	vehicle.add_child(area)


func _make_crate() -> Node3D:
	var crate := CRATE_SCENE.instantiate() as Node3D
	crate.scale = Vector3.ONE * CRATE_SCALE
	return crate


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
