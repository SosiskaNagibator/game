@tool
extends Node3D
## Загрузочная/разгрузочная база Hollow Creek: амбар, силосы, док,
## truck scale, мелкий реквизит. Всё из примитивов, без внешних ассетов.

const CLAPBOARD_SHADER := preload("res://shaders/clapboard.gdshader")
const METAL_SHADER := preload("res://shaders/corrugated_metal.gdshader")
const ROAD_SHADER := preload("res://shaders/road_gravel.gdshader")

var _barn_mat: ShaderMaterial
var _silo_mat: ShaderMaterial
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

@export var snap_to_yard: bool = true


func _ready() -> void:
	if get_node_or_null("Barn") != null:
		return
	if snap_to_yard:
		position.y = RuralHeight.yard_height()
	_create_materials()
	_build_yard()
	_build_barn()
	_build_silos()
	_build_loading_dock()
	_build_scale()
	_build_props()
	_build_sign()
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
	_gravel_mat.set_shader_parameter("track_strength", 0.0)
	_gravel_mat.set_shader_parameter("edge_strength", 0.15)
	_gravel_mat.set_shader_parameter("pebble_amount", 0.45)


func _standard(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _build_yard() -> void:
	# Гравийная площадка: плоская плита чуть выше рельефа.
	var pad := MeshInstance3D.new()
	pad.name = "YardGravel"
	pad.mesh = _unit_box
	pad.material_override = _gravel_mat
	pad.transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(36.4, 0.10, 36.4)),
		Vector3(RuralHeight.YARD_CENTER.x, 0.02, RuralHeight.YARD_CENTER.y)
	)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)


func _build_barn() -> void:
	var barn := Node3D.new()
	barn.name = "Barn"
	barn.position = Vector3(29.0, 0.0, 100.0)
	add_child(barn)

	_box(barn, Vector3(13.5, 0.35, 15.5), Vector3(0.0, 0.14, 0.0), _concrete_mat, "BarnSlab")
	_box(barn, Vector3(12.0, 6.5, 14.0), Vector3(0.0, 3.45, 0.0), _barn_mat, "BarnBody")

	# Красный щипец + металлические скаты крыши.
	var gable := PrismMesh.new()
	gable.size = Vector3(12.0, 3.7, 14.0)
	_mesh_node(barn, gable, Vector3(0.0, 8.45, 0.0), _barn_mat, "BarnGable")

	var slope_angle: float = atan2(3.7, 6.6)
	var slope_length: float = sqrt(6.6 * 6.6 + 3.7 * 3.7) + 0.9
	for side in [-1.0, 1.0]:
		var rot := Vector3(0.0, 0.0, -side * slope_angle)
		var center := Vector3(side * 3.3, 8.45, 0.0)
		_box(barn, Vector3(slope_length, 0.22, 15.0), center, _roof_mat, "BarnRoof", rot)
		_box(
			barn, Vector3(slope_length, 0.16, 0.12),
			Vector3(side * 3.3, 8.45, 7.06), _white_mat, "Bargeboard", rot
		)
		_box(
			barn, Vector3(slope_length, 0.16, 0.12),
			Vector3(side * 3.3, 8.45, -7.06), _white_mat, "Bargeboard", rot
		)

	# Угловые доски.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(
				barn, Vector3(0.24, 6.5, 0.24),
				Vector3(sx * 6.03, 3.45, sz * 7.03), _white_mat, "CornerTrim"
			)

	# Ворота на южном фасаде.
	_box(barn, Vector3(6.0, 4.35, 0.12), Vector3(0.0, 2.45, 7.02), _dark_wood_mat, "BarnOpening")
	for sx in [-1.0, 1.0]:
		_box(barn, Vector3(2.85, 4.15, 0.10), Vector3(sx * 1.48, 2.45, 7.10), _white_mat, "BarnDoor")
		_box(
			barn, Vector3(3.5, 0.14, 0.06),
			Vector3(sx * 1.48, 2.45, 7.17), _dark_wood_mat, "DoorBrace",
			Vector3(0.0, 0.0, 38.0)
		)
		_box(
			barn, Vector3(3.5, 0.14, 0.06),
			Vector3(sx * 1.48, 2.45, 7.17), _dark_wood_mat, "DoorBrace",
			Vector3(0.0, 0.0, -38.0)
		)
	_box(barn, Vector3(6.35, 0.2, 0.18), Vector3(0.0, 4.63, 7.08), _white_mat, "DoorFrameTop")
	for sx in [-1.0, 1.0]:
		_box(barn, Vector3(0.18, 4.45, 0.18), Vector3(sx * 3.08, 2.45, 7.08), _white_mat, "DoorFrame")

	# Сеновал и балка с блоком.
	_box(barn, Vector3(2.3, 1.55, 0.10), Vector3(0.0, 5.55, 7.02), _dark_wood_mat, "HayloftOpening")
	_box(barn, Vector3(2.6, 0.15, 0.16), Vector3(0.0, 6.38, 7.06), _white_mat, "HayloftTrim")
	for sx in [-1.0, 1.0]:
		_box(barn, Vector3(0.15, 1.6, 0.16), Vector3(sx * 1.22, 5.55, 7.06), _white_mat, "HayloftTrim")
	_box(barn, Vector3(0.17, 0.17, 1.7), Vector3(0.0, 6.2, 7.75), _dark_wood_mat, "HoistBeam")
	_box(barn, Vector3(0.34, 0.34, 0.22), Vector3(0.0, 5.98, 8.5), _dark_metal_mat, "Pulley")

	# Окна по бокам.
	for sx in [-1.0, 1.0]:
		for z in [-3.2, 2.0]:
			_box(barn, Vector3(0.14, 1.75, 1.75), Vector3(sx * 6.04, 3.6, z), _white_mat, "WindowFrame")
			_box(barn, Vector3(0.17, 1.35, 1.35), Vector3(sx * 6.08, 3.6, z), _glass_mat, "WindowGlass")

	# Купол-фонарь и флюгер.
	_box(barn, Vector3(1.8, 1.2, 1.8), Vector3(0.0, 10.7, 0.0), _white_mat, "Cupola")
	var cupola_roof := PrismMesh.new()
	cupola_roof.size = Vector3(2.3, 1.0, 2.3)
	_mesh_node(barn, cupola_roof, Vector3(0.0, 11.75, 0.0), _roof_mat, "CupolaRoof")
	_cylinder(barn, 0.07, 1.5, Vector3(0.0, 12.6, 0.0), _dark_metal_mat, "VanePole")
	_box(barn, Vector3(1.0, 0.06, 0.06), Vector3(0.25, 12.95, 0.0), _dark_metal_mat, "VaneArrow")
	_box(barn, Vector3(0.3, 0.28, 0.04), Vector3(0.65, 12.95, 0.0), _dark_metal_mat, "VaneTail")


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
	_crate(dock, Vector3(-2.4, 1.55, -1.2), Vector3(1.5, 1.1, 1.4))
	_crate(dock, Vector3(-0.9, 1.4, -1.6), Vector3(1.1, 0.8, 1.1))
	_crate(dock, Vector3(-2.6, 2.55, -1.1), Vector3(1.0, 0.9, 0.9), Vector3(0.0, 12.0, 0.0))
	_crate(dock, Vector3(2.6, 1.5, 1.4), Vector3(1.4, 1.0, 1.2))
	_pallet(dock, Vector3(1.0, 1.25, 2.0), 0.0)
	_pallet(dock, Vector3(3.2, 1.35, 0.6), 20.0)
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
	_box(kiosk, Vector3(0.05, 1.0, 1.3), Vector3(-0.96, 1.85, 0.0), _glass_mat, "KioskWindow")
	_box(kiosk, Vector3(0.05, 1.95, 0.85), Vector3(-0.96, 1.0, 0.0), _dark_wood_mat, "KioskDoor")
	_label(kiosk, "SCALE", Vector3(-1.0, 2.5, 0.0), 0.006, Color(0.10, 0.14, 0.10), 300, 36, Vector3(0.0, -90.0, 0.0))


func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)

	# Топливный бак на подставках.
	var tank := Node3D.new()
	tank.name = "FuelTank"
	tank.position = Vector3(38.0, 0.0, 112.5)
	props.add_child(tank)
	_cylinder(tank, 2.0, 4.4, Vector3(0.0, 1.45, 0.0), _dark_metal_mat, "Tank", Vector3(0.0, 0.0, 90.0))
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

	# Паллеты и ящики возле амбара.
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
	_label(sign, "HOLLOW CREEK\nGRAIN & FEED", Vector3(0.0, 2.78, 0.13), 0.0058, Color(0.95, 0.91, 0.80), 640, 52)
	_label(sign, "LOADING  •  UNLOADING", Vector3(0.0, 1.86, 0.13), 0.0042, Color(0.90, 0.85, 0.68), 640, 30)


func _build_collisions() -> void:
	var body := StaticBody3D.new()
	body.name = "FarmCollision"
	add_child(body)

	_static_box(body, Vector3(12.0, 6.5, 14.0), Vector3(29.0, 3.45, 100.0))
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
	basis = basis.scaled(size)
	return _mesh_node(parent, _unit_box, pos, material, node_name, rot_deg, basis)


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
	basis = basis.scaled(Vector3(diameter, height, diameter))
	return _mesh_node(parent, _unit_cylinder, pos, material, node_name, rot_deg, basis)


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
	basis = basis.scaled(Vector3(diameter, height, diameter))
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
