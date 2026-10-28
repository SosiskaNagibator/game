@tool
extends Node3D
## Деревня Hollow Creek у южной кромки карты: жилые дома, лавка, амбар,
## колодец и фонари. База логистики спрятана в чаще далеко на северо-западе,
## поэтому деревня — единственное «людное» место на карте.

const CLAPBOARD_SHADER := preload("res://shaders/clapboard.gdshader")

const HOUSES := [
	{
		"pos": Vector2(114.0, 330.0), "yaw": 90.0, "size": Vector2(8.4, 6.6),
		"paint": Color(0.72, 0.68, 0.56), "two_story": false, "porch": true,
	},
	{
		"pos": Vector2(114.0, 306.0), "yaw": 90.0, "size": Vector2(8.4, 6.6),
		"paint": Color(0.37, 0.46, 0.35), "two_story": true, "porch": true,
	},
	{
		"pos": Vector2(116.0, 282.0), "yaw": 90.0, "size": Vector2(8.0, 6.4),
		"paint": Color(0.56, 0.55, 0.50), "two_story": false, "porch": true,
	},
	{
		"pos": Vector2(160.0, 300.0), "yaw": -90.0, "size": Vector2(8.4, 6.6),
		"paint": Color(0.62, 0.51, 0.29), "two_story": false, "porch": true,
	},
	{
		"pos": Vector2(162.0, 278.0), "yaw": -90.0, "size": Vector2(8.0, 6.4),
		"paint": Color(0.40, 0.47, 0.53), "two_story": false, "porch": true,
	},
]

const STORE_POS := Vector2(160.0, 322.0)
const BARN_POS := Vector2(100.0, 262.0)
const WELL_POS := Vector2(148.0, 288.0)
const LAMPS := [
	Vector2(128.5, 340.0), Vector2(130.0, 316.0),
	Vector2(131.5, 292.0), Vector2(146.0, 272.0),
]

var _unit_box: BoxMesh
var _unit_cylinder: CylinderMesh
var _unit_sphere: SphereMesh

var _roof_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _dark_wood_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D
var _path_mat: StandardMaterial3D
var _metal_mat: StandardMaterial3D


func _ready() -> void:
	if get_node_or_null("Houses") != null:
		return
	_create_materials()
	var houses_root := Node3D.new()
	houses_root.name = "Houses"
	add_child(houses_root)
	for house in HOUSES:
		_build_house(houses_root, house)
	_build_store()
	_build_barn()
	_build_well()
	_build_lamps()
	_build_entrance_sign()
	_build_gardens()
	_build_collisions()


func _create_materials() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE

	_unit_cylinder = CylinderMesh.new()
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0
	_unit_cylinder.radial_segments = 14
	_unit_cylinder.rings = 1

	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 1.0
	_unit_sphere.height = 2.0
	_unit_sphere.radial_segments = 10
	_unit_sphere.rings = 5

	_roof_mat = _standard(Color(0.205, 0.190, 0.170), 0.82)
	_trim_mat = _standard(Color(0.80, 0.78, 0.68), 0.78)
	_dark_wood_mat = _standard(Color(0.235, 0.175, 0.110), 0.95)
	_concrete_mat = _standard(Color(0.52, 0.50, 0.45), 0.96)
	_glass_mat = _standard(Color(0.055, 0.085, 0.10), 0.18, 0.55)
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(1.0, 0.78, 0.45)
	_glass_mat.emission_energy_multiplier = 0.18
	_stone_mat = _standard(Color(0.42, 0.41, 0.37), 0.97)
	_path_mat = _standard(Color(0.34, 0.30, 0.24), 0.98)
	_metal_mat = _standard(Color(0.20, 0.21, 0.20), 0.55, 0.5)


func _standard(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _wall_material(paint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLAPBOARD_SHADER
	material.set_shader_parameter("paint_color", paint)
	material.set_shader_parameter("board_frequency", 4.4)
	material.set_shader_parameter("wear", 0.4)
	return material


# --- Жилые дома -------------------------------------------------------------


func _build_house(root: Node3D, house: Dictionary) -> void:
	var pos: Vector2 = house["pos"]
	var size: Vector2 = house["size"]
	var yaw: float = house["yaw"]
	var paint: Color = house["paint"]
	var two_story: bool = house["two_story"]
	var porch: bool = house["porch"]

	var node := Node3D.new()
	node.name = "House"
	node.position = Vector3(pos.x, RuralHeight.terrain_height(pos.x, pos.y), pos.y)
	node.rotation_degrees.y = yaw
	root.add_child(node)

	var width: float = size.x
	var depth: float = size.y
	var wall_height: float = 5.4 if two_story else 3.3
	var base_y: float = 0.36
	var wall_mat := _wall_material(paint)

	# Фундамент и стены.
	_box(node, Vector3(width + 0.55, 0.36, depth + 0.55), Vector3(0.0, 0.18, 0.0), _concrete_mat, "Foundation")
	_box(node, Vector3(width, wall_height, depth), Vector3(0.0, base_y + wall_height * 0.5, 0.0), wall_mat, "Walls")

	# Двускатная крыша: щипец и два ската.
	var roof_base: float = base_y + wall_height
	var roof_height: float = 2.1
	var gable := PrismMesh.new()
	gable.size = Vector3(width + 0.7, roof_height, depth + 0.7)
	_mesh_node(node, gable, Vector3(0.0, roof_base + roof_height * 0.5, 0.0), _roof_mat, "Gable")

	var slope_angle: float = atan2(roof_height, width * 0.5)
	var slope_len: float = sqrt(width * width * 0.25 + roof_height * roof_height) + 0.6
	for side in [-1.0, 1.0]:
		var rot := Vector3(0.0, 0.0, -side * slope_angle)
		_box(
			node, Vector3(slope_len, 0.15, depth + 1.0),
			Vector3(side * width * 0.25, roof_base + roof_height * 0.5, 0.0),
			_roof_mat, "Roof", rot
		)
		_box(
			node, Vector3(0.18, 0.14, depth + 1.1),
			Vector3(side * (width * 0.5 + 0.18), roof_base - 0.1, 0.0),
			_trim_mat, "Gutter"
		)

	# Печная труба.
	_box(
		node, Vector3(0.62, 1.9, 0.62),
		Vector3(width * 0.26, roof_base + roof_height * 0.75, -depth * 0.22),
		_concrete_mat, "Chimney"
	)

	# Дверь, окна, наличники на фронтоне (+Z).
	var front: float = depth * 0.5
	_box(node, Vector3(1.05, 2.08, 0.12), Vector3(0.0, base_y + 1.04, front + 0.02), _dark_wood_mat, "Door")
	_box(node, Vector3(0.16, 2.14, 0.16), Vector3(-0.62, base_y + 1.07, front + 0.04), _trim_mat, "DoorTrim")
	_box(node, Vector3(0.16, 2.14, 0.16), Vector3(0.62, base_y + 1.07, front + 0.04), _trim_mat, "DoorTrim")
	_box(node, Vector3(1.35, 0.12, 0.18), Vector3(0.0, base_y + 2.2, front + 0.05), _trim_mat, "DoorLintel")

	for sx in [-1.0, 1.0]:
		_box(
			node, Vector3(0.12, 1.05, 1.25),
			Vector3(sx * (width * 0.28), base_y + 1.62, front + 0.03), _glass_mat, "Window"
		)
		# Крестовина рамы.
		_box(
			node, Vector3(0.14, 1.15, 0.08),
			Vector3(sx * (width * 0.28), base_y + 1.62, front + 0.10), _trim_mat, "WindowFrame"
		)
		_box(
			node, Vector3(0.14, 0.08, 1.35),
			Vector3(sx * (width * 0.28), base_y + 1.62, front + 0.10), _trim_mat, "WindowFrame"
		)

	if two_story:
		for sx in [-1.0, 1.0]:
			_box(
				node, Vector3(0.12, 1.0, 1.1),
				Vector3(sx * (width * 0.28), base_y + 4.15, front + 0.03), _glass_mat, "AtticWindow"
			)

	# Крыльцо с навесом.
	if porch:
		_box(
			node, Vector3(width * 0.62, 0.16, 2.1),
			Vector3(0.0, 0.42, front + 1.05), _dark_wood_mat, "PorchFloor"
		)
		for sx in [-1.0, 1.0]:
			_box(
				node, Vector3(0.14, 2.35, 0.14),
				Vector3(sx * width * 0.27, 1.15, front + 1.9), _trim_mat, "PorchPost"
			)
		_box(
			node, Vector3(width * 0.66, 0.12, 2.3),
			Vector3(0.0, 2.38, front + 1.15), _roof_mat, "PorchRoof"
		)
		_box(
			node, Vector3(1.3, 0.12, 0.7),
			Vector3(0.0, 0.16, front + 2.35), _concrete_mat, "Step"
		)
		_box(
			node, Vector3(1.3, 0.12, 0.7),
			Vector3(0.0, 0.28, front + 2.05), _concrete_mat, "Step"
		)
		# Дорожка от калитки к крыльцу.
		var path_length: float = 3.4
		_box(
			node, Vector3(1.4, 0.035, path_length),
			Vector3(0.0, 0.02, front + 2.7 + path_length * 0.5), _path_mat, "Path"
		)
		# Скамейка у стены.
		if not two_story:
			_box(
				node, Vector3(1.7, 0.1, 0.42),
				Vector3(-width * 0.34, 0.55, front + 0.55), _dark_wood_mat, "Bench"
			)

	# Коллизия дома и крыльца.
	var body := StaticBody3D.new()
	body.name = "HouseCollision"
	node.add_child(body)
	_static_box(body, Vector3(width, wall_height + 0.4, depth), Vector3(0.0, (wall_height + 0.4) * 0.5, 0.0))
	if porch:
		_static_box(body, Vector3(width * 0.62, 0.4, 2.1), Vector3(0.0, 0.25, front + 1.05))


# --- Лавка ------------------------------------------------------------------


func _build_store() -> void:
	var node := Node3D.new()
	node.name = "Store"
	node.position = Vector3(
		STORE_POS.x, RuralHeight.terrain_height(STORE_POS.x, STORE_POS.y), STORE_POS.y
	)
	node.rotation_degrees.y = -90.0
	add_child(node)

	var width: float = 10.0
	var depth: float = 7.2
	var wall_height: float = 5.8
	var wall_mat := _wall_material(Color(0.58, 0.47, 0.32))

	_box(node, Vector3(width + 0.5, 0.36, depth + 0.5), Vector3(0.0, 0.18, 0.0), _concrete_mat, "Foundation")
	_box(node, Vector3(width, wall_height, depth), Vector3(0.0, 0.36 + wall_height * 0.5, 0.0), wall_mat, "Walls")

	var roof_base: float = 0.36 + wall_height
	var roof_height: float = 2.4
	var gable := PrismMesh.new()
	gable.size = Vector3(width + 0.8, roof_height, depth + 0.8)
	_mesh_node(node, gable, Vector3(0.0, roof_base + roof_height * 0.5, 0.0), _roof_mat, "Gable")
	var slope_angle: float = atan2(roof_height, width * 0.5)
	var slope_len: float = sqrt(width * width * 0.25 + roof_height * roof_height) + 0.7
	for side in [-1.0, 1.0]:
		_box(
			node, Vector3(slope_len, 0.16, depth + 1.2),
			Vector3(side * width * 0.25, roof_base + roof_height * 0.5, 0.0),
			_roof_mat, "Roof", Vector3(0.0, 0.0, -side * slope_angle)
		)

	# Витрина и дверь на фронте (+Z).
	var front: float = depth * 0.5
	_box(node, Vector3(1.2, 2.2, 0.12), Vector3(-2.0, 1.5, front + 0.02), _dark_wood_mat, "Door")
	_box(node, Vector3(3.4, 1.3, 0.12), Vector3(1.4, 1.9, front + 0.02), _glass_mat, "StoreWindow")
	_box(node, Vector3(0.14, 1.4, 0.12), Vector3(1.4, 1.9, front + 0.11), _trim_mat, "WindowBar")
	_box(node, Vector3(3.5, 0.14, 0.2), Vector3(1.4, 1.22, front + 0.08), _trim_mat, "WindowSill")

	# Навес над входом.
	_box(node, Vector3(6.2, 0.14, 2.4), Vector3(0.4, 3.1, front + 1.15), _roof_mat, "Awning")
	for sx in [-1.0, 1.0]:
		_box(node, Vector3(0.15, 2.8, 0.15), Vector3(0.4 + sx * 2.9, 1.4, front + 2.25), _trim_mat, "AwningPost")

	# Вывеска.
	_box(node, Vector3(5.2, 1.0, 0.12), Vector3(0.0, 3.2, front + 2.3), _dark_wood_mat, "StoreSign")
	_label(
		node, "HOLLOW CREEK STORE", Vector3(0.0, 3.2, front + 2.37),
		0.0052, Color(0.93, 0.89, 0.74), 900, 40
	)

	# Бочки и ящики у входа.
	_cylinder(node, 0.62, 0.95, Vector3(-3.6, 0.83, front + 1.5), _dark_wood_mat, "Barrel")
	_cylinder(node, 0.62, 0.95, Vector3(-3.6, 0.83, front + 2.4), _dark_wood_mat, "Barrel")
	_box(node, Vector3(0.9, 0.9, 0.9), Vector3(3.6, 0.81, front + 1.4), _dark_wood_mat, "Crate")

	var body := StaticBody3D.new()
	body.name = "StoreCollision"
	node.add_child(body)
	_static_box(body, Vector3(width, wall_height + 0.4, depth), Vector3(0.0, (wall_height + 0.4) * 0.5, 0.0))
	_static_box(body, Vector3(6.2, 0.2, 2.4), Vector3(0.4, 3.1, front + 1.15))


# --- Амбар ------------------------------------------------------------------


func _build_barn() -> void:
	var node := Node3D.new()
	node.name = "Barn"
	node.position = Vector3(
		BARN_POS.x, RuralHeight.terrain_height(BARN_POS.x, BARN_POS.y), BARN_POS.y
	)
	node.rotation_degrees.y = 90.0
	add_child(node)

	var width: float = 13.0
	var depth: float = 9.0
	var wall_height: float = 5.2
	var wall_mat := _wall_material(Color(0.40, 0.11, 0.085))

	_box(node, Vector3(width + 0.6, 0.4, depth + 0.6), Vector3(0.0, 0.2, 0.0), _concrete_mat, "Foundation")
	_box(node, Vector3(width, wall_height, depth), Vector3(0.0, 0.4 + wall_height * 0.5, 0.0), wall_mat, "Walls")

	# Классическая двускатная крыша с большим выносом.
	var roof_base: float = 0.4 + wall_height
	var roof_height: float = 3.4
	var gable := PrismMesh.new()
	gable.size = Vector3(width + 1.0, roof_height, depth + 1.0)
	_mesh_node(node, gable, Vector3(0.0, roof_base + roof_height * 0.5, 0.0), _roof_mat, "Gable")
	var slope_angle: float = atan2(roof_height, width * 0.5)
	var slope_len: float = sqrt(width * width * 0.25 + roof_height * roof_height) + 0.8
	for side in [-1.0, 1.0]:
		_box(
			node, Vector3(slope_len, 0.16, depth + 1.4),
			Vector3(side * width * 0.25, roof_base + roof_height * 0.5, 0.0),
			_roof_mat, "Roof", Vector3(0.0, 0.0, -side * slope_angle)
		)

	# Большие ворота и сеновал.
	var front: float = depth * 0.5
	for sx in [-1.0, 1.0]:
		_box(
			node, Vector3(width * 0.35, 3.6, 0.16),
			Vector3(sx * width * 0.2, 2.2, front + 0.04), _dark_wood_mat, "BarnDoor"
		)
		_box(
			node, Vector3(0.16, 3.9, 0.2),
			Vector3(sx * width * 0.36, 2.2, front + 0.06), _trim_mat, "BarnDoorTrim"
		)
	_box(node, Vector3(width * 0.72, 0.16, 0.2), Vector3(0.0, 4.1, front + 0.05), _trim_mat, "BarnLintel")
	_box(node, Vector3(1.8, 1.8, 0.14), Vector3(0.0, roof_base + 0.95, front + 0.04), _dark_wood_mat, "LoftDoor")
	_box(node, Vector3(2.1, 0.12, 0.2), Vector3(0.0, roof_base + 1.9, front + 0.08), _trim_mat, "LoftLedge")

	# Сено под навесом вдоль стены.
	for i in 4:
		_cylinder(
			node, 1.5, 1.4, Vector3(-width * 0.34 + float(i) * 1.8, 1.1, front + 2.2),
			_standard(Color(0.70, 0.59, 0.32), 0.95), "HayBale", Vector3(0.0, 0.0, 90.0)
		)

	var body := StaticBody3D.new()
	body.name = "BarnCollision"
	node.add_child(body)
	_static_box(body, Vector3(width, wall_height + 0.4, depth), Vector3(0.0, (wall_height + 0.4) * 0.5, 0.0))


# --- Колодец и фонари -------------------------------------------------------


func _build_well() -> void:
	var node := Node3D.new()
	node.name = "Well"
	node.position = Vector3(
		WELL_POS.x, RuralHeight.terrain_height(WELL_POS.x, WELL_POS.y), WELL_POS.y
	)
	add_child(node)

	_cylinder(node, 2.3, 1.05, Vector3(0.0, 0.52, 0.0), _stone_mat, "WellRing")
	_cylinder(node, 1.7, 0.08, Vector3(0.0, 1.06, 0.0), _standard(Color(0.06, 0.08, 0.09), 0.3), "WellWater")
	for sx in [-1.0, 1.0]:
		_box(node, Vector3(0.16, 2.7, 0.16), Vector3(sx * 1.1, 1.4, 0.0), _dark_wood_mat, "WellPost")
	_box(node, Vector3(2.8, 0.14, 0.18), Vector3(0.0, 2.5, 0.0), _dark_wood_mat, "WellBeam")
	var roof := PrismMesh.new()
	roof.size = Vector3(3.2, 0.9, 1.9)
	_mesh_node(node, roof, Vector3(0.0, 3.05, 0.0), _roof_mat, "WellRoof")
	_cylinder(node, 0.06, 1.1, Vector3(0.0, 1.9, 0.0), _metal_mat, "WellChain")
	_cylinder(node, 0.42, 0.5, Vector3(0.0, 1.3, 0.0), _dark_wood_mat, "WellBucket")

	var body := StaticBody3D.new()
	body.name = "WellCollision"
	node.add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 1.16
	shape.height = 1.1
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.55, 0.0)
	body.add_child(collision)


func _build_lamps() -> void:
	var lamp_root := Node3D.new()
	lamp_root.name = "StreetLamps"
	add_child(lamp_root)

	for i in LAMPS.size():
		var point: Vector2 = LAMPS[i]
		var y: float = RuralHeight.terrain_height(point.x, point.y)
		var lamp := Node3D.new()
		lamp.name = "StreetLamp_%d" % i
		lamp.position = Vector3(point.x, y, point.y)
		lamp_root.add_child(lamp)

		_cylinder(lamp, 0.14, 4.4, Vector3(0.0, 2.2, 0.0), _dark_wood_mat, "Post")
		_box(lamp, Vector3(1.1, 0.1, 0.1), Vector3(0.5, 4.35, 0.0), _dark_wood_mat, "Arm")

		var glass := _standard(Color(1.0, 0.86, 0.58), 0.25)
		glass.emission_enabled = true
		glass.emission = Color(1.0, 0.78, 0.42)
		glass.emission_energy_multiplier = 2.4
		_box(lamp, Vector3(0.34, 0.26, 0.3), Vector3(0.95, 4.22, 0.0), glass, "Lantern")

		var light := OmniLight3D.new()
		light.name = "Light"
		light.position = Vector3(0.95, 4.1, 0.0)
		light.light_color = Color(1.0, 0.82, 0.55)
		light.light_energy = 1.7
		light.omni_range = 13.0
		light.shadow_enabled = false
		lamp.add_child(light)

		var body := StaticBody3D.new()
		body.name = "LampCollision"
		lamp.add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = 0.13
		shape.height = 4.4
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(0.0, 2.2, 0.0)
		body.add_child(collision)


# --- Въездной знак и огороды -----------------------------------------------


func _build_entrance_sign() -> void:
	var sign := Node3D.new()
	sign.name = "VillageSign"
	var x: float = 144.0
	var z: float = 344.0
	sign.position = Vector3(x, RuralHeight.terrain_height(x, z), z)
	sign.rotation_degrees.y = 8.0
	add_child(sign)

	for sx in [-1.5, 1.5]:
		_box(sign, Vector3(0.18, 3.0, 0.18), Vector3(sx, 1.5, 0.0), _dark_wood_mat, "SignPost")
	_box(sign, Vector3(4.4, 1.6, 0.14), Vector3(0.0, 2.35, 0.02), _dark_wood_mat, "SignBoard")
	_label(
		sign, "HOLLOW CREEK", Vector3(0.0, 2.52, 0.12),
		0.0058, Color(0.94, 0.90, 0.76), 640, 46
	)
	_label(
		sign, "FOREST ROAD  •  NO SERVICES", Vector3(0.0, 1.93, 0.12),
		0.0036, Color(0.80, 0.77, 0.62), 700, 26
	)


func _build_gardens() -> void:
	var garden := Node3D.new()
	garden.name = "Gardens"
	add_child(garden)

	var soil := _standard(Color(0.20, 0.145, 0.095), 0.98)
	var crop := _standard(Color(0.24, 0.38, 0.12), 0.92)

	# Огород за домом №3.
	var gx: float = 101.0
	var gz: float = 282.0
	var gy: float = RuralHeight.terrain_height(gx, gz)
	_box(garden, Vector3(7.5, 0.16, 5.5), Vector3(gx, gy + 0.06, gz), soil, "VegetableBed")
	for row in 4:
		for i in 3:
			var x: float = gx - 2.4 + float(i) * 1.6
			var z: float = gz - 1.6 + float(row) * 1.1
			_box(
				garden, Vector3(0.9, 0.32, 0.7),
				Vector3(x, gy + 0.28, z), crop, "Crop"
			)

	# Поленница у второго дома.
	var wx: float = 104.0
	var wz: float = 312.0
	var wy: float = RuralHeight.terrain_height(wx, wz)
	for i in 9:
		var row: int = i / 3
		var column: int = i % 3
		_cylinder(
			garden, 0.36, 1.4,
			Vector3(wx + float(column) * 0.4, wy + 0.2 + float(row) * 0.34, wz),
			_dark_wood_mat, "Firewood", Vector3(90.0, 0.0, 0.0)
		)


# --- Коллизии общие ---------------------------------------------------------


func _build_collisions() -> void:
	pass


# --- Помощники --------------------------------------------------------------


func _box(
	parent: Node3D,
	size: Vector3,
	pos: Vector3,
	material: Material,
	node_name: String,
	rot_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	if rot_deg == Vector3.ZERO:
		basis = basis.scaled_local(size)
		return _mesh_node(parent, _unit_box, pos, material, node_name, basis)
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_node(parent, mesh, pos, material, node_name, basis)


func _cylinder(
	parent: Node3D,
	diameter: float,
	height: float,
	pos: Vector3,
	material: Material,
	node_name: String,
	rot_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	if rot_deg == Vector3.ZERO:
		basis = basis.scaled_local(Vector3(diameter, height, diameter))
		return _mesh_node(parent, _unit_cylinder, pos, material, node_name, basis)
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	return _mesh_node(parent, mesh, pos, material, node_name, basis)


func _mesh_node(
	parent: Node3D,
	mesh: Mesh,
	pos: Vector3,
	material: Material,
	node_name: String,
	custom_basis: Basis = Basis.IDENTITY
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = Transform3D(custom_basis, pos)
	parent.add_child(instance)
	return instance


func _static_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = pos
	body.add_child(collision)


func _label(
	parent: Node3D,
	text: String,
	pos: Vector3,
	pixel_size: float,
	color: Color,
	width_px: int,
	font_size: int
) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.width = width_px
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0.06, 0.07, 0.05, 0.9)
	label.shaded = false
	label.double_sided = false
	parent.add_child(label)
	return label
