extends Node3D
## Перестановка деревьев прямо в игре.
##
## Управление (пешком):
##   F            — взять дерево под прицелом / поставить его на землю
##   Колесо мыши  — повернуть дерево вокруг оси (шаг 15°)
##   ПКМ          — отменить и вернуть дерево на прежнее место
##
## Пока дерево «в руках», его коллизия отключена, а на земле виден
## зелёный маркер точки установки. Раскладка сохраняется в
## user://tree_layout.cfg и восстанавливается при следующем запуске.

## Дальность наведения на ствол, м.
@export var reach: float = 7.0
## Дальность установки дерева от камеры, м.
@export var place_range: float = 16.0
## Шаг поворота колесом мыши, градусы.
@export var rotation_step_degrees: float = 15.0
## Цвет маркера установки.
@export var marker_color: Color = Color(0.35, 0.95, 0.45, 0.5)

var _player = null
var _vegetation = null
var _marker: MeshInstance3D = null

var _carried_id: int = -1
var _carry_origin: Vector3 = Vector3.ZERO
var _yaw_offset: float = 0.0
var _preview_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_vegetation = get_tree().get_first_node_in_group("vegetation")
	_create_marker()


func _create_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = "TreePlacementMarker"

	var disc := CylinderMesh.new()
	disc.top_radius = 1.35
	disc.bottom_radius = 1.35
	disc.height = 0.03
	disc.radial_segments = 28
	disc.rings = 1
	_marker.mesh = disc

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = marker_color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


func _process(_delta: float) -> void:
	if _player == null or _vegetation == null:
		return

	if _player.is_driving():
		if _carried_id >= 0:
			_cancel_carry()
		_marker.visible = false
		_clear_hint()
		return

	if _carried_id >= 0:
		_update_carry()
		_player.set_hint_override(
			"[F] Поставить   [Колесо] Поворот   [ПКМ] Отмена"
		)
		return

	var tree_id := _tree_under_crosshair()
	if tree_id >= 0:
		_player.set_hint_override("[F] Переставить дерево")
		var pos: Vector3 = _vegetation.get_tree_position(tree_id)
		_marker.visible = true
		_marker.global_position = pos + Vector3.UP * 0.07
	else:
		_marker.visible = false
		_player.clear_hint_override()


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _vegetation == null:
		return
	if _player.is_driving():
		return

	if _carried_id >= 0:
		if event.is_action_pressed("move_tree"):
			_place_tree()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_yaw_offset += deg_to_rad(rotation_step_degrees)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_yaw_offset -= deg_to_rad(rotation_step_degrees)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_carry()
				get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_tree"):
		_try_grab()
		get_viewport().set_input_as_handled()


func _try_grab() -> void:
	var tree_id := _tree_under_crosshair()
	if tree_id < 0:
		return

	_carried_id = tree_id
	_carry_origin = _vegetation.get_tree_position(tree_id)
	_yaw_offset = 0.0
	_preview_pos = _carry_origin
	_vegetation.set_tree_ghost(tree_id, true)
	_marker.visible = true
	_marker.global_position = _preview_pos + Vector3.UP * 0.07


func _update_carry() -> void:
	var hit := _raycast(place_range)
	if not hit.is_empty():
		_preview_pos = hit.position

	# Не ставим дерево вплотную к игроку, иначе ствол «запирает» его.
	var player_pos: Vector3 = _player.global_position
	var from_player := Vector2(
		_preview_pos.x - player_pos.x,
		_preview_pos.z - player_pos.z
	)
	if from_player.length() < 1.8:
		if from_player.length() < 0.01:
			from_player = Vector2(0.0, -1.0)
		from_player = from_player.normalized() * 1.8
		_preview_pos = Vector3(
			player_pos.x + from_player.x,
			_preview_pos.y,
			player_pos.z + from_player.y
		)

	var yaw: float = _camera_yaw() + _yaw_offset
	_vegetation.move_tree(_carried_id, _preview_pos, yaw, true)
	_marker.global_position = _preview_pos + Vector3.UP * 0.07


func _place_tree() -> void:
	if _carried_id < 0:
		return
	_vegetation.move_tree(
		_carried_id, _preview_pos, _camera_yaw() + _yaw_offset, true
	)
	_vegetation.set_tree_ghost(_carried_id, false)
	_vegetation.save_layout()
	_carried_id = -1
	_marker.visible = false
	_player.clear_hint_override()


func _cancel_carry() -> void:
	if _carried_id < 0:
		return
	_vegetation.set_tree_ghost(_carried_id, false)
	_vegetation.move_tree(_carried_id, _carry_origin, 0.0, false)
	_carried_id = -1
	_marker.visible = false
	_clear_hint()


func _tree_under_crosshair() -> int:
	if _vegetation == null:
		return -1
	var hit := _raycast(reach)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	return _vegetation.tree_id_for_collider(collider)


func _camera_yaw() -> float:
	var cam: Camera3D = _player.get_camera()
	if cam == null:
		return _player.global_rotation.y
	return cam.global_rotation.y


func _raycast(distance: float) -> Dictionary:
	var cam: Camera3D = _player.get_camera()
	if cam == null or not cam.current:
		return {}
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_transform.basis.z * distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


func _clear_hint() -> void:
	if _player != null and _player.has_method("clear_hint_override"):
		_player.clear_hint_override()
