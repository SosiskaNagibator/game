@tool
extends Node3D
## Загрузочная/разгрузочная база Hollow Creek: амбар, силосы, док,
## truck scale, мелкий реквизит. Всё из примитивов, без внешних ассетов.

const CLAPBOARD_SHADER := preload("res://shaders/clapboard.gdshader")
const METAL_SHADER := preload("res://shaders/corrugated_metal.gdshader")
const ROAD_SHADER := preload("res://shaders/road_gravel.gdshader")

var _barn_mat: ShaderMaterial
var _silo_mat: ShaderMaterial
var _warehouse_mat: ShaderMaterial
var _white_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _dark_metal_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _dark_wood_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _yellow_mat: StandardMaterial3D
var _crate_mat: StandardMaterial3D
var _hay_mat: StandardMaterial3D
var _barrel_mat: StandardMaterial3D
var _sign_mat: StandardMaterial3D
var _gravel_mat: ShaderMaterial

var _unit_box: BoxMesh
var _unit_cylinder: CylinderMesh
var _unit_cone: CylinderMesh
var _unit_sphere: SphereMesh

var _hay_colliders: Array[Dictionary] = []

@export var snap_to_yard: bool = true


func _ready() -> void:
	if get_node_or_null("Warehouse") != null:
		return
	if snap_to_yard:
		position.y = RuralHeight.yard_height()
	_create_materials()
	_build_yard()
	_build_warehouse()
	_build_silos()
	_build_loading_dock()
	_build_scale()
	_build_props()
	_build_sign()
	_build_cargo_zones()
	_build_collisions()


func _create_materials() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE

	_unit_cylinder = CylinderMesh.new()
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0
	_unit_cylinder.radial_segments = 18
	_unit_cylinder.rings = 1

	_unit_cone = CylinderMesh.new()
	_unit_cone.top_radius = 0.035
	_unit_cone.bottom_radius = 0.5
	_unit_cone.height = 1.0
	_unit_cone.radial_segments = 18
	_unit_cone.rings = 1

	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 1.0
	_unit_sphere.height = 2.0
	_unit_sphere.radial_segments = 10
	_unit_sphere.rings = 6

	_barn_mat = ShaderMaterial.new()
	_barn_mat.shader = CLAPBOARD_SHADER
	_barn_mat.set_shader_parameter("paint_color", Color(0.40, 0.09, 0.07))
	_barn_mat.set_shader_parameter("board_frequency", 3.6)
	_barn_mat.set_shader_parameter("wear", 0.35)

	_silo_mat = ShaderMaterial.new()
	_silo_mat.shader = METAL_SHADER
	_silo_mat.set_shader_parameter("base_color", Color(0.56, 0.59, 0.57))
	_silo_mat.set_shader_parameter("rust_amount", 0.28)
	_silo_mat.set_shader_parameter("rib_frequency", 17.0)
	_silo_mat.set_shader_parameter("rib_axis", 1)
	_silo_mat.set_shader_parameter("metallic_value", 0.55)

	# Светлый сайдинг склада: та же гофра, но чище и мельче.
	_warehouse_mat = ShaderMaterial.new()
	_warehouse_mat.shader = METAL_SHADER
	_warehouse_mat.set_shader_parameter("base_color", Color(0.63, 0.66, 0.65))
	_warehouse_mat.set_shader_parameter("rust_amount", 0.10)
	_warehouse_mat.set_shader_parameter("rib_frequency", 26.0)
	_warehouse_mat.set_shader_parameter("rib_axis", 1)
	_warehouse_mat.set_shader_parameter("metallic_value", 0.40)

	_white_mat = _standard(Color(0.88, 0.85, 0.75), 0.72)
	_concrete_mat = _standard(Color(0.60, 0.58, 0.52), 0.96)
	_dark_metal_mat = _standard(Color(0.20, 0.22, 0.23), 0.55, 0.55)
	_roof_mat = _standard(Color(0.22, 0.25, 0.25), 0.60, 0.40)
	_wood_mat = _standard(Color(0.40, 0.29, 0.17), 0.92)
	_dark_wood_mat = _standard(Color(0.25, 0.18, 0.11), 0.95)
	_yellow_mat = _standard(Color(0.84, 0.67, 0.14), 0.75)
	_crate_mat = _standard(Color(0.53, 0.40, 0.24), 0.9)
	_hay_mat = _standard(Color(0.72, 0.61, 0.33), 0.95)
	_barrel_mat = _standard(Color(0.16, 0.30, 0.40), 0.7, 0.3)
	_sign_mat = _standard(Color(0.14, 0.24, 0.17), 0.8)

	_glass_mat = _standard(Color(0.05, 0.09, 0.11), 0.15, 0.6)

	_gravel_mat = ShaderMaterial.new()
	_gravel_mat.shader = ROAD_SHADER
	_gravel_mat.set_shader_parameter("gravel_light", Color(0.43, 0.37, 0.28))
	_gravel_mat.set_shader_parameter("gravel_dark", Color(0.25, 0.21, 0.155))
	_gravel_mat.set_shader_parameter("track_color", Color(0.35, 0.30, 0.23))
	_gravel_mat.set_shader_parameter("edge_color", Color(0.30, 0.25, 0.19))
	_gravel_mat.set_shader_parameter("track_strength", 0.0)
	_gravel_mat.set_shader_parameter("edge_strength", 0.0)
	_gravel_mat.set_shader_parameter("pebble_amount", 0.32)


func _standard(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _build_yard() -> void:
	# Гравийная площадка с неровной скруглённой кромкой. Края плавно
	# уходят под землю, поэтому нет резкого прямоугольника и светлой каймы.
	var pad := MeshInstance3D.new()
	pad.name = "YardGravel"
	pad.mesh = _make_yard_mesh()
	pad.material_override = _gravel_mat
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)


func _make_yard_mesh() -> ArrayMesh:
	var segments := 96
	var rings := 7
	var radius_x := 20.2
	var radius_z := 19.4
	var center := RuralHeight.YARD_CENTER
	var top_y := 0.055

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(Vector3(center.x, top_y, center.y))

	for ring in range(1, rings + 1):
		var t: float = float(ring) / float(rings)
		# Плоское полотно, у самой кромки уходящее под рельеф.
		var fall: float = smoothstep(0.86, 1.0, t)
		for i in segments:
			var ang: float = TAU * float(i) / float(segments)
			# Суперэллипс — скруглённый прямоугольник.
			var n_exp := 4.0
			var ca: float = absf(cos(ang) / radius_x)
			var sa: float = absf(sin(ang) / radius_z)
			var r: float = pow(pow(ca, n_exp) + pow(sa, n_exp), -1.0 / n_exp)
			# Живая, чуть неровная кромка вместо линейки.
			r *= (1.0 + 0.05 * sin(ang * 3.0 + 0.7) + 0.025 * sin(ang * 7.0 - 1.3)) * t

			var x: float = center.x + cos(ang) * r
			var z: float = center.y + sin(ang) * r
			var ground: float = RuralHeight.terrain_height(x, z) - RuralHeight.yard_height()
			var y: float = lerpf(top_y, ground - 0.05, fall)

			st.set_uv(Vector2(x - center.x, z - center.y) / (2.0 * radius_x) + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(x, y, z))

	for i in segments:
		var nxt: int = (i + 1) % segments
		st.add_index(0)
		st.add_index(1 + nxt)
		st.add_index(1 + i)

	for ring in range(rings - 1):
		var inner: int = 1 + ring * segments
		var outer: int = inner + segments
		for i in segments:
			var nxt: int = (i + 1) % segments
			st.add_index(inner + i)
			st.add_index(inner + nxt)
			st.add_index(outer + i)

			st.add_index(inner + nxt)
			st.add_index(outer + nxt)
			st.add_index(outer + i)

	st.generate_normals()
	return st.commit()


func _build_warehouse() -> void:
	var warehouse := Node3D.new()
	warehouse.name = "Warehouse"
	warehouse.position = Vector3(29.0, 0.0, 100.0)
	add_child(warehouse)

	# Бетонная плита и стены. Ворота открыты — внутрь можно зайти и заехать.
	_box(warehouse, Vector3(14.2, 0.3, 16.0), Vector3(0.0, 0.15, 0.0), _concrete_mat, "Slab")
	_box(warehouse, Vector3(13.5, 7.0, 0.35), Vector3(0.0, 3.5, -7.5), _warehouse_mat, "WallNorth")
	_box(warehouse, Vector3(0.35, 7.0, 15.0), Vector3(-6.75, 3.5, 0.0), _warehouse_mat, "WallWest")
	_box(warehouse, Vector3(0.35, 7.0, 15.0), Vector3(6.75, 3.5, 0.0), _warehouse_mat, "WallEast")

	# Южная стена с двумя проёмами ворот.
	_box(warehouse, Vector3(2.05, 7.0, 0.35), Vector3(-5.725, 3.5, 7.5), _warehouse_mat, "WallSouthL")
	_box(warehouse, Vector3(1.0, 7.0, 0.35), Vector3(0.0, 3.5, 7.5), _warehouse_mat, "WallSouthM")
	_box(warehouse, Vector3(2.05, 7.0, 0.35), Vector3(5.725, 3.5, 7.5), _warehouse_mat, "WallSouthR")
	_box(warehouse, Vector3(13.5, 1.6, 0.35), Vector3(0.0, 6.2, 7.5), _warehouse_mat, "Lintel")

	# Двускатная крыша: щипец + металлические скаты, конёк и водостоки.
	var gable := PrismMesh.new()
	gable.size = Vector3(13.5, 2.2, 15.0)
	_mesh_node(warehouse, gable, Vector3(0.0, 8.1, 0.0), _roof_mat, "Gable")

	var slope_angle: float = atan2(2.2, 6.75)
	var slope_length: float = sqrt(6.75 * 6.75 + 2.2 * 2.2) + 0.7
	for side in [-1.0, 1.0]:
		var rot := Vector3(0.0, 0.0, -side * slope_angle)
		_box(
			warehouse, Vector3(slope_length, 0.18, 15.4),
			Vector3(side * 3.4, 8.1, 0.0), _roof_mat, "Roof", rot
		)
		_box(
			warehouse, Vector3(0.3, 0.26, 15.4),
			Vector3(side * 6.9, 7.0, 0.0), _dark_metal_mat, "Gutter"
		)
	_box(warehouse, Vector3(0.4, 0.16, 15.5), Vector3(0.0, 9.22, 0.0), _dark_metal_mat, "RidgeCap")

	# Два открытых проёма с поднятыми ролеттами.
	for door in [-2.6, 2.6]:
		_cylinder(
			warehouse, 0.62, 4.2, Vector3(door, 5.55, 7.16),
			_warehouse_mat, "DoorRoll", Vector3(0.0, 0.0, 90.0)
		)
		for sx in [-1.0, 1.0]:
			_box(
				warehouse, Vector3(0.12, 5.4, 0.12),
				Vector3(door + sx * 2.16, 2.7, 7.3), _yellow_mat, "DoorRail"
			)
		_box(warehouse, Vector3(4.3, 0.1, 1.3), Vector3(door, 0.34, 8.05), _dark_metal_mat, "Threshold")

	_box(warehouse, Vector3(13.2, 0.22, 0.16), Vector3(0.0, 0.55, 7.72), _yellow_mat, "DockBumper")

	# Пологие пандусы в ворота: по плите можно зайти пешком и заехать.
	for door in [-2.6, 2.6]:
		_box(
			warehouse, Vector3(4.4, 0.14, 3.0),
			Vector3(door, 0.11, 9.5), _concrete_mat, "DoorRamp", Vector3(4.7, 0.0, 0.0)
		)

	# Вывеска базы.
	_box(warehouse, Vector3(9.4, 1.4, 0.16), Vector3(0.0, 6.45, 7.72), _sign_mat, "SignBoard")
	_label(
		warehouse, "HOLLOW CREEK LOGISTICS", Vector3(0.0, 6.78, 7.82),
		0.0072, Color(0.92, 0.88, 0.68), 980, 44
	)
	_label(
		warehouse, "BASE  •  LOADING / UNLOADING", Vector3(0.0, 6.24, 7.82),
		0.0048, Color(0.80, 0.76, 0.58), 1100, 30
	)

	# Высокие окна по бокам.
	for sx in [-1.0, 1.0]:
		for z in [-4.5, -1.5, 1.5, 4.5]:
			_box(
				warehouse, Vector3(0.12, 0.9, 1.5),
				Vector3(sx * 6.94, 5.6, z), _glass_mat, "Window"
			)

	# Наружные прожекторы над воротами — включаются и днём, и ночью.
	for sx in [-1.0, 1.0]:
		_box(
			warehouse, Vector3(0.4, 0.22, 0.3),
			Vector3(sx * 4.9, 6.5, 8.0), _dark_metal_mat, "FloodFixture"
		)
		var flood := OmniLight3D.new()
		flood.name = "FloodLight"
		flood.position = Vector3(sx * 4.9, 6.1, 8.7)
		flood.light_color = Color(1.0, 0.90, 0.72)
		flood.light_energy = 2.6
		flood.omni_range = 17.0
		flood.shadow_enabled = false
		warehouse.add_child(flood)

	_build_warehouse_interior(warehouse)


func _build_warehouse_interior(warehouse: Node3D) -> void:
	# Стеллажи вдоль стен и ящики на полках.
	for sx in [-1.0, 1.0]:
		for z in [-5.2, -2.6, 0.0, 2.6, 5.2]:
			_box(
				warehouse, Vector3(0.12, 4.4, 0.12),
				Vector3(sx * 5.35, 2.2, z), _dark_metal_mat, "RackUpright"
			)
		for level in [0.45, 1.8, 3.15, 4.4]:
			_box(
				warehouse, Vector3(1.6, 0.1, 11.0),
				Vector3(sx * 5.35, level, 0.0), _dark_metal_mat, "RackShelf"
			)
			for z in [-4.4, 0.0, 4.4]:
				_crate(
					warehouse, Vector3(sx * 5.35, level + 0.36, z),
					Vector3(0.9, 0.7, 0.9)
				)

	# Паллеты в центре склада.
	for z in [-2.4, 2.4]:
		_pallet(warehouse, Vector3(-2.2, 0.31, z), 0.0)
		_crate(warehouse, Vector3(-2.2, 0.95, z), Vector3(1.2, 1.0, 1.1))
		_pallet(warehouse, Vector3(2.2, 0.31, z), 180.0)
		_crate(warehouse, Vector3(2.2, 0.95, z), Vector3(1.1, 0.9, 1.0))

	# Потолочные светильники.
	for z in [-4.5, 0.0, 4.5]:
		_box(warehouse, Vector3(1.8, 0.1, 0.5), Vector3(0.0, 6.6, z), _white_mat, "CeilingLight")
		var lamp := OmniLight3D.new()
		lamp.name = "CeilingLamp"
		lamp.position = Vector3(0.0, 6.2, z)
		lamp.light_color = Color(1.0, 0.93, 0.78)
		lamp.light_energy = 2.2
		lamp.omni_range = 13.0
		lamp.shadow_enabled = false
		warehouse.add_child(lamp)


func _build_silos() -> void:
	var silo_root := Node3D.new()
	silo_root.name = "Silos"
	add_child(silo_root)

	for z in [96.0, 105.2]:
		var silo := Node3D.new()
		silo.name = "Silo"
		silo.position = Vector3(38.6, 0.0, z)
		silo_root.add_child(silo)

		_cylinder(silo, 5.7, 0.55, Vector3(0.0, 0.27, 0.0), _concrete_mat, "Base")
		_cylinder(silo, 5.15, 9.2, Vector3(0.0, 5.0, 0.0), _silo_mat, "Body")
		_cone(silo, 5.5, 1.5, Vector3(0.0, 10.3, 0.0), _silo_mat, "Roof")
		_cylinder(silo, 0.24, 0.55, Vector3(0.0, 11.25, 0.0), _dark_metal_mat, "Vent")

		# Лестница на западной стороне.
		for sz in [-0.28, 0.28]:
			_box(
				silo, Vector3(0.06, 8.2, 0.06),
				Vector3(-2.68, 4.55, sz), _dark_metal_mat, "LadderRail"
			)
		for rung in range(1, 19):
			_box(
				silo, Vector3(0.06, 0.05, 0.62),
				Vector3(-2.70, 0.75 + rung * 0.42, 0.0), _dark_metal_mat, "LadderRung"
			)


func _build_loading_dock() -> void:
	var dock := Node3D.new()
	dock.name = "LoadingDock"
	dock.position = Vector3(14.0, 0.0, 89.0)
	add_child(dock)

	_box(dock, Vector3(9.0, 1.15, 7.0), Vector3(0.0, 0.58, 0.0), _concrete_mat, "DockPlatform")
	_box(dock, Vector3(4.2, 0.22, 4.5), Vector3(0.0, 0.63, 5.55), _concrete_mat, "DockRamp", Vector3(15.3, 0.0, 0.0))

	for sx in [-1.0, 1.0]:
		_box(dock, Vector3(0.34, 0.75, 0.34), Vector3(sx * 3.6, 0.62, 3.52), _dark_wood_mat, "Bumper")

	# Навес на деревянных столбах.
	_box(dock, Vector3(10.2, 0.22, 8.5), Vector3(0.0, 5.15, 0.0), _roof_mat, "DockCanopy")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(
				dock, Vector3(0.25, 5.1, 0.25),
				Vector3(sx * 4.05, 2.55, sz * 3.2), _wood_mat, "DockPost"
			)
		_box(dock, Vector3(0.18, 0.18, 7.0), Vector3(sx * 4.05, 4.75, 0.0), _wood_mat, "DockBeam")

	_box(dock, Vector3(6.6, 0.7, 0.12), Vector3(0.0, 5.15, 4.3), _white_mat, "DockSignBoard")
	_label(dock, "LOADING DOCK", Vector3(0.0, 5.16, 4.37), 0.0065, Color(0.12, 0.18, 0.12), 720, 48)

	# Ящики, паллеты и бочки на площадке.
	# Ящики стоят на настиле дока (верх плиты — y = 1.15), а не утопают в нём.
	_crate(dock, Vector3(-2.4, 1.70, -1.2), Vector3(1.5, 1.1, 1.4))
	_crate(dock, Vector3(-0.9, 1.55, -1.6), Vector3(1.1, 0.8, 1.1))
	_crate(dock, Vector3(-2.6, 2.70, -1.1), Vector3(1.0, 0.9, 0.9), Vector3(0.0, 12.0, 0.0))
	_crate(dock, Vector3(2.6, 1.65, 1.4), Vector3(1.4, 1.0, 1.2))
	_pallet(dock, Vector3(1.0, 1.20, 2.0), 0.0)
	_pallet(dock, Vector3(3.2, 1.20, 0.6), 20.0)
	_barrel(dock, Vector3(3.5, 1.65, -2.0), _barrel_mat)
	_barrel(dock, Vector3(2.85, 1.65, -2.2), _barrel_mat)


func _build_scale() -> void:
	var scale_root := Node3D.new()
	scale_root.name = "TruckScale"
	scale_root.position = Vector3(14.0, 0.0, 103.5)
	add_child(scale_root)

	_box(scale_root, Vector3(8.0, 0.16, 13.0), Vector3(0.0, 0.08, 0.0), _concrete_mat, "ScalePad")
	_box(scale_root, Vector3(7.2, 0.14, 12.4), Vector3(0.0, 0.23, 0.0), _dark_metal_mat, "ScaleDeck")
	for sx in [-1.0, 1.0]:
		_box(scale_root, Vector3(0.13, 0.03, 12.4), Vector3(sx * 3.44, 0.31, 0.0), _yellow_mat, "ScaleStripe")
	for sz in [-1.0, 1.0]:
		_box(scale_root, Vector3(7.2, 0.03, 0.13), Vector3(0.0, 0.31, sz * 6.05), _yellow_mat, "ScaleStripe")

	var kiosk := Node3D.new()
	kiosk.name = "ScaleKiosk"
	kiosk.position = Vector3(5.3, 0.0, 0.0)
	scale_root.add_child(kiosk)
	_box(kiosk, Vector3(1.9, 2.7, 2.0), Vector3(0.0, 1.35, 0.0), _white_mat, "KioskBody")
	_box(kiosk, Vector3(2.3, 0.18, 2.4), Vector3(0.0, 2.78, 0.0), _roof_mat, "KioskRoof")
	# Окно и дверь — отдельные панели на западной стене, без наложения друг на друга
	# и без утопания в теле киоска (раньше они пересекались и мерцали).
	_box(kiosk, Vector3(0.06, 0.80, 1.25), Vector3(-0.98, 1.97, 0.0), _glass_mat, "KioskWindow")
	_box(kiosk, Vector3(0.06, 1.50, 0.90), Vector3(-0.98, 0.77, 0.0), _dark_wood_mat, "KioskDoor")
	_label(kiosk, "SCALE", Vector3(-1.02, 2.55, 0.0), 0.0055, Color(0.10, 0.14, 0.10), 300, 30, Vector3(0.0, -90.0, 0.0))


func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)

	# Топливный бак на подставках.
	var tank := Node3D.new()
	tank.name = "FuelTank"
	tank.position = Vector3(38.0, 0.0, 112.5)
	props.add_child(tank)
	_cylinder(tank, 2.0, 4.4, Vector3(0.0, 2.0, 0.0), _dark_metal_mat, "Tank", Vector3(0.0, 0.0, 90.0))
	for sx in [-1.4, 1.4]:
		_box(tank, Vector3(0.45, 1.0, 1.5), Vector3(sx, 0.5, 0.0), _concrete_mat, "TankCradle")
	_box(tank, Vector3(0.7, 1.35, 0.55), Vector3(-2.6, 0.68, 1.0), _barrel_mat, "FuelPump")
	_box(tank, Vector3(0.55, 0.2, 0.55), Vector3(-2.6, 1.42, 1.0), _dark_metal_mat, "PumpHead")

	# Рулоны сена у северного края.
	for i in 5:
		var bx: float = 9.0 + float(i % 3) * 2.1
		var row: int = 1 if i >= 3 else 0
		var bz: float = 82.4 + float(row) * 1.9
		var by: float = 0.82 + (1.55 if row == 1 else 0.0)
		_cylinder(props, 1.6, 1.5, Vector3(bx, by, bz), _hay_mat, "HayBale", Vector3(0.0, 0.0, 90.0))
		_hay_colliders.append({
			"pos": Vector3(bx, by, bz),
			"radius": 0.8,
			"height": 1.5,
			"rot": Vector3(0.0, 0.0, 90.0),
		})

	# Паллеты и ящики у склада.
	_crate(props, Vector3(23.6, 0.7, 108.4), Vector3(1.35, 1.2, 1.2))
	_crate(props, Vector3(24.8, 0.55, 108.8), Vector3(1.0, 0.9, 1.0), Vector3(0.0, 18.0, 0.0))
	_pallet(props, Vector3(20.6, 0.06, 109.3), 10.0)
	_pallet(props, Vector3(20.3, 0.30, 109.2), 35.0)
	_barrel(props, Vector3(35.7, 0.47, 90.3), _barrel_mat)
	_barrel(props, Vector3(36.4, 0.47, 90.8), _barrel_mat)
	_barrel(props, Vector3(35.9, 0.47, 91.4), _yellow_mat)

	# Фонарь у дока.
	_cylinder(props, 0.12, 4.8, Vector3(19.0, 2.4, 94.2), _dark_metal_mat, "LampPost")
	_box(props, Vector3(1.3, 0.10, 0.10), Vector3(18.45, 4.75, 94.2), _dark_metal_mat, "LampArm")
	var lamp_mat := _standard(Color(1.0, 0.9, 0.6), 0.2)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.48)
	lamp_mat.emission_energy_multiplier = 2.2
	_box(props, Vector3(0.36, 0.16, 0.28), Vector3(17.9, 4.68, 94.2), lamp_mat, "LampHead")
	var dock_light := OmniLight3D.new()
	dock_light.name = "DockLampLight"
	dock_light.position = Vector3(17.9, 4.5, 94.2)
	dock_light.light_color = Color(1.0, 0.86, 0.60)
	dock_light.light_energy = 2.6
	dock_light.omni_range = 15.0
	dock_light.shadow_enabled = false
	props.add_child(dock_light)

	# Почтовый ящик у дороги.
	var mailbox := Node3D.new()
	mailbox.name = "Mailbox"
	var mb_x: float = RuralHeight.road_x(120.0) + 5.1
	mailbox.position = Vector3(
		mb_x,
		RuralHeight.terrain_height(mb_x, 120.0) - RuralHeight.yard_height(),
		120.0
	)
	mailbox.rotation_degrees.y = -12.0
	props.add_child(mailbox)
	_box(mailbox, Vector3(0.11, 1.25, 0.11), Vector3(0.0, 0.62, 0.0), _wood_mat, "Post")
	_box(mailbox, Vector3(0.38, 0.36, 0.58), Vector3(0.0, 1.38, 0.0), _dark_metal_mat, "Box")
	_box(mailbox, Vector3(0.04, 0.4, 0.05), Vector3(0.22, 1.6, 0.1), _yellow_mat, "Flag")


func _build_sign() -> void:
	var sign := Node3D.new()
	sign.name = "EntranceSign"
	var sx: float = 7.0
	var sz: float = 113.8
	sign.position = Vector3(
		sx,
		RuralHeight.terrain_height(sx, sz) - RuralHeight.yard_height(),
		sz
	)
	sign.rotation_degrees.y = -24.0
	add_child(sign)

	for sx_post in [-1.6, 1.6]:
		_box(sign, Vector3(0.17, 3.3, 0.17), Vector3(sx_post, 1.65, 0.0), _dark_wood_mat, "SignPost")
	_box(sign, Vector3(4.6, 1.9, 0.16), Vector3(0.0, 2.55, 0.02), _sign_mat, "SignBoard")
	_box(sign, Vector3(4.75, 0.08, 0.2), Vector3(0.0, 3.52, 0.03), _white_mat, "SignTopTrim")
	_box(sign, Vector3(4.75, 0.08, 0.2), Vector3(0.0, 1.58, 0.03), _white_mat, "SignBottomTrim")
	_label(sign, "HOLLOW CREEK\nLOGISTICS", Vector3(0.0, 2.78, 0.13), 0.0058, Color(0.95, 0.91, 0.80), 640, 52)
	_label(sign, "BASE  •  LOADING / UNLOADING", Vector3(0.0, 1.86, 0.13), 0.0042, Color(0.90, 0.85, 0.68), 640, 30)


func _build_cargo_zones() -> void:
	var zones := Node3D.new()
	zones.name = "CargoZones"
	add_child(zones)

	# Уголки зоны погрузки на настиле весов у дока.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := Vector3(14.0 + sx * 3.1, 0.33, 99.6 + sz * 2.3)
			_box(zones, Vector3(0.9, 0.03, 0.12), corner, _yellow_mat, "LoadCorner")
			_box(zones, Vector3(0.12, 0.03, 0.9), corner, _yellow_mat, "LoadCorner")

	# Жёлтая разметка зоны разгрузки перед воротами склада.
	var paint := _standard(Color(0.72, 0.58, 0.16), 0.85)
	_box(
		zones, Vector3(6.2, 0.03, 4.4), Vector3(29.0, 0.075, 111.0),
		paint, "UnloadPaint"
	)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := Vector3(29.0 + sx * 3.0, 0.10, 111.0 + sz * 2.1)
			_box(zones, Vector3(1.0, 0.03, 0.14), corner, _yellow_mat, "UnloadCorner")
			_box(zones, Vector3(0.14, 0.03, 1.0), corner, _yellow_mat, "UnloadCorner")

	# Указатель зоны разгрузки слева от ворот.
	var sign := Node3D.new()
	sign.name = "UnloadSign"
	sign.position = Vector3(22.4, 0.0, 113.9)
	sign.rotation_degrees.y = 10.0
	zones.add_child(sign)
	for sx in [-1.25, 1.25]:
		_box(sign, Vector3(0.14, 2.4, 0.14), Vector3(sx, 1.2, 0.0), _dark_metal_mat, "SignPost")
	_box(sign, Vector3(3.1, 1.05, 0.12), Vector3(0.0, 2.35, 0.05), _yellow_mat, "SignBoard")
	_label(sign, "UNLOADING", Vector3(0.0, 2.5, 0.13), 0.0065, Color(0.12, 0.13, 0.08), 640, 46)
	_label(sign, "ONLY", Vector3(0.0, 2.04, 0.13), 0.0045, Color(0.14, 0.15, 0.10), 640, 30)


func _build_collisions() -> void:
	var body := StaticBody3D.new()
	body.name = "FarmCollision"
	add_child(body)

	# Склад: плита, стены с проёмами ворот, перекрытие и стеллажи.
	_static_box(body, Vector3(14.2, 0.3, 16.0), Vector3(29.0, 0.15, 100.0))
	_static_box(body, Vector3(13.5, 7.0, 0.35), Vector3(29.0, 3.5, 92.5))
	_static_box(body, Vector3(0.35, 7.0, 15.0), Vector3(22.25, 3.5, 100.0))
	_static_box(body, Vector3(0.35, 7.0, 15.0), Vector3(35.75, 3.5, 100.0))
	_static_box(body, Vector3(2.05, 7.0, 0.35), Vector3(23.275, 3.5, 107.5))
	_static_box(body, Vector3(1.0, 7.0, 0.35), Vector3(29.0, 3.5, 107.5))
	_static_box(body, Vector3(2.05, 7.0, 0.35), Vector3(34.725, 3.5, 107.5))
	_static_box(body, Vector3(13.5, 1.6, 0.35), Vector3(29.0, 6.2, 107.5))
	_static_box(body, Vector3(13.5, 0.4, 15.0), Vector3(29.0, 7.0, 100.0))
	for rack_x in [-5.35, 5.35]:
		_static_box(body, Vector3(1.6, 4.4, 11.0), Vector3(29.0 + rack_x, 2.2, 100.0))
	for door in [-2.6, 2.6]:
		_static_box(
			body, Vector3(4.4, 0.14, 3.0),
			Vector3(29.0 + door, 0.11, 109.5), Vector3(4.7, 0.0, 0.0)
		)
	_static_cylinder(body, 2.62, 9.4, Vector3(38.6, 5.0, 96.0))
	_static_cylinder(body, 2.62, 9.4, Vector3(38.6, 5.0, 105.2))

	_static_box(body, Vector3(9.0, 1.15, 7.0), Vector3(14.0, 0.58, 89.0))
	_static_box(body, Vector3(4.2, 0.24, 4.5), Vector3(14.0, 0.63, 94.55), Vector3(15.3, 0.0, 0.0))
	for sx in [-4.05, 4.05]:
		for sz in [85.8, 92.2]:
			_static_box(body, Vector3(0.25, 5.1, 0.25), Vector3(14.0 + sx, 2.55, sz))

	_static_box(body, Vector3(8.0, 0.32, 13.0), Vector3(14.0, 0.16, 103.5))
	_static_box(body, Vector3(1.9, 2.7, 2.0), Vector3(19.3, 1.35, 103.5))

	_static_box(body, Vector3(2.1, 2.2, 4.5), Vector3(38.0, 1.5, 112.5))
	_static_box(body, Vector3(0.75, 1.45, 0.6), Vector3(35.4, 0.73, 114.0))

	# Сено: лежачие цилиндры, поэтому коллизия поворачивается вместе с рулоном.
	for bale in _hay_colliders:
		_static_cylinder_rot(
			body, bale.radius, bale.height, bale.pos, bale.rot
		)


func _static_box(
	body: StaticBody3D, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO
) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	collision.transform = Transform3D(basis, pos)
	body.add_child(collision)


func _static_cylinder(body: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position = pos
	body.add_child(collision)


func _static_cylinder_rot(
	body: StaticBody3D, radius: float, height: float, pos: Vector3, rot_deg: Vector3
) -> void:
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	collision.transform = Transform3D(basis, pos)
	body.add_child(collision)


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
		return _mesh_node(parent, _unit_box, pos, material, node_name, rot_deg, basis)
	# Для повёрнутых деталей размер запекаем в меш, а в трансформе
	# оставляем только поворот. Иначе неравномерный масштаб и поворот
	# перемножаются в неверном порядке и крыша «складывается» в плоскость.
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_node(parent, mesh, pos, material, node_name, rot_deg, basis)


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
		return _mesh_node(parent, _unit_cylinder, pos, material, node_name, rot_deg, basis)
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = height
	mesh.radial_segments = 18
	mesh.rings = 1
	return _mesh_node(parent, mesh, pos, material, node_name, rot_deg, basis)


func _cone(
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
	basis = basis.scaled_local(Vector3(diameter, height, diameter))
	return _mesh_node(parent, _unit_cone, pos, material, node_name, rot_deg, basis)


func _mesh_node(
	parent: Node3D,
	mesh: Mesh,
	pos: Vector3,
	material: Material,
	node_name: String,
	rot_deg: Vector3 = Vector3.ZERO,
	custom_basis: Basis = Basis.IDENTITY
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = Transform3D(custom_basis, pos)
	parent.add_child(instance)
	return instance


func _crate(
	parent: Node3D,
	pos: Vector3,
	size: Vector3,
	rot_deg: Vector3 = Vector3.ZERO
) -> void:
	var crate := Node3D.new()
	crate.name = "Crate"
	crate.position = pos
	crate.rotation_degrees = rot_deg
	parent.add_child(crate)
	_box(crate, size, Vector3.ZERO, _crate_mat, "Box")
	_box(crate, Vector3(size.x * 1.01, 0.1, size.z * 1.01), Vector3(0.0, size.y * 0.38, 0.0), _dark_wood_mat, "Slat")
	_box(crate, Vector3(size.x * 1.01, 0.1, size.z * 1.01), Vector3(0.0, -size.y * 0.38, 0.0), _dark_wood_mat, "Slat")


func _pallet(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var pallet := Node3D.new()
	pallet.name = "Pallet"
	pallet.position = pos
	pallet.rotation_degrees.y = rot_y
	parent.add_child(pallet)
	for i in 4:
		_box(pallet, Vector3(1.2, 0.07, 0.16), Vector3(0.0, 0.07, -0.45 + i * 0.3), _wood_mat, "Plank")
	for sx in [-0.5, 0.0, 0.5]:
		_box(pallet, Vector3(0.16, 0.1, 1.0), Vector3(sx, 0.0, 0.0), _dark_wood_mat, "Block")


func _barrel(parent: Node3D, pos: Vector3, material: Material) -> void:
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	barrel.position = pos
	parent.add_child(barrel)
	_cylinder(barrel, 0.6, 0.95, Vector3.ZERO, material, "Body")
	_cylinder(barrel, 0.64, 0.06, Vector3(0.0, 0.3, 0.0), _dark_metal_mat, "Rim")
	_cylinder(barrel, 0.64, 0.06, Vector3(0.0, -0.3, 0.0), _dark_metal_mat, "Rim")


func _label(
	parent: Node3D,
	text: String,
	pos: Vector3,
	pixel_size: float,
	color: Color,
	width_px: int,
	font_size: int,
	rot_deg: Vector3 = Vector3.ZERO
) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.rotation_degrees = rot_deg
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
