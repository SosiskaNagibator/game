@tool
class_name DecorGrounding
extends Node3D
## Ставит декор на землю и (в игре) схлопывает сотни одинаковых деревьев
## и камней в MultiMeshInstance3D.
##
## В сцене Decor.tscn лежит ~1700 отдельных инстансов Tree_*.tscn/Rock_1.tscn.
## Каждый из них — Node3D + MeshInstance3D + пустой StaticBody3D, то есть
## отдельный draw call (и ещё один в shadow pass). Здесь мы группируем их
## по типу меша и чанку 160 м, получая вместо тысяч нод несколько десятков
## MultiMesh с корректной видимостью и тенями.
##
## В редакторе батчинг не выполняется: сцена остаётся редактируемой.

const GROUND_CLEARANCE := 0.02
## Размер чанка, м. Мельче — лучше отсечение, но больше draw call.
const BATCH_CELL := 160.0
const TREE_VISIBILITY := 450.0
const ROCK_VISIBILITY := 260.0
const TREE_MIN_HEIGHT := 2.2

@export var batching_enabled: bool = true


func _ready() -> void:
	for child in get_children():
		var prop := child as Node3D
		if prop == null:
			continue
		var bottom: float = bottom_offset(prop)
		if not is_finite(bottom):
			continue
		prop.position.y = (
			RuralHeight.terrain_height(prop.position.x, prop.position.z)
			- bottom
			+ GROUND_CLEARANCE
		)

	if Engine.is_editor_hint() or not batching_enabled:
		return
	_batch_props()


## Собираем меши в чанковые MultiMesh и удаляем исходные инстансы.
func _batch_props() -> void:
	var groups: Dictionary = {}
	var props: Array[Node3D] = []

	for child in get_children():
		var prop := child as Node3D
		if prop == null:
			continue
		var source := _first_mesh_instance(prop)
		if source == null or source.mesh == null:
			continue

		props.append(prop)
		var mesh: Mesh = source.mesh
		var material: Material = source.material_override
		var cell := Vector2i(
			floori(prop.global_position.x / BATCH_CELL),
			floori(prop.global_position.z / BATCH_CELL)
		)
		var material_id: int = material.get_instance_id() if material != null else 0
		var key := "%d|%d|%d|%d" % [mesh.get_instance_id(), material_id, cell.x, cell.y]

		var group: Dictionary = groups.get(key, {})
		if group.is_empty():
			var world_size: Vector3 = (
				mesh.get_aabb().size * source.global_transform.basis.get_scale()
			)
			var is_tree: bool = (
				world_size.y >= TREE_MIN_HEIGHT
				or maxf(world_size.x, world_size.z) >= TREE_MIN_HEIGHT
			)
			group = {
				"mesh": mesh,
				"material": material,
				"transforms": [],
				"shadow": is_tree,
				"visibility": TREE_VISIBILITY if is_tree else ROCK_VISIBILITY,
				"cell": cell,
			}
			groups[key] = group

		var relative := global_transform.affine_inverse() * source.global_transform
		var transforms: Array = group["transforms"]
		transforms.append(relative)

	if groups.is_empty():
		return

	var index := 0
	for group in groups.values():
		_create_batch(group, index)
		index += 1

	for prop in props:
		prop.visible = false
		prop.queue_free()


func _create_batch(group: Dictionary, index: int) -> void:
	var transforms: Array = group["transforms"]
	if transforms.is_empty():
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = group["mesh"]
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

	var cell: Vector2i = group["cell"]
	var batch := MultiMeshInstance3D.new()
	batch.name = "Batch_%d_%d_%d" % [index, cell.x, cell.y]
	batch.multimesh = multimesh
	batch.material_override = group["material"]
	batch.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if group["shadow"]
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	batch.visibility_range_end = group["visibility"]
	batch.visibility_range_end_margin = float(group["visibility"]) * 0.1
	add_child(batch)


static func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null


static func bottom_offset(root: Node3D) -> float:
	return _lowest_mesh_y(root, Transform3D.IDENTITY, root)


static func _lowest_mesh_y(node: Node, parent_transform: Transform3D, root: Node3D) -> float:
	var current_transform := parent_transform
	if node == root:
		current_transform = Transform3D(root.transform.basis, Vector3.ZERO)
	elif node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform

	var lowest: float = INF
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner in 8:
			var point: Vector3 = bounds.get_endpoint(corner)
			lowest = minf(lowest, (current_transform * point).y)

	for child in node.get_children():
		lowest = minf(lowest, _lowest_mesh_y(child, current_transform, root))
	return lowest
