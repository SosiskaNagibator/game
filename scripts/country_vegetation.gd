@tool
extends Node3D
## Деревья, кусты и трава вдоль просёлка.
## Всё собрано через MultiMesh, поэтому сотни объектов стоят почти ничего.

const FOLIAGE_SHADER := preload("res://shaders/foliage_flat.gdshader")
const GRASS_SHADER := preload("res://shaders/grass_blade.gdshader")

const RNG_SEED := 77123

var _rng := RandomNumberGenerator.new()
var _trunk_transforms: Array[Transform3D] = []
var _foliage_transforms: Array[Transform3D] = []
var _foliage_data: Array[Color] = []
var _tree_colliders: Array[Dictionary] = []
var _bush_colliders: Array[Dictionary] = []


func _ready() -> void:
	if get_node_or_null("TreeTrunks") != null:
		return
	_rng.seed = RNG_SEED
	_scatter_trees()
	_scatter_bushes()
	_build_trees()
	_build_grass()
	_build_collisions()


# --- Деревья ---------------------------------------------------------------


func _scatter_trees() -> void:
	var clusters: Array[Vector2] = [
		Vector2(RuralHeight.road_x(118.0) - 15.0, 118.0),
		Vector2(RuralHeight.road_x(92.0) - 17.0, 92.0),
		Vector2(RuralHeight.road_x(62.0) - 13.0, 62.0),
		Vector2(RuralHeight.road_x(34.0) + 20.0, 34.0),
		Vector2(RuralHeight.road_x(8.0) - 19.0, 8.0),
		Vector2(RuralHeight.road_x(-28.0) + 17.0, -28.0),
		Vector2(RuralHeight.road_x(-62.0) - 24.0, -62.0),
		Vector2(RuralHeight.road_x(-110.0) + 21.0, -110.0),
		Vector2(RuralHeight.road_x(-155.0) - 28.0, -155.0),
		Vector2(RuralHeight.road_x(-205.0) + 26.0, -205.0),
		Vector2(RuralHeight.road_x(-255.0) - 30.0, -255.0),
		Vector2(-42.0, 150.0),
		Vector2(48.0, 72.0),
		Vector2(-55.0, 165.0),
	]

	for center in clusters:
		var tree_count: int = _rng.randi_range(3, 6)
		for i in tree_count:
			var angle: float = _rng.randf_range(0.0, TAU)
			var radius: float = _rng.randf_range(1.5, 9.0)
			var x: float = center.x + cos(angle) * radius
			var z: float = center.y + sin(angle) * radius
			_try_add_tree(x, z, _rng.randf_range(0.85, 1.25))

	# Отдельно стоящие деревья на склонах.
	for i in 26:
		var z: float = _rng.randf_range(-300.0, 240.0)
		var side: float = 1.0 if _rng.randf() > 0.5 else -1.0
		var x: float = RuralHeight.road_x(z) + side * _rng.randf_range(12.0, 70.0)
		_try_add_tree(x, z, _rng.randf_range(0.8, 1.35))


func _try_add_tree(x: float, z: float, size_scale: float) -> void:
	if absf(x) > RuralHeight.WORLD_HALF - 12.0 or absf(z) > RuralHeight.WORLD_HALF - 12.0:
		return
	if absf(x - RuralHeight.road_x(z)) < 9.0:
		return
	if RuralHeight.yard_mask(x, z) > 0.02:
		return
	_add_tree(x, z, size_scale)


func _add_tree(x: float, z: float, size_scale: float) -> void:
	var y: float = RuralHeight.terrain_height(x, z)
	var trunk_height: float = _rng.randf_range(2.6, 3.8) * size_scale
	var crown_radius: float = _rng.randf_range(2.1, 3.1) * size_scale
	var tint: Color = RuralHeight.foliage_color(_rng)

	_tree_colliders.append({
		"pos": Vector3(x, y, z),
		"radius": 0.31 * size_scale,
		"height": trunk_height,
	})

	var trunk_basis := Basis.from_euler(Vector3(
		_rng.randf_range(-0.04, 0.04),
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(-0.04, 0.04)
	))
	trunk_basis = trunk_basis.scaled_local(Vector3(size_scale, trunk_height, size_scale))
	_trunk_transforms.append(Transform3D(trunk_basis, Vector3(x, y + trunk_height * 0.5, z)))

	var blob_count: int = _rng.randi_range(3, 5)
	for i in blob_count:
		var offset := Vector3(
			_rng.randf_range(-0.62, 0.62) * crown_radius,
			_rng.randf_range(-0.18, 0.42) * crown_radius,
			_rng.randf_range(-0.62, 0.62) * crown_radius
		)
		var blob_scale := Vector3(
			_rng.randf_range(0.62, 0.95) * crown_radius,
			_rng.randf_range(0.52, 0.78) * crown_radius,
			_rng.randf_range(0.62, 0.95) * crown_radius
		)

		var basis := Basis.from_euler(Vector3(
			_rng.randf_range(-0.15, 0.15),
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.15, 0.15)
		))
		basis = basis.scaled_local(blob_scale)
		var center := Vector3(
			x + offset.x,
			y + trunk_height * 0.94 + offset.y,
			z + offset.z
		)
		_foliage_transforms.append(Transform3D(basis, center))

		var blob_tint := Color(
			clampf(tint.r + _rng.randf_range(-0.06, 0.08), 0.0, 1.0),
			clampf(tint.g + _rng.randf_range(-0.06, 0.08), 0.0, 1.0),
			clampf(tint.b + _rng.randf_range(-0.05, 0.05), 0.0, 1.0),
			1.0
		)
		_foliage_data.append(blob_tint)


func _scatter_bushes() -> void:
	for i in 30:
		var z: float = _rng.randf_range(-140.0, 190.0)
		var side: float = 1.0 if _rng.randf() > 0.5 else -1.0
		var x: float = RuralHeight.road_x(z) + side * _rng.randf_range(7.4, 13.5)
		if RuralHeight.yard_mask(x, z) > 0.02:
			continue
		if absf(x - RuralHeight.road_x(z)) < 6.4:
			continue
		var y: float = RuralHeight.terrain_height(x, z)
		var radius: float = _rng.randf_range(0.55, 1.15)
		_bush_colliders.append({
			"pos": Vector3(x, y, z),
			"radius": radius * 1.2,
			"height": radius * 1.4,
		})
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0))
		basis = basis.scaled_local(Vector3(radius * 1.4, radius, radius * 1.4))
		_foliage_transforms.append(Transform3D(basis, Vector3(x, y + radius * 0.55, z)))
		var tint: Color = RuralHeight.foliage_color(_rng)
		_foliage_data.append(Color(tint.r * 0.86, tint.g * 0.9, tint.b * 0.8, 1.0))


func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.27
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 7
	trunk_mesh.rings = 1

	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.27, 0.20, 0.13)
	trunk_material.roughness = 0.95

	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 1.0
	foliage_mesh.height = 2.0
	foliage_mesh.radial_segments = 7
	foliage_mesh.rings = 4

	var foliage_material := ShaderMaterial.new()
	foliage_material.shader = FOLIAGE_SHADER

	_add_multimesh(trunk_mesh, _trunk_transforms, trunk_material, "TreeTrunks", true, false)
	_add_multimesh(foliage_mesh, _foliage_transforms, foliage_material, "TreeCrowns", true, true)


# --- Трава -----------------------------------------------------------------


func _build_grass() -> void:
	var mesh: ArrayMesh = _make_grass_mesh()
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER

	var target_count: int = 36000
	var transforms: Array[Transform3D] = []
	var data: Array[Color] = []
	var attempts: int = 0
	var max_attempts: int = target_count * 14

	while transforms.size() < target_count and attempts < max_attempts:
		attempts += 1
		var z: float = _rng.randf_range(-40.0, 240.0)
		var x: float = RuralHeight.road_x(z) + _rng.randf_range(-26.0, 30.0)
		if absf(x - RuralHeight.road_x(z)) < 5.0:
			continue
		if RuralHeight.yard_mask(x, z) > 0.18:
			continue

		var y: float = RuralHeight.terrain_height(x, z)
		var scale: float = _rng.randf_range(0.70, 1.20)
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0))
		basis = basis.scaled_local(Vector3(scale, scale * _rng.randf_range(0.8, 1.25), scale))
		transforms.append(Transform3D(basis, Vector3(x, y - 0.02, z)))
		data.append(Color(_rng.randf(), _rng.randf(), 0.0, 1.0))

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.use_custom_data = true
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_custom_data(i, data[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_width: float = 0.34
	var height: float = 0.52

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


# --- Коллизии --------------------------------------------------------------


func _build_collisions() -> void:
	var body := StaticBody3D.new()
	body.name = "VegetationCollision"
	add_child(body)

	for tree in _tree_colliders:
		var center: Vector3 = tree["pos"] + Vector3(0.0, tree["height"] * 0.5, 0.0)
		_add_cylinder_shape(body, tree["radius"], tree["height"], center)

	for bush in _bush_colliders:
		var center: Vector3 = bush["pos"] + Vector3(0.0, bush["height"] * 0.5, 0.0)
		_add_cylinder_shape(body, bush["radius"], bush["height"], center)


func _add_cylinder_shape(
	body: StaticBody3D, radius: float, height: float, center: Vector3
) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


# --- Общее -----------------------------------------------------------------


func _add_multimesh(
	mesh: Mesh,
	transforms: Array[Transform3D],
	material: Material,
	node_name: String,
	cast_shadow: bool,
	custom_data: bool
) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.use_custom_data = custom_data
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if custom_data and i < _foliage_data.size():
			multimesh.set_instance_custom_data(i, _foliage_data[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(instance)
