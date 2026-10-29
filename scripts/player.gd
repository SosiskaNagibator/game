extends CharacterBody3D
## Игрок от первого лица: ходьба, бег, прыжок, приседание,
## вход в машину и выход из неё, переноска ящиков.
##
## Управление:
##   W/A/S/D      — движение
##   Shift        — бег
##   Space        — прыжок
##   Ctrl         — присесть (удерживать)
##   E            — взять/поставить ящик, сесть в машину / выйти из машины
##   Колесо мыши  — повернуть ящик в руках
##   Q / R        — плавно вращать ящик в руках
##   V            — вид от третьего лица (в машине)
##   Esc          — пауза (обрабатывается камерой машины)

@export_group("Передвижение")
## Скорость ходьбы, м/с.
@export var walk_speed: float = 4.5
## Скорость бега, м/с.
@export var sprint_speed: float = 7.5
## Скорость в приседе, м/с.
@export var crouch_speed: float = 2.2
## Ускорение разгона/торможения, м/с².
@export var acceleration: float = 12.0
## Начальная скорость прыжка, м/с.
@export var jump_velocity: float = 5.0
## Доля высоты капсулы в приседе (0.55 = 55% от роста).
@export_range(0.35, 0.8, 0.01) var crouch_height_ratio: float = 0.55
## Скорость изменения высоты капсулы при приседании.
@export var crouch_speed_change: float = 4.0

@export_group("Камера")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022
@export_range(30.0, 89.0, 1.0) var max_pitch_deg: float = 85.0

@export_group("Взаимодействие")
## С какого расстояния от центра машины можно в неё сесть.
@export var enter_range: float = 6.0

@export_group("Груз")
## Дальность луча, которым игрок наводится на ящики и кузов.
@export var cargo_reach: float = 4.0
## Положение ящика в руках относительно камеры.
@export var cargo_hold_offset: Vector3 = Vector3(0.45, -0.45, -1.6)
## Насколько поворачивается ящик за один щелчок колеса, градусы.
@export_range(5.0, 90.0, 1.0) var cargo_rotate_step_deg: float = 45.0
## Скорость доводки ящика до целевого угла, градусы/с.
@export var cargo_rotate_speed_deg: float = 270.0
## Скорость вращения ящика при удержании Q/R, градусы/с.
@export var cargo_rotate_key_speed_deg: float = 120.0
## Прозрачность призрака ящика.
@export_range(0.05, 1.0, 0.01) var cargo_ghost_alpha: float = 0.4
## Громкость звука установки ящика, дБ.
@export var cargo_thud_volume_db: float = -4.0

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _hint: Label = $HUD/Hint

# Ресурс капсулы (меняем высоту при приседании).
var _capsule: CapsuleShape3D
var _stand_height: float = 1.8
var _crouch_height: float = 1.0
# Наклон камеры в радианах.
var _pitch: float = 0.0
# Игрок сейчас за рулём?
var _driving: bool = false
var _landscape_editing: bool = false
# Машина, которой управляет игрок.
var _vehicle: BaseVehicle = null
# Подсказка от других систем (перестановка деревьев и т.п.).
var _hint_override: String = ""

# --- Груз ------------------------------------------------------------------
var _interact_ray: RayCast3D = null
## Отдельный луч только по слою взаимодействия: корпус машины не перекрывает
## Area3D кузова и загруженные ящики.
var _cargo_ray: RayCast3D = null
var _hold_marker: Marker3D = null
var _cargo_system: CargoSystem = null
var _held_box: RigidBody3D = null
var _ghost: Node3D = null
var _ghost_valid_material: StandardMaterial3D = null
var _ghost_invalid_material: StandardMaterial3D = null
var _ghost_bottom_offset: float = 0.0
var _hold_rotation: float = 0.0
var _hold_rotation_target: float = 0.0
var _target_vehicle: VehicleBody3D = null
var _target_slot: int = -1
var _ghost_valid: bool = false
var _drop_blocked: bool = false
var _thud_player: AudioStreamPlayer3D = null


func _ready() -> void:
	_capsule = _collision.shape as CapsuleShape3D
	_stand_height = _capsule.height
	_crouch_height = _stand_height * crouch_height_ratio
	_camera.position.y = _stand_height - 0.2
	_pitch = _camera.rotation.x

	_hint.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_cargo_interaction()


func _physics_process(delta: float) -> void:
	# В редакторе ландшафта мышь занята установкой объектов, но ходить можно (B).
	if _driving:
		return

	_apply_gravity(delta)
	_update_crouch(delta)
	_update_movement(delta)
	move_and_slide()


func _process(delta: float) -> void:
	# За рулём подсказку показывает сама машина.
	if _driving:
		return

	# Переноска ящика: обновляем призрак и подсказку каждый кадр.
	if _held_box != null:
		_update_held_rotation(delta)
		_update_held_box()
		_update_ghost()
		_update_cargo_hint()
		return

	# Подсказка от другой системы важнее подсказки про машину.
	if not _hint_override.is_empty():
		_hint.text = _hint_override
		_hint.visible = true
		return

	if _aimed_cargo_box() != null:
		_hint.text = "[E] Взять ящик"
		_hint.visible = true
		return

	_hint.text = "[E] Сесть в машину"
	_hint.visible = _find_nearest_vehicle() != null


func _input(event: InputEvent) -> void:
	if _landscape_editing:
		return

	# E — ящик / машина.
	if event.is_action_pressed("interact"):
		if _driving:
			_leave_vehicle()
		elif _held_box != null:
			_drop_held_box()
		else:
			var box := _aimed_cargo_box()
			if box != null:
				_pick_up_box(box)
			else:
				_enter_nearest_vehicle()
		return

	# Клик по окну возвращает захват мыши (например, после паузы).
	if event is InputEventMouseButton and event.pressed:
		# Колесо мыши вращает ящик в руках.
		if _held_box != null and _handle_cargo_scroll(event):
			return

		if not _landscape_editing and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if _driving:
		return

	# Вращение камеры мышью: игрок поворачивается вокруг Y, камера наклоняется по X.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)

		var pitch_limit: float = deg_to_rad(max_pitch_deg)
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity,
			-pitch_limit,
			pitch_limit
		)
		_camera.rotation.x = _pitch
		_camera.rotation.z = 0.0


# --- Движение --------------------------------------------------------------


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity


func _get_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _update_movement(delta: float) -> void:
	# get_vector: вперёд = -Y (move_forward — отрицательное действие).
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)

	# Направление относительно текущего поворота игрока.
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed: float = walk_speed
	if _capsule.height < _stand_height * 0.9:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed

	# С ящиком в руках идём медленнее.
	if _held_box != null:
		speed *= 0.75

	var target: Vector3 = direction * speed
	# В воздухе управление слабее.
	var accel: float = acceleration if is_on_floor() else acceleration * 0.3
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)


# --- Приседание ------------------------------------------------------------


func _update_crouch(delta: float) -> void:
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	var target_height: float = _crouch_height if wants_crouch else _stand_height

	# Не даём встать, если над головой потолок.
	if not wants_crouch and _capsule.height < _stand_height - 0.01 and not _has_headroom():
		target_height = _capsule.height

	var new_height: float = move_toward(_capsule.height, target_height, crouch_speed_change * delta)
	_capsule.height = new_height
	_collision.position.y = new_height * 0.5
	_camera.position.y = lerpf(_camera.position.y, new_height - 0.2, 10.0 * delta)


func _has_headroom() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * (_capsule.height - 0.05),
		global_position + Vector3.UP * (_stand_height + 0.05)
	)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Машина ----------------------------------------------------------------


func _find_nearest_vehicle() -> BaseVehicle:
	var nearest: BaseVehicle = null
	var nearest_distance: float = enter_range

	for node in get_tree().get_nodes_in_group("vehicles"):
		if node is not BaseVehicle:
			continue

		var vehicle: BaseVehicle = node
		if vehicle.is_occupied():
			continue

		var distance: float = global_position.distance_to(vehicle.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = vehicle

	return nearest


func _enter_nearest_vehicle() -> void:
	var vehicle: BaseVehicle = _find_nearest_vehicle()
	if vehicle == null:
		return

	var vehicle_camera: Camera3D = vehicle.get_vehicle_camera()
	if vehicle_camera == null:
		push_warning("Player: у машины нет Camera3D.")
		return

	_vehicle = vehicle
	_driving = true
	vehicle.enter_vehicle(self)

	# Переключаем камеру и прячем игрока.
	_camera.current = false
	vehicle_camera.current = true
	visible = false
	_collision.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)

	_hint.text = "[E] Выйти из машины    [V] Сменить вид"
	_hint.visible = true


func _leave_vehicle() -> void:
	if _vehicle == null:
		return

	var vehicle: BaseVehicle = _vehicle
	var exit_position: Vector3 = vehicle.get_exit_position()

	vehicle.exit_vehicle()
	_vehicle = null
	_driving = false

	global_position = exit_position
	velocity = Vector3.ZERO
	visible = true
	_collision.set_deferred("disabled", false)
	set_physics_process(true)

	var vehicle_camera: Camera3D = vehicle.get_vehicle_camera()
	if vehicle_camera != null:
		vehicle_camera.current = false
	_camera.current = true

	_hint.text = "[E] Сесть в машину"


# --- Груз: наведение, переноска, призрак -----------------------------------


func _setup_cargo_interaction() -> void:
	_interact_ray = get_node_or_null("Camera3D/InteractRay") as RayCast3D
	if _interact_ray == null:
		_interact_ray = RayCast3D.new()
		_interact_ray.name = "InteractRay"
		_camera.add_child(_interact_ray)
	_interact_ray.target_position = Vector3(0.0, 0.0, -cargo_reach)
	_interact_ray.collision_mask = 1 | 2
	_interact_ray.collide_with_areas = true
	_interact_ray.collide_with_bodies = true
	_interact_ray.enabled = true
	_interact_ray.exclude_parent = true
	_interact_ray.add_exception(self)

	_cargo_ray = get_node_or_null("Camera3D/CargoRay") as RayCast3D
	if _cargo_ray == null:
		_cargo_ray = RayCast3D.new()
		_cargo_ray.name = "CargoRay"
		_camera.add_child(_cargo_ray)
	_cargo_ray.target_position = Vector3(0.0, 0.0, -cargo_reach)
	_cargo_ray.collision_mask = 2
	_cargo_ray.collide_with_areas = true
	_cargo_ray.collide_with_bodies = true
	_cargo_ray.enabled = true
	_cargo_ray.exclude_parent = true
	_cargo_ray.add_exception(self)

	_hold_marker = get_node_or_null("Camera3D/CargoHold") as Marker3D
	if _hold_marker == null:
		_hold_marker = Marker3D.new()
		_hold_marker.name = "CargoHold"
		_camera.add_child(_hold_marker)
	_hold_marker.position = cargo_hold_offset

	_ghost_valid_material = _make_ghost_material(
		Color(0.35, 1.0, 0.45, cargo_ghost_alpha)
	)
	_ghost_invalid_material = _make_ghost_material(
		Color(1.0, 0.22, 0.16, cargo_ghost_alpha)
	)
	_setup_thud()


func _make_ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.no_depth_test = false
	return material


func _setup_thud() -> void:
	_thud_player = AudioStreamPlayer3D.new()
	_thud_player.name = "CargoThud"
	_thud_player.stream = _make_thud_stream()
	_thud_player.volume_db = cargo_thud_volume_db
	_thud_player.unit_size = 4.0
	_thud_player.max_distance = 35.0
	add_child(_thud_player)
	_thud_player.top_level = true


## Короткий низкий «бум» генерируется в памяти — внешний .wav не нужен.
func _make_thud_stream() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.22
	var count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x54485544
	for i in count:
		var t := float(i) / float(mix_rate)
		var env := exp(-t * 24.0)
		var tone := sin(TAU * 72.0 * t) * 0.75 + sin(TAU * 118.0 * t) * 0.25
		var noise := rng.randf_range(-1.0, 1.0) * 0.18
		var sample := clampf((tone + noise) * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream


func _play_thud(world_position: Vector3, volume_offset_db: float = 0.0) -> void:
	if _thud_player == null:
		return
	_thud_player.global_position = world_position
	_thud_player.volume_db = cargo_thud_volume_db + volume_offset_db
	_thud_player.play()


func _get_cargo_system() -> CargoSystem:
	if _cargo_system != null and is_instance_valid(_cargo_system):
		return _cargo_system
	_cargo_system = get_tree().get_first_node_in_group("cargo_system") as CargoSystem
	return _cargo_system


func _aimed_cargo_box() -> RigidBody3D:
	# Сначала обычный луч (ящики на земле), затем «грузовой» — он видит
	# ящики в кузове сквозь корпус машины.
	var box := _raycast_cargo_box(_interact_ray)
	if box != null:
		return box
	return _raycast_cargo_box(_cargo_ray)


func _raycast_cargo_box(ray: RayCast3D) -> RigidBody3D:
	if ray == null:
		return null
	ray.force_raycast_update()
	if not ray.is_colliding():
		return null
	var collider: Object = ray.get_collider()
	if collider is RigidBody3D and collider.is_in_group("cargo"):
		return collider as RigidBody3D
	return null


## Наведение на кузов: Area3D кузова или уже загруженный ящик.
func _is_cargo_target(collider: Object) -> bool:
	if collider is Area3D and collider.is_in_group("cargo_area"):
		return true
	return (
		collider is RigidBody3D
		and collider.is_in_group("cargo")
		and collider.has_meta("cargo_slot")
	)


func _get_cargo_vehicle(collider: Object) -> VehicleBody3D:
	if collider == null:
		return null

	if collider is Area3D and collider.is_in_group("cargo_area"):
		if collider.has_meta("cargo_vehicle"):
			var vehicle: Variant = collider.get_meta("cargo_vehicle")
			if vehicle is VehicleBody3D:
				return vehicle
		var parent: Node = collider.get_parent()
		if parent is VehicleBody3D:
			return parent

	# Загруженный ящик тоже считается частью кузова: по нему можно
	# навестись и увидеть, что слот занят.
	if collider is RigidBody3D and collider.is_in_group("cargo"):
		if collider.has_meta("cargo_vehicle"):
			var vehicle: Variant = collider.get_meta("cargo_vehicle")
			if vehicle is VehicleBody3D:
				return vehicle

	return null


func _pick_up_box(box: RigidBody3D) -> void:
	if box == null:
		return

	# Если ящик уже стоял в кузове — освобождаем слот и массу машины.
	var cargo := _get_cargo_system()
	if cargo != null:
		cargo.unregister_box(box)

	_held_box = box
	_hold_rotation = 0.0
	_hold_rotation_target = 0.0
	_apply_box_held(box)
	box.reparent(_hold_marker, false)
	box.transform = Transform3D(Basis(Vector3.UP, _hold_rotation), Vector3.ZERO)

	_create_ghost(box)
	_update_ghost()
	_update_cargo_hint()


func _apply_box_held(box: RigidBody3D) -> void:
	if box is CargoBox:
		(box as CargoBox).set_held()
		return
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.collision_layer = 0
	box.collision_mask = 0


func _update_held_rotation(delta: float) -> void:
	# Удержание Q/R плавно добавляет вращение к целевой цели.
	var key_dir := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		key_dir += 1.0
	if Input.is_physical_key_pressed(KEY_R):
		key_dir -= 1.0
	if not is_zero_approx(key_dir):
		_hold_rotation_target = wrapf(
			_hold_rotation_target
			+ deg_to_rad(cargo_rotate_key_speed_deg) * key_dir * delta,
			-PI,
			PI
		)

	# Доводим текущий угол к целевому по кратчайшей дуге.
	_hold_rotation = rotate_toward(
		_hold_rotation,
		_hold_rotation_target,
		deg_to_rad(cargo_rotate_speed_deg) * delta
	)


func _update_held_box() -> void:
	if _held_box == null:
		return
	_held_box.transform = Transform3D(Basis(Vector3.UP, _hold_rotation), Vector3.ZERO)


func _handle_cargo_scroll(event: InputEventMouseButton) -> bool:
	var step := deg_to_rad(cargo_rotate_step_deg)
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_hold_rotation_target = wrapf(_hold_rotation_target + step, -PI, PI)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_hold_rotation_target = wrapf(_hold_rotation_target - step, -PI, PI)
	else:
		return false

	# Доводка выполняется в _process; здесь только накапливаем цель.
	_update_ghost()
	_update_cargo_hint()
	return true


func _update_ghost() -> void:
	if _held_box == null or _ghost == null:
		return

	_interact_ray.force_raycast_update()
	if _cargo_ray != null:
		_cargo_ray.force_raycast_update()

	var main_collider: Object = null
	var main_point := Vector3.ZERO
	if _interact_ray.is_colliding():
		main_collider = _interact_ray.get_collider()
		main_point = _interact_ray.get_collision_point()

	_target_vehicle = null
	_target_slot = -1
	_ghost_valid = false
	_drop_blocked = false
	_ghost.visible = true

	# Куда попал «грузовой» луч: Area3D кузова или загруженный ящик.
	var cargo_collider: Object = null
	var cargo_point := Vector3.ZERO

	if _is_cargo_target(main_collider):
		cargo_collider = main_collider
		cargo_point = main_point
	elif main_collider is VehicleBody3D and _cargo_ray != null and _cargo_ray.is_colliding():
		var hit_collider: Object = _cargo_ray.get_collider()
		if _is_cargo_target(hit_collider):
			var cargo_distance: float = _cargo_ray.get_collision_point().distance_to(
				_cargo_ray.global_position
			)
			var body_distance: float = main_point.distance_to(
				_interact_ray.global_position
			)
			# Корпус сбоку перекрывает Area3D всего на ~0.2 м — это нормально.
			# Если же корпус заметно ближе (кабина, мотор), значит игрок целится
			# не в кузов, и «протыкать» машину лучом нельзя.
			if cargo_distance <= body_distance + 0.6:
				cargo_collider = hit_collider
				cargo_point = _cargo_ray.get_collision_point()

	var vehicle := _get_cargo_vehicle(cargo_collider)
	var cargo := _get_cargo_system()
	if vehicle != null and cargo != null:
		var slot := -1
		var occupied := false

		if (
			cargo_collider is RigidBody3D
			and cargo_collider.is_in_group("cargo")
			and cargo_collider.has_meta("cargo_slot")
		):
			# Игрок целится прямо в загруженный ящик — этот слот занят.
			slot = int(cargo_collider.get_meta("cargo_slot"))
			occupied = true
		else:
			# Ищем ближайший свободный слот. Если кузов полон — показываем
			# красный призрак на ближайшем слоте.
			slot = cargo.find_nearest_empty_slot(vehicle, cargo_point)
			if slot < 0:
				slot = cargo.find_nearest_slot(vehicle, cargo_point)
				occupied = true

		if slot >= 0:
			# Призрак в кузове всегда выровнен по машине: при установке
			# ящик тоже встанет ровно, независимо от угла в руках.
			_ghost.global_transform = cargo.get_slot_world_transform(
				vehicle, slot, 0.0
			)
			_target_vehicle = vehicle
			_target_slot = slot
			_ghost_valid = not occupied
			_set_ghost_valid(_ghost_valid)
			return

	# Игрок смотрит на корпус машины, но не в кузов (кабина, крыло):
	# ставить ящик некуда, призрак прячем.
	if main_collider is VehicleBody3D:
		_drop_blocked = true
		_ghost.visible = false
		_set_ghost_valid(false)
		return

	# Луч не попал в кузов — призрак на земле/поверхности.
	_ghost.global_transform = _get_ground_placement()
	_set_ghost_valid(true)


func _get_ground_placement() -> Transform3D:
	var point := Vector3.ZERO
	var normal := Vector3.UP

	if _interact_ray.is_colliding():
		point = _interact_ray.get_collision_point()
		normal = _interact_ray.get_collision_normal()
	else:
		var forward := -_camera.global_transform.basis.z
		var probe := _camera.global_position + forward * 2.0
		var query := PhysicsRayQueryParameters3D.create(
			probe + Vector3.UP * 2.0,
			probe + Vector3.DOWN * 8.0,
			1,
			[get_rid()]
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			point = probe + Vector3.DOWN * 1.0
		else:
			point = hit.position
			normal = hit.normal

	var basis := Basis(Vector3.UP, rotation.y + _hold_rotation)
	var position := point + normal * 0.02 + Vector3.UP * (_ghost_bottom_offset + 0.01)
	return Transform3D(basis, position)


func _set_ghost_valid(valid: bool) -> void:
	if _ghost == null:
		return
	var material := _ghost_valid_material if valid else _ghost_invalid_material
	for child in _ghost.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material


func _create_ghost(source: Node3D) -> void:
	_destroy_ghost()

	var ghost := Node3D.new()
	ghost.name = "CargoGhost"
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	root.add_child(ghost)

	var to_source := source.global_transform.affine_inverse()
	var meshes := _collect_meshes(source)
	if meshes.is_empty():
		_add_fallback_ghost_mesh(ghost, source)
	else:
		for node in meshes:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var copy := MeshInstance3D.new()
			copy.name = mesh_instance.name
			copy.mesh = mesh_instance.mesh
			copy.material_override = _ghost_valid_material
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			ghost.add_child(copy)
			copy.transform = to_source * mesh_instance.global_transform

	_ghost = ghost
	_ghost_bottom_offset = _get_box_bottom_offset(source)
	_set_ghost_valid(true)


func _add_fallback_ghost_mesh(ghost: Node3D, source: Node3D) -> void:
	var size := Vector3(0.6, 0.3, 0.6)
	var offset := Vector3.ZERO
	var collision := source.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		size = (collision.shape as BoxShape3D).size
		offset = collision.position

	var mesh := BoxMesh.new()
	mesh.size = size
	var copy := MeshInstance3D.new()
	copy.mesh = mesh
	copy.material_override = _ghost_valid_material
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	copy.position = offset
	ghost.add_child(copy)


func _get_box_bottom_offset(source: Node3D) -> float:
	var to_source := source.global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false

	for node in _collect_meshes(source):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var xform := to_source * mesh_instance.global_transform
		var mesh_bounds := _get_mesh_vertex_bounds(mesh_instance.mesh, xform)
		if not bool(mesh_bounds["valid"]):
			continue
		var aabb: AABB = mesh_bounds["aabb"]
		if not has_bounds:
			bounds = aabb
			has_bounds = true
		else:
			bounds = bounds.merge(aabb)

	if not has_bounds:
		return 0.0
	return maxf(-bounds.position.y, 0.0)


## Точные границы вершин: локальный AABB меша у woodbox.glb сильно раздут
## и даёт неверное смещение призрака к полу.
func _get_mesh_vertex_bounds(mesh: Mesh, xform: Transform3D) -> Dictionary:
	var result := AABB()
	var has_bounds := false

	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := xform * vertex
			if not has_bounds:
				result = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				result = result.expand(point)

	return {"valid": has_bounds, "aabb": result}


func _collect_meshes(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_meshes(child))
	return result


func _destroy_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_target_vehicle = null
	_target_slot = -1
	_ghost_valid = false
	_drop_blocked = false


func _update_cargo_hint() -> void:
	if _held_box == null:
		return

	if _drop_blocked:
		_hint.text = "Здесь нельзя поставить ящик    [Колесо/Q/R] Поворот"
	elif _target_vehicle != null:
		if _ghost_valid:
			_hint.text = "[E] Поставить ящик    [Колесо/Q/R] Поворот"
		else:
			_hint.text = "Место занято    [Колесо/Q/R] Поворот"
	else:
		_hint.text = "[E] Бросить ящик    [Колесо/Q/R] Поворот"
	_hint.visible = true


func _drop_held_box() -> void:
	if _held_box == null:
		return

	if _drop_blocked:
		_update_cargo_hint()
		return

	if _target_vehicle != null and _target_slot >= 0:
		if not _ghost_valid:
			# Слот занят: не бросаем ящик в чужой ящик.
			_update_cargo_hint()
			return
		_place_in_truck(_target_vehicle, _target_slot)
		return

	_drop_on_ground()


func _place_in_truck(vehicle: VehicleBody3D, slot: int) -> void:
	var cargo := _get_cargo_system()
	if cargo == null:
		_drop_on_ground()
		return

	var box := _held_box
	if not cargo.register_box(vehicle, box, slot, 0.0):
		_drop_on_ground()
		return

	var xform := cargo.get_slot_world_transform(vehicle, slot, 0.0)
	if box is CargoBox:
		(box as CargoBox).set_loaded()
	else:
		box.freeze = true
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.collision_layer = 2
		box.collision_mask = 0

	box.reparent(vehicle, true)
	box.global_transform = xform
	# Слот задаёт точную ориентацию кузова: сбрасываем любой угол,
	# под которым игрок держал ящик.
	box.rotation = Vector3.ZERO
	_play_thud(box.global_position, 0.0)

	_held_box = null
	_destroy_ghost()
	_hint.visible = false


func _drop_on_ground() -> void:
	var box := _held_box
	if box == null:
		return

	var xform := _ghost.global_transform if _ghost != null else _hold_marker.global_transform
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	box.reparent(root, true)
	box.global_transform = xform

	if box is CargoBox:
		(box as CargoBox).set_free()
	else:
		box.freeze = false
		box.collision_layer = 1
		box.collision_mask = 1
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.sleeping = false

	_play_thud(box.global_position, -6.0)
	_held_box = null
	_destroy_ghost()
	_hint.visible = false


# --- Публичный API для других систем ----------------------------------------


## Камера от первого лица (нужна для наведения на объекты).
func get_camera() -> Camera3D:
	return _camera


## Игрок сейчас за рулём?
func is_driving() -> bool:
	return _driving


## Игрок несёт ящик?
func is_holding_cargo() -> bool:
	return _held_box != null


func set_landscape_editing(enabled: bool) -> void:
	_landscape_editing = enabled
	if enabled:
		velocity = Vector3.ZERO


## Показать подсказку поверх стандартных (деревья, склад и т.п.).
func set_hint_override(text: String) -> void:
	_hint_override = text


## Убрать внешнюю подсказку.
func clear_hint_override() -> void:
	_hint_override = ""
