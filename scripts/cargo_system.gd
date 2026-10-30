class_name CargoSystem
extends Node3D
## Логистика: ручная погрузка в кузов и сдача груза в ДВУХ зонах разгрузки.

const CAPACITY := 6
const CARGO_VALUE := 150

const CRATE_SCENE: PackedScene = preload(
	"res://assets/models/wooden_box/woodbox.glb"
)
const CRATE_SCALE := 1
const CRATE_BOTTOM_LOCAL := -0.030735
const BED_FLOOR_Y := 0.86
const BED_CENTER_Z := 1.66
const CRATE_VISUAL_SIZE := 0.615
const CRATE_GAP := 0.05
const CRATE_ROW_SPACING := CRATE_VISUAL_SIZE + CRATE_GAP
const CRATE_COLUMN_X := (CRATE_VISUAL_SIZE + CRATE_GAP) * 0.5

const LAYER_WORLD := 1
const LAYER_INTERACTION := 2

class SlotState:
	var occupant: Node3D = null
	var mass: float = 0.0
	func clear() -> void:
		occupant = null
		mass = 0.0

@export_group("Зона разгрузки 1 (TRUCK BAY 1)")
## Центр первой зоны (обязательно поменяй Y на уровень земли в инспекторе!)
@export var unload_zone_1_center: Vector3 = Vector3.ZERO
@export var unload_zone_1_radius: float = 4.0

@export_group("Зона разгрузки 2 (TRUCK BAY 2)")
## Центр второй зоны (обязательно поменяй Y на уровень земли в инспекторе!)
@export var unload_zone_2_center: Vector3 = Vector3.ZERO
@export var unload_zone_2_radius: float = 4.0

@export_range(1.0, 500.0, 1.0) var cargo_box_mass: float = 75.0
@export var cargo_value: int = CARGO_VALUE

var _money: int = 0
var _delivered: int = 0
var _unload_zones: Array[Area3D] = []
var _crate_owner: VehicleBody3D = null
var _loaded_boxes: Array[Node3D] = []
var _vehicle_states: Dictionary = {}

var _status_label: Label = null
var _hint_label: Label = null
var _message: String = ""
var _message_timer: float = 0.0
var _hud_timer: float = 0.0
var _startup_safe_timer: float = 1.0 


func _ready() -> void:
	add_to_group("cargo_system")
	
	# Если координаты не заданы, ставим их по умолчанию (замени на свои!)
	if unload_zone_1_center == Vector3.ZERO:
		unload_zone_1_center = Vector3(RuralHeight.BASE_CENTER.x + 2.0, -6.5, RuralHeight.BASE_CENTER.y + 13.0)
	if unload_zone_2_center == Vector3.ZERO:
		unload_zone_2_center = Vector3(RuralHeight.BASE_CENTER.x + 8.0, -6.5, RuralHeight.BASE_CENTER.y + 13.0)
		
	_create_unload_zone(unload_zone_1_center, unload_zone_1_radius, "Zone1")
	_create_unload_zone(unload_zone_2_center, unload_zone_2_radius, "Zone2")
	_create_hud()


## Создает физическую зону И визуальный круг на земле.
func _create_unload_zone(center: Vector3, radius: float, zone_name: String) -> void:
	var area = Area3D.new()
	area.name = zone_name
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF 
	area.monitoring = true
	area.monitorable = true
	
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0 
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	
	# --- ВИЗУАЛЬНАЯ ЧАСТЬ ---
	var mesh_instance := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius
	cyl_mesh.height = 0.1 
	mesh_instance.mesh = cyl_mesh
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.4) # Желтый, полупрозрачный
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	
	area.add_child(mesh_instance)
	area.position = center
	
	# Сохраняем данные о радиусе и центре в самой зоне для быстрой проверки
	area.set_meta("radius", radius)
	area.set_meta("center", center)
	
	area.body_entered.connect(_on_unload_zone_entered)
	area.area_entered.connect(_on_unload_zone_area_entered)
	
	add_child(area)
	_unload_zones.append(area)


func _on_unload_zone_entered(body: Node3D) -> void:
	if _startup_safe_timer <= 0.0:
		_try_deliver_box(body)

func _on_unload_zone_area_entered(area: Area3D) -> void:
	if _startup_safe_timer <= 0.0:
		_try_deliver_box(area)

func _process(delta: float) -> void:
	if _startup_safe_timer > 0.0:
		_startup_safe_timer -= delta

	_message_timer = maxf(_message_timer - delta, 0.0)
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.2
		_update_hud()
		if _startup_safe_timer <= 0.0:
			_check_zone_for_boxes()

func _check_zone_for_boxes() -> void:
	for box in get_tree().get_nodes_in_group("cargo_box"):
		if is_instance_valid(box) and box is Node3D:
			# Проверяем расстояние до каждой из двух зон
			for area in _unload_zones:
				var center: Vector3 = area.get_meta("center")
				var radius: float = area.get_meta("radius")
				if box.global_position.distance_to(center) <= radius:
					_try_deliver_box(box)
					break


func _try_deliver_box(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is VehicleBody3D or node is CharacterBody3D:
		return
		
	# ГЛАВНОЕ ИСПРАВЛЕНИЕ: Если ящик все еще в машине (зарегистрирован), мы его НЕ ТРОГАЕМ.
	# Он должен быть сначала выгружен игроком (тогда метаданные удалятся).
	if is_box_registered(node):
		return

	var is_box := false
	if node.is_in_group("cargo_box") or node.has_meta("cargo_mass"):
		is_box = true
	elif node.name.begins_with("CargoBox") or node.name.begins_with("CargoPallet") or node.name.begins_with("woodbox"):
		is_box = true
		
	if is_box:
		if node.has_meta("sold_for_money"):
			return
		node.set_meta("sold_for_money", true)
		
		_money += cargo_value
		_delivered += 1
		_message = "Отгружено: +$%d" % cargo_value
		_message_timer = 2.0
		print("Ящик сдан! +", cargo_value, "$ (Всего: ", _money, "$)")
		node.queue_free()
		_update_hud()


# --- HUD (Интерфейс) --------------------------------------------------------

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CargoHUD"
	add_child(layer)
	_status_label = Label.new()
	_status_label.offset_left = 24.0
	_status_label.offset_top = 16.0
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86, 0.95))
	_status_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	_status_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_status_label)

	_hint_label = Label.new()
	_hint_label.offset_left = 24.0
	_hint_label.offset_top = 54.0
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.66, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	_hint_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hint_label)
	_update_hud()


func _update_hud() -> void:
	if _status_label == null or _hint_label == null:
		return
	if _crate_owner == null or not is_instance_valid(_crate_owner):
		_crate_owner = _find_nearest_vehicle_to_player()

	var loaded := 0
	if _crate_owner != null:
		loaded = get_loaded_count(_crate_owner)

	var heading := "СКЛАД  •  груз %d/%d" % [loaded, CAPACITY]
	if _message_timer > 0.0 and not _message.is_empty():
		heading = _message
	_status_label.text = heading

	var hint := "Доставлено: %d   •   $%d\nВыгрузите ящики руками в желтые круги." % [_delivered, _money]
	if _crate_owner != null:
		if loaded >= CAPACITY:
			hint = "Кузов полон. Выгружайте ящики в желтые зоны."
		elif loaded > 0:
			hint = "Доставлено: %d   •   $%d\nВ кузове %d ящиков." % [_delivered, _money, loaded]
	_hint_label.text = hint


func _find_nearest_vehicle_to_player() -> VehicleBody3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): return null
	var player = players[0] as Node3D
	if player == null: return null
	var best_vehicle: VehicleBody3D = null
	var best_dist := 100.0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v is VehicleBody3D:
			var dist = player.global_position.distance_to(v.global_position)
			if dist < best_dist:
				best_dist = dist
				best_vehicle = v
	return best_vehicle


# --- Сетка и регистрация ящиков --------------------------------------------

func get_slot_count() -> int: return CAPACITY

func get_slot_local_position(index: int) -> Vector3:
	if index < 0 or index >= CAPACITY: return Vector3.ZERO
	var row: int = int(index / 2.0)
	var column: int = index % 2
	return Vector3(
		-CRATE_COLUMN_X + float(column) * CRATE_COLUMN_X * 2.0,
		BED_FLOOR_Y - CRATE_BOTTOM_LOCAL * CRATE_SCALE,
		BED_CENTER_Z + (float(row) - 1.0) * CRATE_ROW_SPACING
	)

func get_slot_world_position(vehicle: Node3D, index: int) -> Vector3:
	if vehicle == null: return Vector3.ZERO
	return vehicle.to_global(get_slot_local_position(index))

func get_slot_world_transform(vehicle: Node3D, index: int, yaw_offset: float = 0.0) -> Transform3D:
	if vehicle == null: return Transform3D()
	var basis := vehicle.global_transform.basis.orthonormalized()
	if not is_zero_approx(yaw_offset):
		basis = basis * Basis(Vector3.UP, yaw_offset)
	return Transform3D(basis, get_slot_world_position(vehicle, index))

func is_slot_occupied(vehicle: Node3D, index: int) -> bool:
	return get_slot_occupant(vehicle, index) != null

func get_slot_occupant(vehicle: Node3D, index: int) -> Node3D:
	var state := _get_state(vehicle, false)
	if state.is_empty(): return null
	var slots: Array = state["slots"]
	if index < 0 or index >= slots.size(): return null
	var slot := slots[index] as SlotState
	return slot.occupant if slot != null else null

func find_nearest_slot(vehicle: Node3D, world_point: Vector3, only_empty: bool = false) -> int:
	if vehicle == null: return -1
	var best := -1
	var best_distance := INF
	for i in CAPACITY:
		if only_empty and is_slot_occupied(vehicle, i): continue
		var distance := get_slot_world_position(vehicle, i).distance_squared_to(world_point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best

func find_nearest_empty_slot(vehicle: Node3D, world_point: Vector3) -> int:
	return find_nearest_slot(vehicle, world_point, true)

func get_loaded_count(vehicle: Node3D) -> int:
	var state := _get_state(vehicle, false)
	if state.is_empty(): return 0
	var count := 0
	for slot in state["slots"]:
		if slot != null and slot.occupant != null: count += 1
	return count

func get_capacity() -> int: return CAPACITY

func register_box(vehicle: VehicleBody3D, box: Node3D, slot_index: int, yaw_offset: float = 0.0) -> bool:
	if vehicle == null or box == null or slot_index < 0 or slot_index >= CAPACITY: return false
	var state := _get_state(vehicle, true)
	var slots: Array = state["slots"]
	var slot := slots[slot_index] as SlotState
	if slot == null or (slot.occupant != null and slot.occupant != box): return false

	if box.has_meta("cargo_vehicle") and box.has_meta("cargo_slot"):
		var old_vehicle: Node = box.get_meta("cargo_vehicle")
		var old_slot: int = int(box.get_meta("cargo_slot"))
		if is_instance_valid(old_vehicle) and (old_vehicle != vehicle or old_slot != slot_index):
			_unregister_box_internal(box)
			state = _get_state(vehicle, true)
			slots = state["slots"]
			slot = slots[slot_index] as SlotState
			if slot == null or (slot.occupant != null and slot.occupant != box): return false

	var mass := cargo_box_mass
	var custom_mass: Variant = box.get("cargo_mass")
	if custom_mass != null: mass = float(custom_mass)

	slot.occupant = box
	slot.mass = mass
	box.set_meta("cargo_vehicle", vehicle)
	box.set_meta("cargo_slot", slot_index)
	box.set_meta("cargo_mass", mass)
	box.set_meta("cargo_yaw", yaw_offset)
	_track_box(box)
	_apply_cargo_mass(vehicle)
	_crate_owner = vehicle
	_update_hud()
	return true

func unregister_box(box: Node3D) -> bool:
	return _unregister_box_internal(box)

func _unregister_box_internal(box: Node3D) -> bool:
	if box == null or not box.has_meta("cargo_vehicle") or not box.has_meta("cargo_slot"): return false
	var vehicle: Node = box.get_meta("cargo_vehicle")
	var slot_index: int = int(box.get_meta("cargo_slot"))
	box.remove_meta("cargo_vehicle")
	box.remove_meta("cargo_slot")
	box.remove_meta("cargo_mass")
	box.remove_meta("cargo_yaw")
	_untrack_box(box)
	if not is_instance_valid(vehicle): return false
	var state := _get_state(vehicle, false)
	if state.is_empty(): return false
	var slots: Array = state["slots"]
	if slot_index < 0 or slot_index >= slots.size(): return false
	var slot := slots[slot_index] as SlotState
	if slot != null and slot.occupant == box: slot.clear()
	_apply_cargo_mass(vehicle)
	_update_hud()
	return true

func is_box_registered(box: Node3D) -> bool:
	return box != null and box.has_meta("cargo_vehicle") and box.has_meta("cargo_slot")

func _get_state(vehicle: Node3D, create: bool) -> Dictionary:
	if vehicle == null or not is_instance_valid(vehicle): return {}
	if _vehicle_states.has(vehicle): return _vehicle_states[vehicle]
	if not create: return {}
	var slots: Array = []
	slots.resize(CAPACITY)
	for i in CAPACITY: slots[i] = SlotState.new()
	var state := { "slots": slots, "base_mass": float(vehicle.get("mass")) }
	_vehicle_states[vehicle] = state
	_ensure_cargo_area(vehicle)
	return state

func _apply_cargo_mass(vehicle: Node3D) -> void:
	if vehicle == null or not is_instance_valid(vehicle): return
	var state := _get_state(vehicle, true)
	var total := 0.0
	for slot in state["slots"]:
		if slot != null and slot.occupant != null: total += slot.mass
	var base_mass: float = float(state.get("base_mass", 0.0))
	if base_mass <= 0.0:
		base_mass = float(vehicle.get("mass")) - total
		state["base_mass"] = base_mass
	vehicle.set("mass", base_mass + total)

func _ensure_cargo_area(vehicle: Node3D) -> void:
	if vehicle == null or vehicle.get_node_or_null("CargoArea") != null: return
	var area := Area3D.new()
	area.name = "CargoArea"
	area.collision_layer = LAYER_INTERACTION
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group("cargo_area")
	area.set_meta("cargo_vehicle", vehicle)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 1.0, 2.0) 
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position = Vector3(0.0, 1.46, BED_CENTER_Z)
	area.add_child(collision)
	vehicle.add_child(area)

func _track_box(box: Node3D) -> void:
	if box == null or not is_instance_valid(box): return
	_prune_loaded_boxes()
	if not _loaded_boxes.has(box): _loaded_boxes.append(box)

func _untrack_box(box: Node3D) -> void:
	if box == null: return
	_loaded_boxes.erase(box)

func _prune_loaded_boxes() -> void:
	for i in range(_loaded_boxes.size() - 1, -1, -1):
		if not is_instance_valid(_loaded_boxes[i]): _loaded_boxes.remove_at(i)
