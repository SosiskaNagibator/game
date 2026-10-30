class_name CargoBox
extends RigidBody3D
## Ящик, который игрок может взять, перенести и поставить в кузов.
##
## Слои:
##   1 — обычная физика (ящик лежит в мире);
##   2 — «только для наведения» (ящик загружен в кузов: луч игрока его
##       видит, но физика машины/игрока с ним не сталкивается).
##   Во время переноски слой 0 — ящик не участвует в столкновениях.

const MODEL_SCENE: PackedScene = preload(
	"res://assets/models/wooden_box/woodbox.glb"
)
const LAYER_WORLD := 1
const LAYER_INTERACTION := 2

@export_range(1.0, 500.0, 1.0) var cargo_mass: float = 75.0
@export_range(0.05, 2.0, 0.01) var model_scale: float = 1.0
## Контрабандный груз: CargoSystem.has_contraband() вернёт true,
## пока хотя бы один такой ящик стоит в кузове.
@export var is_contraband: bool = false

var _model: Node3D = null
var _collision: CollisionShape3D = null


func _ready() -> void:
	add_to_group("cargo")
	mass = cargo_mass

	_model = get_node_or_null("Model") as Node3D
	if _model == null:
		_model = MODEL_SCENE.instantiate() as Node3D
		_model.name = "Model"
		add_child(_model)
	_model.scale = Vector3.ONE * model_scale

	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "CollisionShape3D"
		add_child(_collision)

	_fit_collision()
	set_free()


## Подобрать коллайдер под визуальные границы модели.
func _fit_collision() -> void:
	var bounds := _get_visual_aabb()
	if bounds.size.length_squared() < 0.0001:
		bounds = AABB(Vector3(-0.3, -0.015, -0.3), Vector3(0.6, 0.31, 0.6))

	var shape := BoxShape3D.new()
	shape.size = bounds.size
	_collision.shape = shape
	_collision.position = bounds.get_center()


## Точные границы видимых вершин. Нельзя оборачивать локальный AABB меша:
## у woodbox.glb он сильно раздут (7.2 x 11.2 x 0.66), а реальная модель —
## куб ~0.615 м. Из-за повёрнутых углов такого AABB коллайдер вырастал вдвое.
func _get_visual_aabb() -> AABB:
	var result := AABB()
	var has_bounds := false
	var to_local := global_transform.affine_inverse()

	for node in _collect_meshes(_model):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var xform := to_local * mesh_instance.global_transform
		var bounds := _get_mesh_vertex_bounds(mesh_instance.mesh, xform)
		if not bool(bounds["valid"]):
			continue
		var aabb: AABB = bounds["aabb"]
		if not has_bounds:
			result = aabb
			has_bounds = true
		else:
			result = result.merge(aabb)

	return result


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


## Ящик в руках: физика выключена, столкновения выключены.
func set_held() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0


## Ящик стоит в кузове: физика выключена, но луч игрока его видит.
func set_loaded() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = LAYER_INTERACTION
	collision_mask = 0


## Ящик брошен в мир: обычная физика.
func set_free() -> void:
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = LAYER_WORLD
	collision_mask = LAYER_WORLD
	sleeping = false
