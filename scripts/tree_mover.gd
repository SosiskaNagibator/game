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
##
## Редактор ландшафта (пешком, клавиша B):
##   B            — открыть / закрыть редактор
##   1…4          — дерево, куст, камень, цветы
##   ЛКМ          — поставить объект под курсором
##   Колесо мыши  — повернуть объект (шаг 15°)
##   Delete       — режим удаления (ЛКМ по объекту)
##   WASD         — ходить, Q/E — повернуть вид
##   B / Esc      — закрыть редактор
##
## Поставленные объекты сохраняются в user://landscape_props.cfg.

## Дальность наведения на ствол, м.
@export var reach: float = 7.0
## Дальность установки дерева от камеры, м.
@export var place_range: float = 16.0
## Дальность луча в редакторе ландшафта, м.
@export var editor_range: float = 60.0
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

const PLACED_LAYOUT_PATH := "user://landscape_props.cfg"
const PROP_NAMES := ["Дерево", "Куст", "Камень", "Цветы"]

var _editing_landscape := false
var _delete_mode := false
var _selected_prop := 0
var _editor_ui: CanvasLayer
var _editor_panel: PanelContainer
var _editor_title: Label
var _editor_hint: Label
var _delete_button: Button
var _prop_buttons: Array[Button] = []
var _prop_button_group := ButtonGroup.new()
var _preview_prop: Node3D
var _placed_props: Array[Dictionary] = []
## Кэш наведения: луч дорогой, проверяем его 10 раз в секунду.
var _hover_tree_id: int = -1
var _hover_timer: float = 0.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_vegetation = get_tree().get_first_node_in_group("vegetation")
	_create_marker()
	_create_editor_ui()
	_load_placed_props()


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


func _process(delta: float) -> void:
	if _player == null or _vegetation == null:
		return

	_editor_hint.visible = not _editing_landscape and not _player.is_driving()

	if _editing_landscape:
		_turn_view(delta)
		_update_landscape_preview()
		return

	if _player.is_driving():
		if _carried_id >= 0:
			_cancel_carry()
		_hover_tree_id = -1
		_marker.visible = false
		_clear_hint()
		return

	if _carried_id >= 0:
		_update_carry()
		_player.set_hint_override(
			"[F] Поставить   [Колесо] Поворот   [ПКМ] Отмена"
		)
		return

	# Луч наведения пересчитываем ~10 раз в секунду: за это время прицел
	# не успевает заметно сдвинуться, а physics-запросов становится в 6 раз меньше.
	_hover_timer -= delta
	if _hover_timer <= 0.0:
		_hover_timer = 0.1
		_hover_tree_id = _tree_under_crosshair()

	var tree_id := _hover_tree_id
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

	if event.is_action_pressed("toggle_landscape_editor"):
		if _player.is_driving():
			return
		_toggle_landscape_editor()
		get_viewport().set_input_as_handled()
		return

	if _editing_landscape:
		_handle_landscape_input(event)
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
	return _vegetation.tree_id_for_collider(collider, int(hit.get("shape", -1)))


func _camera_yaw() -> float:
	var cam: Camera3D = _player.get_camera()
	if cam == null:
		return _player.global_rotation.y
	return cam.global_rotation.y


func _raycast(distance: float, surface_only: bool = false) -> Dictionary:
	var cam: Camera3D = _player.get_camera()
	if cam == null or not cam.current:
		return {}
	var from: Vector3
	var direction: Vector3
	if _editing_landscape:
		var mouse_pos := get_viewport().get_mouse_position()
		from = cam.project_ray_origin(mouse_pos)
		direction = cam.project_ray_normal(mouse_pos)
	else:
		from = cam.global_position
		direction = -cam.global_transform.basis.z
	var to: Vector3 = from + direction * distance
	var exclude: Array[RID] = [_player.get_rid()]
	for _attempt in 24:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.collider as CollisionObject3D
		if collider == null:
			return hit
		if not surface_only or collider.has_meta("terrain_ground"):
			return hit
		exclude.append(collider.get_rid())
	return {}


func _clear_hint() -> void:
	if _player != null and _player.has_method("clear_hint_override"):
		_player.clear_hint_override()


func _create_editor_ui() -> void:
	_editor_ui = CanvasLayer.new()
	_editor_ui.name = "LandscapeEditorUI"
	_editor_ui.layer = 10
	add_child(_editor_ui)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -352.0
	panel.offset_right = -24.0
	panel.offset_top = 96.0
	panel.offset_bottom = 96.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.custom_minimum_size = Vector2(328.0, 0.0)
	panel.visible = false
	_editor_ui.add_child(panel)
	_editor_panel = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = "Редактор ландшафта"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)

	var select_row := HBoxContainer.new()
	select_row.add_theme_constant_override("separation", 4)
	column.add_child(select_row)
	for i in PROP_NAMES.size():
		var button := Button.new()
		button.text = PROP_NAMES[i]
		button.custom_minimum_size = Vector2(70.0, 34.0) # 4 кнопки в ряд
		button.toggle_mode = true
		button.button_group = _prop_button_group
		button.button_pressed = i == _selected_prop
		button.pressed.connect(_select_prop.bind(i))
		select_row.add_child(button)
		_prop_buttons.append(button)

	var delete_button := Button.new()
	delete_button.text = "Удалить объекты  (Del)"
	delete_button.toggle_mode = true
	delete_button.toggled.connect(_set_delete_mode)
	column.add_child(delete_button)
	_delete_button = delete_button

	_editor_title = Label.new()
	column.add_child(_editor_title)

	var controls := Label.new()
	controls.add_theme_font_size_override("font_size", 13)
	controls.modulate = Color(1.0, 1.0, 1.0, 0.72)
	controls.text = "WASD — ходить, Q/E — повернуть вид\nЛКМ — поставить, колесо — повернуть\n1-4 — выбрать, Del — удалять"
	column.add_child(controls)

	var close_button := Button.new()
	close_button.text = "Готово  (B / Esc)"
	close_button.pressed.connect(_close_landscape_editor)
	column.add_child(close_button)
	_update_editor_title()

	# Постоянная подсказка внизу слева: как открыть редактор.
	_editor_hint = Label.new()
	_editor_hint.anchor_top = 1.0
	_editor_hint.anchor_bottom = 1.0
	_editor_hint.offset_left = 24.0
	_editor_hint.offset_top = -54.0
	_editor_hint.offset_right = 320.0
	_editor_hint.offset_bottom = -26.0
	_editor_hint.add_theme_font_size_override("font_size", 16)
	_editor_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	_editor_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_editor_hint.add_theme_constant_override("outline_size", 4)
	_editor_hint.text = "[B] Редактор ландшафта"
	_editor_ui.add_child(_editor_hint)


func _toggle_landscape_editor() -> void:
	if _editing_landscape:
		_close_landscape_editor()
	else:
		_open_landscape_editor()


func _open_landscape_editor() -> void:
	if _carried_id >= 0:
		_cancel_carry()
	_editing_landscape = true
	_editor_panel.visible = true
	_place_preview()
	_player.set_landscape_editing(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_editor_title()


func _close_landscape_editor() -> void:
	_editing_landscape = false
	_delete_mode = false
	if _delete_button != null:
		_delete_button.set_pressed_no_signal(false)
	_editor_panel.visible = false
	_preview_prop.visible = false
	_marker.visible = false
	_player.set_landscape_editing(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_clear_hint()


func _select_prop(index: int) -> void:
	_selected_prop = clampi(index, 0, PROP_NAMES.size() - 1)
	_delete_mode = false
	if _delete_button != null:
		_delete_button.set_pressed_no_signal(false)
	if _selected_prop < _prop_buttons.size():
		_prop_buttons[_selected_prop].set_pressed_no_signal(true)
	var old_preview := _preview_prop
	_preview_prop = _add_placed_prop(_selected_prop, Vector3.ZERO, 0.0, true)
	if old_preview != null:
		old_preview.queue_free()
	_preview_prop.visible = false
	_update_editor_title()


func _set_delete_mode(enabled: bool) -> void:
	_delete_mode = enabled
	if _delete_button != null:
		_delete_button.set_pressed_no_signal(enabled)
	_preview_prop.visible = not enabled
	_update_editor_title()


func _update_landscape_preview() -> void:
	# Курсор над панелью — предпросмотр не двигаем, чтобы объект не прыгал.
	if _editor_panel != null and _editor_panel.visible:
		if _editor_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
			_preview_prop.visible = false
			_marker.visible = false
			return

	if _delete_mode:
		_preview_prop.visible = false
		var target: Node = _placed_root_from_hit(_raycast(editor_range))
		_marker.visible = target != null
		if target != null:
			_marker.global_position = target.global_position + Vector3.UP * 0.06
		return

	# Луч проходит сквозь кусты, заборы и постройки и упирается в землю.
	var hit := _raycast(editor_range, true)
	if hit.is_empty():
		_preview_prop.visible = false
		_marker.visible = false
		marker_color = Color(0.95, 0.3, 0.25, 0.55)
		_update_marker_color()
		_update_editor_title(false)
		return

	_preview_pos = hit.position
	var player_pos: Vector3 = _player.global_position
	var delta := Vector2(_preview_pos.x - player_pos.x, _preview_pos.z - player_pos.z)
	if delta.length() < 1.8:
		if delta.length() < 0.01:
			delta = Vector2(0.0, -1.0)
		delta = delta.normalized() * 1.8
		_preview_pos.x = player_pos.x + delta.x
		_preview_pos.z = player_pos.z + delta.y
	_preview_pos.y = RuralHeight.terrain_height(_preview_pos.x, _preview_pos.z)

	var valid := _valid_prop_position(_preview_pos, _selected_prop)
	_preview_prop.visible = true
	_preview_prop.global_position = _preview_pos
	_preview_prop.rotation.y = _yaw_offset
	marker_color = Color(0.35, 0.95, 0.45, 0.5) if valid else Color(0.95, 0.3, 0.25, 0.55)
	_update_marker_color()
	_marker.visible = true
	_marker.global_position = _preview_pos + Vector3.UP * 0.04
	_update_editor_title(valid)


## Поворот вида в редакторе: мышь занята установкой объектов.
func _turn_view(delta: float) -> void:
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		turn -= 1.0
	if turn != 0.0:
		_player.rotate_y(turn * 1.9 * delta)


func _handle_landscape_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Физические клавиши: работают и на русской раскладке.
		var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_ESCAPE:
			_close_landscape_editor()
			get_viewport().set_input_as_handled()
			return
		if key >= KEY_1 and key <= KEY_4:
			_select_prop(key - KEY_1)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_DELETE:
			_set_delete_mode(not _delete_mode)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_yaw_offset += deg_to_rad(rotation_step_degrees)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_yaw_offset -= deg_to_rad(rotation_step_degrees)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _delete_mode:
				_delete_prop_under_crosshair()
			else:
				_place_selected_prop()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_close_landscape_editor()
			get_viewport().set_input_as_handled()


func _valid_prop_position(pos: Vector3, kind: int) -> bool:
	if absf(pos.x) > RuralHeight.WORLD_HALF - 4.0 or absf(pos.z) > RuralHeight.WORLD_HALF - 4.0:
		return false
	var road_distance: float = RuralHeight.road_distance(pos.x, pos.z)
	var road_half: float = RuralHeight.road_half_width(pos.x, pos.z)
	# Дорога и её обочины должны оставаться свободными.
	if road_distance < road_half + (1.4 if kind != 2 else 1.0):
		return false
	# Деревья и кусты не сажаем вплотную к колее.
	if kind <= 1 and road_distance < road_half + 2.8:
		return false
	# Внутри двора базы стоят постройки — ставить туда что-либо нельзя.
	if RuralHeight.yard_mask(pos.x, pos.z) > 0.78:
		return false
	return true


func _place_selected_prop() -> void:
	if not _valid_prop_position(_preview_pos, _selected_prop):
		return
	_add_placed_prop(_selected_prop, _preview_pos, _yaw_offset, false)
	_save_placed_props()


func _add_placed_prop(kind: int, pos: Vector3, yaw: float, preview: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "LandscapePropPreview" if preview else "LandscapeProp_%d" % _placed_props.size()
	pos.y = RuralHeight.terrain_height(pos.x, pos.z)
	root.position = pos
	root.rotation.y = yaw
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("landscape_prop", true)
	root.add_child(body)
	_add_prop_visuals(root, kind, preview)
	var collision := CollisionShape3D.new()
	if kind == 0:
		var shape := CylinderShape3D.new()
		shape.radius = 0.62
		shape.height = 3.8
		collision.shape = shape
		collision.position.y = 1.9
	elif kind == 1:
		var shape := SphereShape3D.new()
		shape.radius = 0.8
		collision.shape = shape
		collision.position.y = 0.55
	elif kind == 2:
		var shape := SphereShape3D.new()
		shape.radius = 0.7
		collision.shape = shape
		collision.position.y = 0.45
	else:
		var shape := SphereShape3D.new()
		shape.radius = 0.45
		collision.shape = shape
		collision.position.y = 0.35
	body.add_child(collision)
	add_child(root)
	if preview:
		body.collision_layer = 0
	else:
		_placed_props.append({"node": root, "kind": kind, "pos": root.position, "yaw": yaw})
	return root


func _add_prop_visuals(root: Node3D, kind: int, ghost: bool) -> void:
	var bark := _prop_material(Color(0.29, 0.18, 0.10), ghost)
	var leaf := _prop_material(Color(0.22, 0.40, 0.12), ghost)
	var rock := _prop_material(Color(0.39, 0.40, 0.35), ghost)
	var flower := _prop_material(Color(0.78, 0.53, 0.32), ghost)
	if kind == 0:
		_add_mesh(root, _cylinder_mesh(0.18, 0.25, 3.0, 7), Vector3(0.0, 1.5, 0.0), Vector3.ONE, bark)
		_add_mesh(root, _sphere_mesh(1.0, 7, 4), Vector3(0.0, 3.15, 0.0), Vector3(1.3, 1.45, 1.25), leaf)
		_add_mesh(root, _sphere_mesh(1.0, 7, 4), Vector3(0.75, 2.8, 0.2), Vector3(0.85, 0.95, 0.82), leaf)
		_add_mesh(root, _sphere_mesh(1.0, 7, 4), Vector3(-0.7, 2.75, -0.15), Vector3(0.9, 0.9, 0.88), leaf)
	elif kind == 1:
		for i in 5:
			var angle := TAU * float(i) / 5.0
			_add_mesh(root, _sphere_mesh(1.0, 7, 4), Vector3(cos(angle) * 0.42, 0.38 + float(i % 2) * 0.18, sin(angle) * 0.42), Vector3(0.55, 0.5, 0.55), leaf)
	elif kind == 2:
		_add_mesh(root, _sphere_mesh(1.0, 7, 4), Vector3(0.0, 0.38, 0.0), Vector3(0.82, 0.52, 0.72), rock)
	elif kind == 3:
		for i in 5:
			var angle := TAU * float(i) / 5.0
			var stem_pos := Vector3(cos(angle) * 0.24, 0.25 + float(i % 3) * 0.06, sin(angle) * 0.24)
			_add_mesh(root, _cylinder_mesh(0.025, 0.025, 0.48, 5), stem_pos + Vector3.UP * 0.24, Vector3.ONE, leaf)
			_add_mesh(root, _sphere_mesh(1.0, 6, 3), stem_pos + Vector3.UP * 0.5, Vector3(0.14, 0.12, 0.14), flower)


func _prop_material(color: Color, ghost: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if ghost:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.28, 0.92, 0.35, 0.6)
	return material


func _add_mesh(root: Node3D, mesh: Mesh, pos: Vector3, scale_value: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.scale = scale_value
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)


func _cylinder_mesh(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh


func _sphere_mesh(radius: float, sides: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = sides
	mesh.rings = rings
	return mesh


func _place_preview() -> void:
	if _preview_prop != null and is_instance_valid(_preview_prop):
		return
	_preview_prop = _add_placed_prop(_selected_prop, Vector3.ZERO, 0.0, true)
	_preview_prop.visible = false


func _update_marker_color() -> void:
	var material := _marker.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = marker_color


func _update_editor_title(valid: bool = true) -> void:
	if _editor_title == null:
		return
	if _delete_mode:
		_editor_title.text = "Удаление: наведите на объект и нажмите ЛКМ."
	else:
		_editor_title.text = "%s  |  %s" % [
			PROP_NAMES[_selected_prop],
			"точка допустима" if valid else "здесь нельзя поставить",
		]


func _delete_prop_under_crosshair() -> void:
	var root: Node = _placed_root_from_hit(_raycast(editor_range))
	if root == null:
		return
	for i in _placed_props.size():
		if _placed_props[i]["node"] == root:
			_placed_props.remove_at(i)
			root.queue_free()
			_save_placed_props()
			return


func _placed_root_from_hit(hit: Dictionary) -> Node:
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider is StaticBody3D and collider.has_meta("landscape_prop"):
		return collider.get_parent()
	return null


func _save_placed_props() -> void:
	var config := ConfigFile.new()
	config.set_value("props", "count", _placed_props.size())
	for i in _placed_props.size():
		var prop: Dictionary = _placed_props[i]
		config.set_value("props", "kind_%d" % i, prop["kind"])
		config.set_value("props", "pos_%d" % i, prop["pos"])
		config.set_value("props", "yaw_%d" % i, prop["yaw"])
	config.save(PLACED_LAYOUT_PATH)


func _load_placed_props() -> void:
	var config := ConfigFile.new()
	if config.load(PLACED_LAYOUT_PATH) != OK:
		_place_preview()
		return
	var count: int = int(config.get_value("props", "count", 0))
	for i in count:
		var kind: int = int(config.get_value("props", "kind_%d" % i, 0))
		var pos: Variant = config.get_value("props", "pos_%d" % i, Vector3.ZERO)
		var yaw: float = float(config.get_value("props", "yaw_%d" % i, 0.0))
		if kind >= 0 and kind < PROP_NAMES.size() and pos is Vector3:
			_add_placed_prop(kind, pos, yaw, false)
	_place_preview()
