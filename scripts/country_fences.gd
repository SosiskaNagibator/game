@tool
extends Node3D
## Заборы из столбов с колючей проволокой вдоль дороги и линии электропередачи.

const RNG_SEED := 20260426

var _rng := RandomNumberGenerator.new()
var _wood_material: StandardMaterial3D
var _dark_wood_material: StandardMaterial3D
var _wire_material: StandardMaterial3D


func _ready() -> void:
	if get_node_or_null("FencePosts") != null:
		return
	_rng.seed = RNG_SEED
	_create_materials()
	_build_fences()
	_build_power_line()


func _create_materials() -> void:
	_wood_material = StandardMaterial3D.new()
	_wood_material.albedo_color = Color(0.38, 0.29, 0.19)
	_wood_material.roughness = 0.95

	_dark_wood_material = StandardMaterial3D.new()
	_dark_wood_material.albedo_color = Color(0.22, 0.16, 0.10)
	_dark_wood_material.roughness = 0.95

	_wire_material = StandardMaterial3D.new()
	_wire_material.albedo_color = Color(0.28, 0.28, 0.26)
	_wire_material.metallic = 0.6
	_wire_material.roughness = 0.55


func _build_fences() -> void:
	var post_transforms: Array[Transform3D] = []
	var wire_transforms: Array[Transform3D] = []
	var sides: Array[int] = [-1, 1]

	for side in sides:
		var posts: Array[Vector3] = []
		var z: float = 300.0
		while z >= -340.0:
			var x: float = RuralHeight.road_x(z) + float(side) * RuralHeight.FENCE_OFFSET
			var yard: float = RuralHeight.yard_mask(x, z)
			# Въезд на базу — разрыв в заборе с восточной стороны.
			var inside_entrance: bool = side > 0 and z > 76.0 and z < 122.0
			if yard < 0.02 and not inside_entrance:
				var y: float = RuralHeight.terrain_height(x, z)
				var height: float = _rng.randf_range(1.32, 1.55)
				posts.append(Vector3(x, y, z))

				var yaw: float = _rng.randf_range(-0.10, 0.10)
				var tilt: float = _rng.randf_range(-0.05, 0.05)
				var basis := Basis.from_euler(Vector3(tilt, yaw, -tilt * 0.6))
				basis = basis.scaled(Vector3(0.14, height, 0.14))
				var origin := Vector3(x, y + height * 0.5, z)
				post_transforms.append(Transform3D(basis, origin))

				if posts.size() >= 2:
					var previous: Vector3 = posts[posts.size() - 2]
					if previous.distance_to(posts[posts.size() - 1]) < 5.2:
						for wire_height in [0.52, 0.9, 1.26]:
							var a: Vector3 = previous + Vector3(0.0, wire_height, 0.0)
							var b: Vector3 = posts[posts.size() - 1] + Vector3(0.0, wire_height, 0.0)
							wire_transforms.append(_segment_transform(a, b, 0.022))
			z -= 4.0

	_add_multimesh(_unit_box(), post_transforms, _wood_material, "FencePosts", false)
	_add_multimesh(_unit_box(), wire_transforms, _wire_material, "FenceWires", false)


func _build_power_line() -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.14
	pole_mesh.bottom_radius = 0.22
	pole_mesh.height = 8.6
	pole_mesh.radial_segments = 8

	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(2.7, 0.16, 0.16)

	var pole_transforms: Array[Transform3D] = []
	var arm_transforms: Array[Transform3D] = []
	var wire_transforms: Array[Transform3D] = []
	var poles: Array[Vector3] = []

	var z: float = 240.0
	while z >= -280.0:
		var x: float = RuralHeight.road_x(z) - 10.5
		var y: float = RuralHeight.terrain_height(x, z)
		var base := Vector3(x, y, z)
		poles.append(base)
		pole_transforms.append(Transform3D(Basis.IDENTITY, base + Vector3(0.0, 4.3, 0.0)))
		arm_transforms.append(Transform3D(Basis.IDENTITY, base + Vector3(0.0, 7.95, 0.0)))
		z -= 46.0

	for i in poles.size() - 1:
		var a: Vector3 = poles[i]
		var b: Vector3 = poles[i + 1]
		for wire_x in [-1.2, 0.0, 1.2]:
			var start: Vector3 = a + Vector3(wire_x, 8.0, 0.0)
			var end: Vector3 = b + Vector3(wire_x, 8.0, 0.0)
			# Провисание: три сегмента по дуге.
			var previous: Vector3 = start
			for s in range(1, 4):
				var t: float = float(s) / 3.0
				var point: Vector3 = start.lerp(end, t) + Vector3(0.0, -sin(t * PI) * 0.75, 0.0)
				wire_transforms.append(_segment_transform(previous, point, 0.028))
				previous = point

	_add_multimesh(pole_mesh, pole_transforms, _dark_wood_material, "PowerPoles", true)
	_add_multimesh(arm_mesh, arm_transforms, _dark_wood_material, "PowerCrossarms", true)
	_add_multimesh(_unit_box(), wire_transforms, _wire_material, "PowerWires", false)


func _unit_box() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


func _segment_transform(a: Vector3, b: Vector3, thickness: float) -> Transform3D:
	var direction: Vector3 = b - a
	var length: float = direction.length()
	if length < 0.001:
		return Transform3D(Basis.IDENTITY, a)
	var basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	basis = basis.scaled(Vector3(thickness, thickness, length))
	return Transform3D(basis, (a + b) * 0.5)


func _add_multimesh(
	mesh: Mesh,
	transforms: Array[Transform3D],
	material: Material,
	node_name: String,
	cast_shadow: bool
) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

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
