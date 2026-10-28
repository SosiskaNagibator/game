@tool
extends Node3D
## Деревенские штакетники, линия электропередачи вдоль улицы и закрытые
## ворота на лесовозном отвороте к скрытой базе.

const RNG_SEED := 20260426

## Табличка «PRIVATE» на воротах базы.
const PRIVATE_SIGN_ENABLED := false

## Дворы с заборами: центр, половина размера и сторона, где калитка.
## front = 1 — калитка с востока, -1 — с запада.
const YARDS := [
	{"center": Vector2(115.0, 330.0), "half": Vector2(6.6, 6.0), "front": 1.0},
	{"center": Vector2(115.0, 306.0), "half": Vector2(6.6, 6.0), "front": 1.0},
	{"center": Vector2(117.0, 282.0), "half": Vector2(6.6, 6.0), "front": 1.0},
	{"center": Vector2(159.0, 322.0), "half": Vector2(7.2, 6.4), "front": -1.0},
	{"center": Vector2(159.0, 300.0), "half": Vector2(6.6, 6.0), "front": -1.0},
]

## Столбы ЛЭП вдоль деревенской улицы, затем линия уходит в лес.
const POWER_POLES := [
	Vector2(126.0, 348.0), Vector2(126.0, 332.0), Vector2(127.0, 316.0),
	Vector2(128.0, 300.0), Vector2(129.0, 284.0), Vector2(130.0, 268.0),
	Vector2(132.0, 252.0), Vector2(135.0, 236.0), Vector2(139.0, 220.0),
]

var _rng := RandomNumberGenerator.new()

var _picket_material: StandardMaterial3D
var _post_material: StandardMaterial3D
var _wire_material: StandardMaterial3D
var _gate_material: StandardMaterial3D
var _sign_material: StandardMaterial3D

var _fence_spans: Array[Dictionary] = []
var _pole_bases: Array[Vector3] = []
var _gate_posts: Array[Vector3] = []

var _pickets: Array[Transform3D] = []
var _posts: Array[Transform3D] = []
var _rails: Array[Transform3D] = []
var _pole_transforms: Array[Transform3D] = []
var _arm_transforms: Array[Transform3D] = []
var _wires: Array[Transform3D] = []


func _ready() -> void:
	if get_node_or_null("FencePosts") != null:
		return
	_rng.seed = RNG_SEED
	_create_materials()
	_build_village_fences()
	_build_power_line()
	_build_base_gate()
	_add_multimeshes()
	_build_collisions()


func _create_materials() -> void:
	_picket_material = StandardMaterial3D.new()
	_picket_material.albedo_color = Color(0.76, 0.74, 0.65)
	_picket_material.roughness = 0.9

	_post_material = StandardMaterial3D.new()
	_post_material.albedo_color = Color(0.235, 0.185, 0.125)
	_post_material.roughness = 0.95

	_wire_material = StandardMaterial3D.new()
	_wire_material.albedo_color = Color(0.25, 0.25, 0.24)
	_wire_material.metallic = 0.6
	_wire_material.roughness = 0.55

	_gate_material = StandardMaterial3D.new()
	_gate_material.albedo_color = Color(0.33, 0.245, 0.155)
	_gate_material.roughness = 0.95

	_sign_material = StandardMaterial3D.new()
	_sign_material.albedo_color = Color(0.16, 0.26, 0.18)
	_sign_material.roughness = 0.85


# --- Деревенские заборы ----------------------------------------------------


func _build_village_fences() -> void:
	for yard in YARDS:
		var center: Vector2 = yard["center"]
		var half: Vector2 = yard["half"]
		var front: float = yard["front"]
		var x0: float = center.x - half.x
		var x1: float = center.x + half.x
		var z0: float = center.y - half.y
		var z1: float = center.y + half.y
		var front_x: float = x1 if front > 0.0 else x0
		var back_x: float = x0 if front > 0.0 else x1
		var gate_half: float = 1.35

		_fence_run(Vector2(back_x, z0), Vector2(back_x, z1))
		_fence_run(Vector2(x0, z0), Vector2(x1, z0))
		_fence_run(Vector2(x0, z1), Vector2(x1, z1))
		_fence_run(Vector2(front_x, z0), Vector2(front_x, center.y - gate_half))
		_fence_run(Vector2(front_x, center.y + gate_half), Vector2(front_x, z1))


func _fence_run(a: Vector2, b: Vector2) -> void:
	var delta: Vector2 = b - a
	var length: float = delta.length()
	if length < 0.4:
		return
	var dir: Vector2 = delta / length
	var yaw: float = atan2(delta.x, delta.y)
	var picket_step: float = 0.30
	var count: int = int(floor(length / picket_step))

	for i in count + 1:
		var t: float = float(i) * picket_step
		if t > length:
			break
		var p: Vector2 = a + dir * t
		var y: float = RuralHeight.terrain_height(p.x, p.y)
		var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(0.085, 1.02, 0.05))
		_pickets.append(Transform3D(basis, Vector3(p.x, y + 0.58, p.y)))

	var post_step: float = 2.4
	var post_count: int = maxi(1, int(round(length / post_step)))
	for i in post_count + 1:
		var t: float = float(i) / float(post_count) * length
		var p: Vector2 = a + dir * t
		var y: float = RuralHeight.terrain_height(p.x, p.y)
		var height: float = _rng.randf_range(1.24, 1.36)
		var basis := Basis(Vector3.UP, yaw)
		basis = basis.scaled_local(Vector3(0.13, height, 0.13))
		_posts.append(Transform3D(basis, Vector3(p.x, y + height * 0.5, p.y)))

	# Рейли двумя ярусами, посегментно по рельефу.
	var segment: float = 2.4
	var segments: int = maxi(1, int(ceil(length / segment)))
	for i in segments:
		var t0: float = float(i) / float(segments) * length
		var t1: float = float(i + 1) / float(segments) * length
		var p0: Vector2 = a + dir * t0
		var p1: Vector2 = a + dir * t1
		var y0: float = RuralHeight.terrain_height(p0.x, p0.y)
		var y1: float = RuralHeight.terrain_height(p1.x, p1.y)
		var seg_len: float = (p1 - p0).length()
		if seg_len < 0.05:
			continue
		for rail_y in [0.36, 0.88]:
			var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(0.07, 0.09, seg_len))
			_rails.append(Transform3D(
				basis,
				Vector3((p0.x + p1.x) * 0.5, (y0 + y1) * 0.5 + rail_y, (p0.y + p1.y) * 0.5)
			))

	_fence_spans.append({
		"a": Vector3(a.x, RuralHeight.terrain_height(a.x, a.y), a.y),
		"b": Vector3(b.x, RuralHeight.terrain_height(b.x, b.y), b.y),
	})


# --- Линия электропередачи -------------------------------------------------


func _build_power_line() -> void:
	for point in POWER_POLES:
		var y: float = RuralHeight.terrain_height(point.x, point.y)
		var base := Vector3(point.x, y, point.y)
		_pole_bases.append(base)
		_pole_transforms.append(Transform3D(
			Basis.IDENTITY.scaled_local(Vector3(1.0, 7.8, 1.0)),
			base + Vector3(0.0, 3.9, 0.0)
		))
		_arm_transforms.append(Transform3D(
			Basis.IDENTITY.scaled_local(Vector3(2.7, 0.16, 0.16)),
			base + Vector3(0.0, 7.3, 0.0)
		))

	for i in POWER_POLES.size() - 1:
		var a: Vector3 = _pole_bases[i]
		var b: Vector3 = _pole_bases[i + 1]
		for wire_x in [-1.15, 0.0, 1.15]:
			var start: Vector3 = a + Vector3(wire_x, 7.4, 0.0)
			var end: Vector3 = b + Vector3(wire_x, 7.4, 0.0)
			var previous: Vector3 = start
			for s in range(1, 4):
				var t: float = float(s) / 3.0
				var point: Vector3 = start.lerp(end, t) + Vector3(0.0, -sin(t * PI) * 0.7, 0.0)
				_wires.append(_segment_transform(previous, point, 0.026))
				previous = point


# --- Ворота на отвороте к базе ---------------------------------------------


func _build_base_gate() -> void:
	# Ворота стоят на северо-восточном въезде во двор базы.
	var gate := Node3D.new()
	gate.name = "BaseGate"
	add_child(gate)

	var y: float = RuralHeight.terrain_height(-225.0, -148.0)
	var left := Vector3(-229.6, y, -148.2)
	var right := Vector3(-220.4, y, -148.2)

	for base in [left, right]:
		var post := MeshInstance3D.new()
		post.name = "GatePost"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.26, 2.5, 0.26)
		post.mesh = mesh
		post.material_override = _gate_material
		post.position = base + Vector3(0.0, 1.25, 0.0)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		gate.add_child(post)
		_gate_posts.append(base)

	# Створки распахнуты внутрь — проезд к доку свободен.
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "GateLeaf"
		pivot.position = left if side < 0.0 else right
		pivot.rotation_degrees.y = side * 104.0
		gate.add_child(pivot)

		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(4.5, 1.35, 0.12)
		leaf.mesh = mesh
		leaf.material_override = _gate_material
		leaf.position = Vector3(side * 2.25, 1.0, 0.0)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pivot.add_child(leaf)

		for brace_y in [0.48, 1.34]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(4.5, 0.12, 0.16)
			rail.mesh = rail_mesh
			rail.material_override = _gate_material
			rail.position = Vector3(side * 2.25, brace_y, 0.0)
			pivot.add_child(rail)

	# Небольшая табличка «частная дорога» на левом столбе.
	if PRIVATE_SIGN_ENABLED:
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(0.9, 0.5, 0.06)
		board.mesh = board_mesh
		board.material_override = _sign_material
		board.position = Vector3(-229.6, y + 1.85, -147.9)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		gate.add_child(board)

		var label := Label3D.new()
		label.name = "PrivateRoad"
		label.text = "PRIVATE"
		label.position = Vector3(-229.6, y + 1.85, -147.86)
		label.font_size = 30
		label.pixel_size = 0.007
		label.modulate = Color(0.88, 0.84, 0.68)
		label.outline_size = 0
		label.shaded = false
		gate.add_child(label)


# --- Общие меши -------------------------------------------------------------


func _add_multimeshes() -> void:
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.13
	post_mesh.bottom_radius = 0.21
	post_mesh.height = 1.0
	post_mesh.radial_segments = 7
	post_mesh.rings = 1

	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3.ONE

	_add_multimesh(_unit_box(), _pickets, _picket_material, "FencePickets", true)
	_add_multimesh(_unit_box(), _rails, _picket_material, "FenceRails", true)
	_add_multimesh(_unit_box(), _posts, _post_material, "FencePosts", true)
	_add_multimesh(post_mesh, _pole_transforms, _post_material, "PowerPoles", true)
	_add_multimesh(arm_mesh, _arm_transforms, _post_material, "PowerCrossarms", true)
	_add_multimesh(_unit_box(), _wires, _wire_material, "PowerWires", false)


func _build_collisions() -> void:
	var body := StaticBody3D.new()
	body.name = "FenceCollision"
	add_child(body)

	# Сплошная невысокая стенка вдоль каждой секции забора: игрок
	# упирается в штакетник, а не проходит сквозь него.
	for span in _fence_spans:
		var a: Vector3 = span["a"]
		var b: Vector3 = span["b"]
		var delta := b - a
		var length := Vector2(delta.x, delta.z).length()
		if length < 0.01:
			continue
		var yaw := atan2(delta.x, delta.z)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.14, 1.15, length)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = Transform3D(
			Basis(Vector3.UP, yaw),
			Vector3((a.x + b.x) * 0.5, minf(a.y, b.y) + 0.58, (a.z + b.z) * 0.5)
		)
		body.add_child(collision)

	for base in _pole_bases:
		var shape := CylinderShape3D.new()
		shape.radius = 0.22
		shape.height = 7.8
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = base + Vector3(0.0, 3.9, 0.0)
		body.add_child(collision)

	for base in _gate_posts:
		var shape := CylinderShape3D.new()
		shape.radius = 0.2
		shape.height = 2.5
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = base + Vector3(0.0, 1.25, 0.0)
		body.add_child(collision)


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
	basis = basis.scaled_local(Vector3(thickness, thickness, length))
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
