@tool
extends Node3D
## Густой смешанный лес по всей карте.
##
## Деревья, кусты, трава, камни, поваленные стволы и пни собраны через
## MultiMesh: тысячи объектов стоят почти ничего. Лес не растёт на дорогах,
## во дворе базы и в деревне; вокруг скрытой базы остаётся плотное кольцо
## ельника, которое закрывает постройки от посторонних глаз.

const FOLIAGE_SHADER := preload("res://shaders/foliage_flat.gdshader")
const TREE_SHADER := preload("res://shaders/foliage_tree.gdshader")
const GRASS_SHADER := preload("res://shaders/grass_blade.gdshader")

const RNG_SEED := 77123
## Раскладка деревьев, которую игрок меняет вручную, хранится здесь.
## Версия в имени файла — чтобы старая раскладка открытого поля не
## перетаскивала деревья нового леса.
const LAYOUT_PATH := "user://tree_layout_v3.cfg"

## Шаг сетки посадки деревьев. Лес плотный: кроны соседей перекрываются,
## и между стволами не видно просветов на уровне глаз.
const TREE_CELL := 6.4
const TREE_MARGIN := 2.8
## Подлесок сажается ещё гуще деревьев — именно он делает лес непросвечиваемым.
const BUSH_CELL := 4.8
## Общий масштаб лесных деревьев. 1.0 — прежние 9–15 м; сейчас лес
## пониже, чтобы кроны не нависали над домами и машинами.
const TREE_SCALE := 0.62
## Лес на карте. false — деревьев нет вовсе: остаются кусты, трава, камни
## и цветы. Свои деревья можно расставить руками в редакторе.
const TREES_ENABLED := false
## Кусты (подлесок). false — кустов на карте нет.
const BUSHES_ENABLED := false
## Камни и их коллизии.
const ROCKS_ENABLED := true
const GRASS_ENABLED := true
const DETAILS_ENABLED := true
## Радиус вокруг базы и деревни, где каждое дерево — отдельный объект,
## который можно выбрать и двигать. Дальше лес остаётся MultiMesh.
const NEAR_TREE_RADIUS := 150.0

## Высоты прототипов деревьев-объектов (м). Набор фиксирован, чтобы
## меши переиспользовались и сцена не пухла от тысяч уникальных мешей.
const CONIFER_HEIGHTS := [5.6, 6.1, 6.6, 7.1, 7.6, 8.2, 8.8, 9.4]
const BROADLEAF_HEIGHTS := [4.3, 4.7, 5.2, 5.7, 6.2, 6.7, 7.1, 7.4]

var _rng := RandomNumberGenerator.new()
## Отдельный поток случайности для деревьев-объектов: включение/выключение
## объектов не должно сдвигать процедурный лес из MultiMesh.
var _near_rng := RandomNumberGenerator.new()
var _species_noise: FastNoiseLite
var _prototypes: Dictionary = {}
var _near_nodes: Array[StaticBody3D] = []
var _near_baked: bool = false
var _near_material: ShaderMaterial

var _trees: Array[Dictionary] = []
var _collider_ids: Dictionary = {}
## Номера коллайдеров дальнего леса: все его стволы живут в одном
## StaticBody3D, чтобы не упереться в лимит тел Jolt.
var _far_shape_ids: Dictionary = {}
var _far_tree_body: StaticBody3D = null

# Буферы экземпляров.
var _trunk_conifer: Array[Transform3D] = []
var _trunk_broadleaf: Array[Transform3D] = []
var _cones: Array[Transform3D] = []
var _cone_tints: Array[Color] = []
var _blobs: Array[Transform3D] = []
var _blob_tints: Array[Color] = []
var _bushes: Array[Transform3D] = []
var _bush_tints: Array[Color] = []
var _grass: Array[Transform3D] = []
var _grass_data: Array[Color] = []
var _rocks: Array[Transform3D] = []
var _rock_colors: Array[Color] = []
var _rock_colliders: Array[Dictionary] = []
var _logs: Array[Transform3D] = []
var _stumps: Array[Transform3D] = []

var _multimeshes: Dictionary = {}


func _ready() -> void:
	if get_node_or_null("TreeTrunks") != null:
		return
	add_to_group("vegetation")
	_rng.seed = RNG_SEED
	_near_rng.seed = RNG_SEED + 17
	_near_material = ShaderMaterial.new()
	_near_material.shader = TREE_SHADER
	_species_noise = FastNoiseLite.new()
	_species_noise.seed = 55021
	_species_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_species_noise.frequency = 0.011
	_species_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_species_noise.fractal_octaves = 3

	if TREES_ENABLED:
		_collect_near_nodes()
		_scatter_forest()
		_register_near_nodes()
	if BUSHES_ENABLED:
		_scatter_bushes()
	if GRASS_ENABLED:
		_scatter_grass()
	_scatter_details()
	_build_visuals()
	_build_collisions()
	if not Engine.is_editor_hint() and TREES_ENABLED:
		_load_layout()


# --- Деревья ---------------------------------------------------------------


func _scatter_forest() -> void:
	var limit: float = RuralHeight.WORLD_HALF - 7.0
	var steps: int = int(ceil(limit * 2.0 / TREE_CELL))
	var jitter: float = TREE_CELL * 0.46

	for gz in steps:
		for gx in steps:
			var x: float = -limit + (float(gx) + 0.5) * TREE_CELL
			var z: float = -limit + (float(gz) + 0.5) * TREE_CELL
			x += _rng.randf_range(-jitter, jitter)
			z += _rng.randf_range(-jitter, jitter)
			if absf(x) > limit or absf(z) > limit:
				continue
			var density: float = RuralHeight.forest_density(x, z)
			if density < 0.10:
				continue
			# Не сплошной ковёр: в редколесье остаются окна.
			if _rng.randf() > density * 0.94:
				continue
			if _is_near_tree(x, z):
				# Рядом с базой и деревней — обычные объекты, которые можно
				# выбрать и перетащить. RNG для них отдельный, поэтому
				# процедурный лес дальше не сдвигается.
				if _near_baked:
					continue
				var species: float = _species_noise.get_noise_2d(x, z)
				var conifer: bool = species > -0.05
				if _near_rng.randf() < 0.12:
					conifer = not conifer
				_add_near_tree(x, z, conifer)
				continue
			_add_tree(x, z)


## Дерево попадает в редактируемую зону у базы или деревни.
func _is_near_tree(x: float, z: float) -> bool:
	var point := Vector2(x, z)
	return (
		point.distance_to(RuralHeight.BASE_CENTER) <= NEAR_TREE_RADIUS
		or point.distance_to(RuralHeight.SETTLEMENT_CENTER) <= NEAR_TREE_RADIUS
	)


func _add_tree(x: float, z: float) -> void:
	var y: float = RuralHeight.terrain_height(x, z)
	var species: float = _species_noise.get_noise_2d(x, z)
	var conifer: bool = species > -0.05
	if _rng.randf() < 0.12:
		conifer = not conifer

	var tint: Color = RuralHeight.foliage_color(_rng)
	var parts: Array[Dictionary] = []
	var radius: float = 0.3
	var trunk_height: float = 6.0

	if conifer:
		var height: float = _rng.randf_range(9.0, 15.5) * TREE_SCALE
		radius = _rng.randf_range(0.24, 0.38) * TREE_SCALE
		trunk_height = height * 0.62
		var trunk_local := Transform3D(
			Basis.IDENTITY.scaled_local(Vector3(radius, trunk_height, radius)),
			Vector3(0.0, trunk_height * 0.5, 0.0)
		)
		parts.append(_add_part("trunk_conifer", _trunk_conifer, trunk_local, x, y, z))

		# Три яруса еловых лап. Радиус яруса — доля высоты дерева:
		# широкие «зонты» в 1.3 высоты смотрелись великанами.
		var layers := [
			Vector3(0.12, 0.30, 0.46),
			Vector3(0.17, 0.30, 0.64),
			Vector3(0.23, 0.26, 0.82),
		]
		for layer in layers:
			var layer_radius: float = height * float(layer.x) * _rng.randf_range(0.92, 1.08)
			var layer_height: float = height * float(layer.y)
			var center_y: float = height * float(layer.z)
			var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0))
			basis = basis.scaled_local(Vector3(layer_radius * 2.0, layer_height, layer_radius * 2.0))
			var local := Transform3D(basis, Vector3(0.0, center_y, 0.0))
			parts.append(_add_foliage_part("cones", _cones, local, x, y, z, tint))
	else:
		var height: float = _rng.randf_range(7.0, 12.0) * TREE_SCALE
		radius = _rng.randf_range(0.28, 0.46) * TREE_SCALE
		trunk_height = height * 0.68
		var trunk_local := Transform3D(
			Basis.IDENTITY.scaled_local(Vector3(radius, trunk_height, radius)),
			Vector3(0.0, trunk_height * 0.5, 0.0)
		)
		parts.append(_add_part("trunk_broadleaf", _trunk_broadleaf, trunk_local, x, y, z))

		var crown_radius: float = _rng.randf_range(1.6, 2.4) * TREE_SCALE
		var crown_y: float = height * 0.84
		var blob_count: int = _rng.randi_range(4, 5)
		for i in blob_count:
			var angle: float = _rng.randf_range(0.0, TAU)
			var spread: float = 0.0 if i == 0 else _rng.randf_range(0.45, 0.8)
			var scale_factor: float = 1.0 if i == 0 else _rng.randf_range(0.62, 0.85)
			var r: float = crown_radius * scale_factor
			var offset := Vector3(
				cos(angle) * crown_radius * spread,
				_rng.randf_range(-0.14, 0.20) * crown_radius,
				sin(angle) * crown_radius * spread
			)
			var basis := Basis.from_euler(Vector3(
				_rng.randf_range(-0.08, 0.08),
				_rng.randf_range(0.0, TAU),
				_rng.randf_range(-0.08, 0.08)
			))
			basis = basis.scaled_local(Vector3(r, r * _rng.randf_range(0.62, 0.82), r))
			var local := Transform3D(basis, Vector3(offset.x, crown_y + offset.y, offset.z))
			parts.append(_add_foliage_part("blobs", _blobs, local, x, y, z, tint))

	_trees.append({
		"kind": "mesh",
		"pos": Vector3(x, y, z),
		"initial_pos": Vector3(x, y, z),
		"yaw": 0.0,
		"radius": radius,
		"height": trunk_height,
		"parts": parts,
		"body": null,
	})


func _add_part(
	group: String,
	buffer: Array[Transform3D],
	local: Transform3D,
	x: float,
	y: float,
	z: float
) -> Dictionary:
	var index: int = buffer.size()
	buffer.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)) * local)
	return {"group": group, "index": index, "local": local}


func _add_foliage_part(
	group: String,
	buffer: Array[Transform3D],
	local: Transform3D,
	x: float,
	y: float,
	z: float,
	tint: Color
) -> Dictionary:
	var index: int = buffer.size()
	buffer.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)) * local)
	var variation := Color(
		clampf(tint.r + _rng.randf_range(-0.04, 0.05), 0.0, 1.0),
		clampf(tint.g + _rng.randf_range(-0.05, 0.05), 0.0, 1.0),
		clampf(tint.b + _rng.randf_range(-0.03, 0.03), 0.0, 1.0),
		1.0
	)
	if group == "cones":
		_cone_tints.append(variation.darkened(0.08))
	else:
		_blob_tints.append(variation)
	return {"group": group, "index": index, "local": local}


# --- Деревья-объекты у базы и деревни ---------------------------------------


## Собирает несколько примитивов в один меш: ствол и крона дерева-объекта
## лежат в одной поверхности, поэтому на дерево приходится одна нода-меш.
class TreeMeshBuilder:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add_mesh(mesh: Mesh, xform: Transform3D, color: Color) -> void:
		var arrays: Array = mesh.surface_get_arrays(0)
		var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base: int = vertices.size()
		var normal_basis := xform.basis.inverse().transposed()
		for i in src_verts.size():
			vertices.append(xform * src_verts[i])
			normals.append((normal_basis * src_normals[i]).normalized())
			colors.append(color)
		if src_indices.is_empty():
			for i in src_verts.size():
				indices.append(base + i)
		else:
			for i in src_indices:
				indices.append(base + i)

	func commit(material: Material) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh


func _collect_near_nodes() -> void:
	_near_nodes.clear()
	var container := get_node_or_null("NearTrees")
	# Контейнер с меткой «baked» уже сохранён в сцене: не генерируем деревья
	# заново, иначе ручные правки игрока потеряются.
	_near_baked = container != null and container.has_meta("baked")
	if container == null:
		return
	for child in container.get_children():
		if child is StaticBody3D:
			_near_nodes.append(child)


func _near_container() -> Node3D:
	var container := get_node_or_null("NearTrees") as Node3D
	if container != null:
		return container
	container = Node3D.new()
	container.name = "NearTrees"
	add_child(container)
	if Engine.is_editor_hint():
		var scene_root := get_tree().edited_scene_root
		if scene_root != null:
			container.owner = scene_root
	container.set_meta("baked", true)
	return container


## Одно дерево-объект: StaticBody3D с мешем и цилиндрической коллизией.
## Так его можно выбрать, перетащить и сохранить вместе со сценой.
func _add_near_tree(x: float, z: float, conifer: bool) -> void:
	var y: float = RuralHeight.terrain_height(x, z)
	var size_index: int = _near_rng.randi_range(0, CONIFER_HEIGHTS.size() - 1)
	var variant: int = _near_rng.randi_range(0, 5)
	var proto: Dictionary = _tree_prototype(conifer, size_index, variant)

	var body := StaticBody3D.new()
	body.name = "Tree_%d_%d" % [roundi(x * 10.0), roundi(z * 10.0)]
	body.position = Vector3(x, y, z)
	body.rotation.y = _near_rng.randf_range(0.0, TAU)
	var radius: float = proto["radius"]
	body.set_meta("tree_radius", radius)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = proto["mesh"]
	body.add_child(mesh_instance)

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0
	var collision := CollisionShape3D.new()
	collision.name = "Stem"
	collision.shape = shape
	collision.position = Vector3(0.0, 2.0, 0.0)
	body.add_child(collision)

	_near_container().add_child(body)
	_near_nodes.append(body)

	if Engine.is_editor_hint():
		var scene_root := get_tree().edited_scene_root
		if scene_root != null:
			body.owner = scene_root
			mesh_instance.owner = scene_root
			collision.owner = scene_root


## Регистрирует деревья-объекты в общем списке (после процедурного леса,
## чтобы индексы дальних деревьев в раскладке не сдвигались).
func _register_near_nodes() -> void:
	for body in _near_nodes:
		if not is_instance_valid(body):
			continue
		var id: int = _trees.size()
		_trees.append({
			"kind": "node",
			"pos": body.position,
			"initial_pos": body.position,
			"yaw": body.rotation.y,
			"radius": float(body.get_meta("tree_radius", 0.2)),
			"height": 4.0,
			"parts": [],
			"body": body,
			"node": body,
			"name": body.name,
		})
		_collider_ids[body.get_instance_id()] = id
		body.set_meta("tree_id", id)


## Прототип дерева нужной породы, размера и оттенка. Меши переиспользуются
## между деревьями: иначе сохранённая сцена распухнет от тысяч копий.
func _tree_prototype(conifer: bool, size_index: int, variant: int) -> Dictionary:
	var key := "%d_%d_%d" % [1 if conifer else 0, size_index, variant]
	if _prototypes.has(key):
		return _prototypes[key]

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var builder := TreeMeshBuilder.new()
	var tint: Color = RuralHeight.foliage_color(rng)
	var height: float
	var radius: float
	var trunk_height: float
	var bark: Color

	if conifer:
		height = CONIFER_HEIGHTS[size_index]
		radius = lerpf(0.15, 0.24, float(size_index) / 7.0)
		trunk_height = height * 0.62
		bark = Color(0.375, 0.265, 0.170, 1.0)
		_add_trunk_mesh(builder, radius, trunk_height, 6, bark)
		var leaf_color := _foliage_albedo(tint.darkened(0.08))
		var layers := [
			Vector3(0.12, 0.30, 0.46),
			Vector3(0.17, 0.30, 0.64),
			Vector3(0.23, 0.26, 0.82),
		]
		for layer in layers:
			var layer_radius: float = height * float(layer.x) * rng.randf_range(0.92, 1.08)
			var layer_height: float = height * float(layer.y)
			var center_y: float = height * float(layer.z)
			_add_cone_mesh(builder, layer_radius, layer_height, center_y, leaf_color)
	else:
		height = BROADLEAF_HEIGHTS[size_index]
		radius = lerpf(0.17, 0.28, float(size_index) / 7.0)
		trunk_height = height * 0.68
		bark = Color(0.430, 0.325, 0.215, 1.0)
		_add_trunk_mesh(builder, radius, trunk_height, 7, bark)
		var crown_radius: float = rng.randf_range(1.6, 2.4) * TREE_SCALE
		var crown_y: float = height * 0.84
		var leaf_color := _foliage_albedo(tint)
		var blob_count: int = rng.randi_range(4, 5)
		for i in blob_count:
			var angle: float = rng.randf_range(0.0, TAU)
			var spread: float = 0.0 if i == 0 else rng.randf_range(0.45, 0.8)
			var scale_factor: float = 1.0 if i == 0 else rng.randf_range(0.62, 0.85)
			var r: float = crown_radius * scale_factor
			var offset := Vector3(
				cos(angle) * crown_radius * spread,
				rng.randf_range(-0.14, 0.20) * crown_radius,
				sin(angle) * crown_radius * spread
			)
			_add_blob_mesh(
				builder,
				Vector3(r, r * rng.randf_range(0.62, 0.82), r),
				Vector3(offset.x, crown_y + offset.y, offset.z),
				leaf_color
			)

	var proto := {
		"mesh": builder.commit(_near_material),
		"radius": radius,
		"height": height,
	}
	_prototypes[key] = proto
	return proto


func _add_trunk_mesh(
	builder: TreeMeshBuilder, radius: float, height: float, sides: int, color: Color
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.62
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	builder.add_mesh(
		mesh, Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0)), color
	)


func _add_cone_mesh(
	builder: TreeMeshBuilder, radius: float, height: float, center_y: float, color: Color
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	var basis := Basis.IDENTITY.scaled_local(Vector3(radius * 2.0, height, radius * 2.0))
	builder.add_mesh(mesh, Transform3D(basis, Vector3(0.0, center_y, 0.0)), color)


func _add_blob_mesh(
	builder: TreeMeshBuilder, scale_value: Vector3, center: Vector3, color: Color
) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var basis := Basis.IDENTITY.scaled_local(scale_value)
	builder.add_mesh(mesh, Transform3D(basis, center), color)


## Тот же цвет, что даёт foliage_flat.gdshader для леса из MultiMesh.
## Альфа 0 — метка «листва качается» для foliage_tree.gdshader.
func _foliage_albedo(tint: Color) -> Color:
	var col := Color(0.15, 0.28, 0.075).lerp(Color(0.40, 0.55, 0.16), tint.g)
	col *= 0.75 + tint.r * 0.55
	return Color(col.r, col.g, col.b, 0.0)


# --- Кусты -----------------------------------------------------------------


func _scatter_bushes() -> void:
	var limit: float = RuralHeight.WORLD_HALF - 8.0
	var steps: int = int(ceil(limit * 2.0 / BUSH_CELL))
	for gz in steps:
		for gx in steps:
			var x: float = -limit + (float(gx) + 0.5) * BUSH_CELL
			var z: float = -limit + (float(gz) + 0.5) * BUSH_CELL
			x += _rng.randf_range(-BUSH_CELL * 0.45, BUSH_CELL * 0.45)
			z += _rng.randf_range(-BUSH_CELL * 0.45, BUSH_CELL * 0.45)
			var density: float = RuralHeight.forest_density(x, z)
			if density < 0.12 or _rng.randf() > clampf(density * 1.08, 0.0, 1.0):
				continue
			_add_bush(x, z)

	# Плотная подлесок у ворот базы: дорога петляет в зелени,
	# и базу не видно, пока не подойдёшь вплотную.
	var base: Vector2 = RuralHeight.BASE_CENTER
	for i in 220:
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = _rng.randf_range(30.0, 46.0)
		var x: float = base.x + cos(angle) * radius
		var z: float = base.y + sin(angle) * radius
		if RuralHeight.yard_mask(x, z) > 0.02:
			continue
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 1.2:
			continue
		_add_bush(x, z)


func _add_bush(x: float, z: float) -> void:
	var y: float = RuralHeight.terrain_height(x, z)
	var radius: float = _rng.randf_range(0.65, 1.55)
	var tint: Color = RuralHeight.foliage_color(_rng).darkened(0.16)
	var blobs: int = _rng.randi_range(2, 3)
	for i in blobs:
		var angle: float = _rng.randf_range(0.0, TAU)
		var spread: float = 0.0 if i == 0 else radius * _rng.randf_range(0.55, 1.0)
		var r: float = radius * (1.0 if i == 0 else _rng.randf_range(0.55, 0.8))
		var vertical: float = r * _rng.randf_range(1.0, 1.4)
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0))
		basis = basis.scaled_local(Vector3(r * 1.15, vertical, r * 1.15))
		_bushes.append(Transform3D(
			basis,
			Vector3(x + cos(angle) * spread, y + vertical * 0.65, z + sin(angle) * spread)
		))
		_bush_tints.append(Color(
			clampf(tint.r + _rng.randf_range(-0.04, 0.04), 0.0, 1.0),
			clampf(tint.g + _rng.randf_range(-0.04, 0.04), 0.0, 1.0),
			clampf(tint.b + _rng.randf_range(-0.03, 0.03), 0.0, 1.0),
			1.0
		))


# --- Трава -----------------------------------------------------------------


func _scatter_grass() -> void:
	var roads: Array[Dictionary] = ForestRoads.roads()
	var base: Vector2 = RuralHeight.BASE_CENTER

	# 1. Обочины дорог и заросшие колеи.
	for i in 800:
		if roads.is_empty():
			break
		var road: Dictionary = roads[_rng.randi_range(0, roads.size() - 1)]
		var pts: PackedVector3Array = road["points"]
		var half_width: float = road["half_width"]
		var overgrown: float = road["overgrown"]
		var row: int = _rng.randi_range(0, pts.size() - 1)
		var p: Vector3 = pts[row]
		var q: Vector3 = pts[mini(row + 1, pts.size() - 1)]
		var dir := Vector3(q.x - p.x, 0.0, q.z - p.z).normalized()
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		var lateral := Vector3(-dir.z, 0.0, dir.x)
		var offset: float
		if overgrown > 0.5 and _rng.randf() < 0.30:
			# Трава прямо в колее старой лесовозной дороги.
			offset = _rng.randf_range(-half_width * 0.72, half_width * 0.72)
		else:
			var side: float = 1.0 if _rng.randf() > 0.5 else -1.0
			offset = side * _rng.randf_range(half_width + 0.7, half_width + 4.2)
		var x: float = p.x + lateral.x * offset
		var z: float = p.z + lateral.z * offset
		if RuralHeight.yard_mask(x, z) > 0.05:
			continue
		_append_grass(x, z)

	# 2. Деревенский луг.
	for i in 600:
		var x: float = RuralHeight.SETTLEMENT_CENTER.x + _rng.randf_range(-52.0, 52.0)
		var z: float = RuralHeight.SETTLEMENT_CENTER.y + _rng.randf_range(-40.0, 40.0)
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 0.6:
			continue
		_append_grass(x, z)

	# 3. Поляны.
	for i in 500:
		var glade: Vector3 = RuralHeight.GLADES[_rng.randi_range(0, RuralHeight.GLADES.size() - 1)]
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = sqrt(_rng.randf()) * glade.z * 0.95
		_append_grass(glade.x + cos(angle) * radius, glade.y + sin(angle) * radius)

	# 4. Кольцо вокруг базы: высокая трава у кромки леса.
	for i in 300:
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = _rng.randf_range(21.0, 40.0)
		var x: float = base.x + cos(angle) * radius
		var z: float = base.y + sin(angle) * radius
		if RuralHeight.yard_mask(x, z) > 0.03:
			continue
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 0.5:
			continue
		_append_grass(x, z)

	# 5. Редкая трава на лесной подстилке.
	for i in 1000:
		var x: float = _rng.randf_range(-392.0, 392.0)
		var z: float = _rng.randf_range(-392.0, 392.0)
		if RuralHeight.forest_density(x, z) < 0.30:
			continue
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 0.5:
			continue
		if _rng.randf() > 0.62:
			continue
		_append_grass(x, z)


func _append_grass(x: float, z: float) -> void:
	if absf(x) > RuralHeight.WORLD_HALF - 2.0 or absf(z) > RuralHeight.WORLD_HALF - 2.0:
		return
	var y: float = RuralHeight.terrain_height(x, z)
	var scale: float = _rng.randf_range(0.65, 1.25)
	var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0))
	basis = basis.scaled_local(Vector3(scale, scale * _rng.randf_range(0.8, 1.3), scale))
	_grass.append(Transform3D(basis, Vector3(x, y - 0.02, z)))
	_grass_data.append(Color(_rng.randf(), _rng.randf(), 0.0, 1.0))


# --- Камни, стволы, пни ----------------------------------------------------


func _scatter_rocks() -> void:
	if not ROCKS_ENABLED:
		return
	# Заметные камни в чаще.
	var placed: int = 0
	for _attempt in 40000:
		if placed >= 180:
			break
		var x: float = _rng.randf_range(-390.0, 390.0)
		var z: float = _rng.randf_range(-390.0, 390.0)
		if RuralHeight.forest_density(x, z) < 0.22:
			continue
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 2.0:
			continue
		if RuralHeight.yard_mask(x, z) > 0.03:
			continue
		var scale: float = _rng.randf_range(0.35, 1.5)
		if _rng.randf() < 0.06:
			scale *= 1.9
		var y: float = RuralHeight.terrain_height(x, z)
		var basis := Basis.from_euler(Vector3(
			_rng.randf_range(-0.2, 0.2),
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.2, 0.2)
		))
		basis = basis.scaled_local(Vector3(scale * 1.2, scale * 0.62, scale))
		_rocks.append(Transform3D(basis, Vector3(x, y + scale * 0.12, z)))
		var shade: float = _rng.randf_range(0.30, 0.50)
		_rock_colors.append(Color(shade, shade * 0.98, shade * 0.93))
		if scale > 0.85:
			_rock_colliders.append({"pos": Vector3(x, y + scale * 0.35, z), "radius": scale * 0.9})
		placed += 1


func _scatter_details() -> void:
	_scatter_rocks()

	# Без леса не нужны ни поваленные стволы, ни пни.
	if not DETAILS_ENABLED:
		return

	# Поваленные стволы.
	var placed: int = 0
	for _attempt in 16000:
		if placed >= 60:
			break
		var x: float = _rng.randf_range(-385.0, 385.0)
		var z: float = _rng.randf_range(-385.0, 385.0)
		if RuralHeight.forest_density(x, z) < 0.25:
			continue
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 2.4:
			continue
		var length: float = _rng.randf_range(3.0, 7.5)
		var radius: float = _rng.randf_range(0.22, 0.46)
		var yaw: float = _rng.randf_range(0.0, TAU)
		var basis := Basis.from_euler(Vector3(0.0, yaw, PI * 0.5))
		basis = basis.scaled_local(Vector3(radius, length, radius))
		var y: float = RuralHeight.terrain_height(x, z)
		_logs.append(Transform3D(basis, Vector3(x, y + radius * 0.85, z)))
		placed += 1

	# Пни — следы старых вырубок.
	placed = 0
	for _attempt in 20000:
		if placed >= 120:
			break
		var x: float = _rng.randf_range(-388.0, 388.0)
		var z: float = _rng.randf_range(-388.0, 388.0)
		var near_glade: bool = RuralHeight.glade_mask(x, z) > 0.25
		if not near_glade and RuralHeight.forest_density(x, z) < 0.30:
			continue
		if RuralHeight.road_distance(x, z) < RuralHeight.road_half_width(x, z) + 1.4:
			continue
		if RuralHeight.yard_mask(x, z) > 0.03:
			continue
		var radius: float = _rng.randf_range(0.32, 0.65)
		var height: float = _rng.randf_range(0.45, 0.95)
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0))
		basis = basis.scaled_local(Vector3(radius, height, radius))
		var y: float = RuralHeight.terrain_height(x, z)
		_stumps.append(Transform3D(basis, Vector3(x, y + height * 0.45, z)))
		placed += 1


# --- Визуал ----------------------------------------------------------------


func _build_visuals() -> void:
	var trunk_conifer_mesh := CylinderMesh.new()
	trunk_conifer_mesh.top_radius = 0.62
	trunk_conifer_mesh.bottom_radius = 1.0
	trunk_conifer_mesh.height = 1.0
	trunk_conifer_mesh.radial_segments = 6
	trunk_conifer_mesh.rings = 1

	var trunk_broadleaf_mesh := CylinderMesh.new()
	trunk_broadleaf_mesh.top_radius = 0.72
	trunk_broadleaf_mesh.bottom_radius = 1.0
	trunk_broadleaf_mesh.height = 1.0
	trunk_broadleaf_mesh.radial_segments = 7
	trunk_broadleaf_mesh.rings = 1

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.02
	cone_mesh.bottom_radius = 0.5
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 8
	cone_mesh.rings = 1

	var blob_mesh := SphereMesh.new()
	blob_mesh.radius = 1.0
	blob_mesh.height = 2.0
	blob_mesh.radial_segments = 7
	blob_mesh.rings = 4

	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 1.0
	bush_mesh.height = 2.0
	bush_mesh.radial_segments = 7
	bush_mesh.rings = 3

	var conifer_bark := StandardMaterial3D.new()
	conifer_bark.albedo_color = Color(0.375, 0.265, 0.170)
	conifer_bark.roughness = 0.94

	var broadleaf_bark := StandardMaterial3D.new()
	broadleaf_bark.albedo_color = Color(0.430, 0.325, 0.215)
	broadleaf_bark.roughness = 0.93

	var foliage_material := ShaderMaterial.new()
	foliage_material.shader = FOLIAGE_SHADER

	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 3

	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color(1.0, 1.0, 1.0)
	rock_material.roughness = 0.95
	rock_material.vertex_color_use_as_albedo = true

	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 1.0
	log_mesh.bottom_radius = 1.0
	log_mesh.height = 1.0
	log_mesh.radial_segments = 7
	log_mesh.rings = 1

	var log_material := StandardMaterial3D.new()
	log_material.albedo_color = Color(0.255, 0.185, 0.115)
	log_material.roughness = 0.97

	var stump_mesh := CylinderMesh.new()
	stump_mesh.top_radius = 1.0
	stump_mesh.bottom_radius = 1.08
	stump_mesh.height = 1.0
	stump_mesh.radial_segments = 8
	stump_mesh.rings = 1

	var stump_material := StandardMaterial3D.new()
	stump_material.albedo_color = Color(0.285, 0.205, 0.125)
	stump_material.roughness = 0.97

	if TREES_ENABLED:
		_add_multimesh(trunk_conifer_mesh, _trunk_conifer, conifer_bark, "TreeTrunks", true, false, true)
		_add_multimesh(trunk_broadleaf_mesh, _trunk_broadleaf, broadleaf_bark, "BroadleafTrunks", true, false, true)
		_add_multimesh(cone_mesh, _cones, foliage_material, "ConiferCrowns", true, true, true, _cone_tints)
		_add_multimesh(blob_mesh, _blobs, foliage_material, "BroadleafCrowns", true, true, true, _blob_tints)
	if BUSHES_ENABLED:
		_add_multimesh(bush_mesh, _bushes, foliage_material, "Bushes", true, true, false, _bush_tints)
	if ROCKS_ENABLED:
		_add_multimesh(rock_mesh, _rocks, rock_material, "Rocks", false, false, false, _rock_colors, true)
	if TREES_ENABLED:
		_add_multimesh(log_mesh, _logs, log_material, "FallenLogs", true, false, false)
		_add_multimesh(stump_mesh, _stumps, stump_material, "Stumps", true, false, false)

	if GRASS_ENABLED:
		_build_grass()


func _build_grass() -> void:
	var mesh: ArrayMesh = _make_grass_mesh()
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.use_custom_data = true
	multimesh.instance_count = _grass.size()
	for i in _grass.size():
		multimesh.set_instance_transform(i, _grass[i])
		multimesh.set_instance_custom_data(i, _grass_data[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Трава нужна только рядом: дальше это просто шум пикселей, а вершин много.
	instance.visibility_range_end = 90.0
	instance.visibility_range_end_margin = 12.0
	add_child(instance)


func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_width: float = 0.30
	var height: float = 0.44

	for plane in 2:
		var angle: float = float(plane) * PI * 0.5
		var right := Vector3(cos(angle), 0.0, sin(angle)) * half_width
		var normal := Vector3(-sin(angle), 0.0, cos(angle))

		var a := -right
		var b := right
		var c := right + Vector3(0.0, height, 0.0)
		var d := -right + Vector3(0.0, height, 0.0)

		st.set_normal(normal)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(a)
		st.set_normal(normal)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(b)
		st.set_normal(normal)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(c)

		st.set_normal(normal)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(a)
		st.set_normal(normal)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(c)
		st.set_normal(normal)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(d)

	return st.commit()


func _add_multimesh(
	mesh: Mesh,
	transforms: Array[Transform3D],
	material: Material,
	node_name: String,
	cast_shadow: bool,
	use_custom_data: bool,
	moves_with_player: bool,
	tints: Array[Color] = [],
	use_colors: bool = false
) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.use_custom_data = use_custom_data
	multimesh.use_colors = use_colors
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if use_custom_data and i < tints.size():
			multimesh.set_instance_custom_data(i, tints[i])
		if use_colors and i < tints.size():
			multimesh.set_instance_color(i, tints[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Дальний план: деревья/камни исчезают за пределами видимости, не
	# нагружая ни основной, ни теневой проход.
	instance.visibility_range_end = 260.0 if node_name == "Rocks" else 450.0
	instance.visibility_range_end_margin = 30.0
	add_child(instance)
	_multimeshes[node_name] = instance

	# Деревья можно перетаскивать по всей карте: AABB должен покрывать мир,
	# иначе переставленное дерево может исчезнуть из вида.
	if moves_with_player:
		instance.custom_aabb = AABB(
			Vector3(-450.0, -80.0, -450.0), Vector3(900.0, 300.0, 900.0)
		)
	return instance


# --- Коллизии --------------------------------------------------------------


func _build_collisions() -> void:
	if not _trees.is_empty():
		# Стволы дальнего леса — один общий StaticBody3D. Отдельное тело на
		# каждое дерево упирается в лимит тел Jolt, а для перетаскивания
		# достаточно сдвигать нужную CollisionShape3D.
		var far_body := StaticBody3D.new()
		far_body.name = "FarTreeCollision"
		add_child(far_body)
		_far_tree_body = far_body

		var shape_index: int = 0
		for i in _trees.size():
			var tree: Dictionary = _trees[i]
			# У деревьев-объектов коллизия уже лежит внутри их собственной ноды.
			if tree.get("kind", "mesh") == "node":
				continue

			var shape := CylinderShape3D.new()
			shape.radius = tree["radius"]
			shape.height = 4.0

			var collision := CollisionShape3D.new()
			collision.name = "Stem_%d" % i
			collision.shape = shape
			collision.position = Vector3(tree["pos"].x, tree["pos"].y + 2.0, tree["pos"].z)
			far_body.add_child(collision)

			tree["body"] = far_body
			tree["shape_node"] = collision
			tree["shape_index"] = shape_index
			_far_shape_ids[shape_index] = i
			shape_index += 1

	if ROCKS_ENABLED and not _rock_colliders.is_empty():
		var rock_body := StaticBody3D.new()
		rock_body.name = "RockCollision"
		add_child(rock_body)
		for rock in _rock_colliders:
			var shape := SphereShape3D.new()
			shape.radius = rock["radius"]
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = rock["pos"]
			rock_body.add_child(collision)


# --- Перестановка деревьев игроком -----------------------------------------


## Номер дерева по объекту-коллайдеру (луч попал в ствол). -1 — не дерево.
## shape_index нужен для дальнего леса: его стволы лежат в одном теле,
## и конкретное дерево определяется номером формы.
func tree_id_for_collider(collider: Object, shape_index: int = -1) -> int:
	if collider == null or not is_instance_valid(collider):
		return -1
	var id: int = int(_collider_ids.get(collider.get_instance_id(), -1))
	if id >= 0:
		return id
	if shape_index >= 0 and collider == _far_tree_body:
		return int(_far_shape_ids.get(shape_index, -1))
	return -1


## Позиция дерева (основание ствола, на земле).
func get_tree_position(tree_id: int) -> Vector3:
	if tree_id < 0 or tree_id >= _trees.size():
		return Vector3.ZERO
	return _trees[tree_id]["pos"]


## Переставить дерево. pos — точка на земле, yaw — поворот вокруг Y.
func move_tree(tree_id: int, pos: Vector3, yaw: float, snap_to_ground: bool = true) -> void:
	if tree_id < 0 or tree_id >= _trees.size():
		return

	var tree: Dictionary = _trees[tree_id]
	var target := pos
	if snap_to_ground:
		target.y = RuralHeight.terrain_height(target.x, target.z)

	if tree.get("kind", "mesh") == "node":
		# Дерево-объект двигается как обычная нода — вместе с мешем и коллизией.
		var node: Node3D = tree["node"]
		node.position = target
		node.rotation.y = yaw
	else:
		var root := Transform3D(Basis(Vector3.UP, yaw), target)
		var parts: Array = tree["parts"]
		for part in parts:
			var node: MultiMeshInstance3D = _multimeshes.get(part["group"], null)
			if node == null:
				continue
			var local: Transform3D = part["local"]
			node.multimesh.set_instance_transform(int(part["index"]), root * local)

		var body: StaticBody3D = tree["body"]
		if body != null:
			var shape_node: CollisionShape3D = tree.get("shape_node", null)
			if shape_node != null:
				shape_node.position = Vector3(target.x, target.y + 2.0, target.z)
			else:
				body.global_position = target

	tree["pos"] = target
	tree["yaw"] = yaw


## Временно отключить коллизию дерева, пока его несут.
func set_tree_ghost(tree_id: int, ghost: bool) -> void:
	if tree_id < 0 or tree_id >= _trees.size():
		return
	var tree: Dictionary = _trees[tree_id]
	if tree.get("kind", "mesh") == "node":
		var body: StaticBody3D = tree["body"]
		if body != null:
			body.collision_layer = 0 if ghost else 1
	else:
		var shape_node: CollisionShape3D = tree.get("shape_node", null)
		if shape_node != null:
			shape_node.disabled = ghost


## Вернуть дерево на исходную позицию.
func reset_tree(tree_id: int) -> void:
	if tree_id < 0 or tree_id >= _trees.size():
		return
	var tree: Dictionary = _trees[tree_id]
	move_tree(tree_id, tree["initial_pos"], 0.0, false)


## Вернуть все деревья на исходные места и стереть сохранённую раскладку.
func reset_layout() -> void:
	for i in _trees.size():
		reset_tree(i)
	if FileAccess.file_exists(LAYOUT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))


func save_layout() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "epoch", RuralHeight.WORLD_EPOCH)
	for i in _trees.size():
		var tree: Dictionary = _trees[i]
		if tree.get("kind", "mesh") == "node":
			# Дерево-объект живёт в сцене, поэтому раскладку храним по имени
			# и запоминаем исходную позицию: ручные правки сцены не затираем.
			config.set_value("near", tree["name"], {
				"from": tree["initial_pos"],
				"pos": tree["pos"],
				"yaw": tree["yaw"],
			})
		else:
			config.set_value("trees", "pos_%d" % i, tree["pos"])
			config.set_value("trees", "yaw_%d" % i, tree["yaw"])
	config.save(LAYOUT_PATH)


func _load_layout() -> void:
	var config := ConfigFile.new()
	if config.load(LAYOUT_PATH) != OK:
		return
	# Раскладка от другой версии мира невалидна: рельеф и дороги сдвинулись,
	# поэтому деревья лучше расставить заново, чем тащить их из старой карты.
	if int(config.get_value("meta", "epoch", -1)) != RuralHeight.WORLD_EPOCH:
		return
	for i in _trees.size():
		var tree: Dictionary = _trees[i]
		if tree.get("kind", "mesh") == "node":
			var saved: Variant = config.get_value("near", tree["name"], null)
			if saved is Dictionary:
				var data: Dictionary = saved
				# Применяем только если сцену не правили руками: иначе
				# старое игровое перемещение перетащило бы дерево обратно.
				var from: Vector3 = data.get("from", tree["initial_pos"])
				if tree["pos"].is_equal_approx(from):
					move_tree(i, data.get("pos", from), float(data.get("yaw", 0.0)), false)
		else:
			var pos: Variant = config.get_value("trees", "pos_%d" % i, null)
			if pos is Vector3:
				var tree_pos: Vector3 = pos
				var yaw: float = float(config.get_value("trees", "yaw_%d" % i, 0.0))
				move_tree(i, tree_pos, yaw, false)
