@tool
extends Node3D
## Main warehouse for rural_base.
##
## The building, racks, stacks, loading docks, office and markings are built
## procedurally so the scene stays editable. Crates and pallets come from the
## ready-made assets in the project.
##
## Layout (local coordinates, +Z is the loading/front side):
##   north half  -> storage racks and aisles
##   south strip -> loading/staging zone with two roller dock doors
##   south-east  -> mezzanine office with glass walls overlooking the floor

const METAL_SHADER := preload("res://shaders/corrugated_metal.gdshader")
const CRATE_SCENE := preload("res://assets/models/wooden_box/woodbox.glb")
const PALLET_SCENE := preload("res://scenes/props/WarehousePallet.tscn")

const HX := 11.5          # interior half width
const HZ := 9.5           # interior half depth
const WALL_T := 0.3
const WALL_H := 8.4
const FLOOR_TOP := 0.12
const GATE_W := 4.4
const GATE_H := 4.8
const GATE_X := [-5.0, 1.4]
const SOUTH_OUT := HZ + WALL_T * 0.5

const RACK_X := [-9.0, -3.5, 2.0, 7.5]
const RACK_Z0 := -8.0
const RACK_Z1 := 2.0
const RACK_LEVELS := [0.42, 1.87, 3.32, 4.77]
const RACK_H := 5.6

const OFFICE_X0 := 5.0
const OFFICE_X1 := HX
const OFFICE_Z0 := 3.2
const OFFICE_Z1 := HZ
const OFFICE_FLOOR := 3.5
const OFFICE_CEIL := 6.3

var _concrete: StandardMaterial3D
var _concrete_dark: StandardMaterial3D
var _asphalt: StandardMaterial3D
var _wall: ShaderMaterial
var _wall_inner: ShaderMaterial
var _roof_mat: StandardMaterial3D
var _steel: StandardMaterial3D
var _steel_dark: StandardMaterial3D
var _steel_light: StandardMaterial3D
var _yellow: StandardMaterial3D
var _black: StandardMaterial3D
var _orange: StandardMaterial3D
var _glass: StandardMaterial3D
var _glass_dark: StandardMaterial3D
var _lamp: StandardMaterial3D
var _lamp_warm: StandardMaterial3D
var _screen: StandardMaterial3D
var _wood: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _fabric: StandardMaterial3D
var _rug: StandardMaterial3D
var _white: StandardMaterial3D
var _paper: StandardMaterial3D

var _unit_box: BoxMesh
var _unit_cyl: CylinderMesh

var _crate_mesh: ArrayMesh
var _pallet_mesh: ArrayMesh
var _crate_h := 0.615
var _crate_lift := 0.584
var _crate_xforms: Array[Transform3D] = []
var _pallet_xforms: Array[Transform3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	position.y = RuralHeight.yard_height()
	if get_node_or_null("Structure") != null:
		return
	_rng.seed = 20261029
	_create_materials()
	_bake_repeats()
	_build_shell()
	_build_floor_markings()
	_build_racks()
	_build_floor_storage()
	_build_loading_area()
	_build_office()
	_build_lighting()
	_build_collision()
	_flush_batches()


# --- Materials --------------------------------------------------------------

func _create_materials() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE

	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 18
	_unit_cyl.rings = 1

	_concrete = _std(Color(0.42, 0.43, 0.42), 0.93)
	_concrete_dark = _std(Color(0.25, 0.26, 0.26), 0.95)
	_asphalt = _std(Color(0.18, 0.19, 0.20), 0.97)
	_roof_mat = _std(Color(0.25, 0.28, 0.29), 0.62, 0.35)
	_steel = _std(Color(0.30, 0.32, 0.33), 0.42, 0.72)
	_steel_dark = _std(Color(0.13, 0.14, 0.15), 0.48, 0.66)
	_steel_light = _std(Color(0.55, 0.57, 0.58), 0.40, 0.70)
	_yellow = _std(Color(0.88, 0.68, 0.08), 0.72)
	_black = _std(Color(0.055, 0.055, 0.06), 0.82)
	_orange = _std(Color(0.84, 0.31, 0.045), 0.70)
	_white = _std(Color(0.86, 0.87, 0.85), 0.82)
	_paper = _std(Color(0.92, 0.91, 0.87), 0.90)
	_wood = _std(Color(0.34, 0.24, 0.14), 0.90)
	_wood_dark = _std(Color(0.20, 0.14, 0.085), 0.92)
	_fabric = _std(Color(0.075, 0.082, 0.09), 0.96)
	_rug = _std(Color(0.24, 0.10, 0.09), 0.98)

	_wall = ShaderMaterial.new()
	_wall.shader = METAL_SHADER
	_wall.set_shader_parameter("base_color", Color(0.60, 0.63, 0.64))
	_wall.set_shader_parameter("rust_amount", 0.08)
	_wall.set_shader_parameter("rib_frequency", 42.0)
	_wall.set_shader_parameter("rib_axis", 0)
	_wall.set_shader_parameter("metallic_value", 0.42)
	_wall.set_shader_parameter("roughness_value", 0.55)

	_wall_inner = ShaderMaterial.new()
	_wall_inner.shader = METAL_SHADER
	_wall_inner.set_shader_parameter("base_color", Color(0.70, 0.72, 0.70))
	_wall_inner.set_shader_parameter("rust_amount", 0.04)
	_wall_inner.set_shader_parameter("rib_frequency", 52.0)
	_wall_inner.set_shader_parameter("rib_axis", 0)
	_wall_inner.set_shader_parameter("metallic_value", 0.30)
	_wall_inner.set_shader_parameter("roughness_value", 0.62)

	_glass = _std(Color(0.56, 0.72, 0.78, 0.20), 0.06, 0.15)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass_dark = _std(Color(0.10, 0.15, 0.17, 0.55), 0.10, 0.30)
	_glass_dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_dark.cull_mode = BaseMaterial3D.CULL_DISABLED

	_lamp = _std(Color(0.92, 0.96, 1.0), 0.18)
	_lamp.emission_enabled = true
	_lamp.emission = Color(0.82, 0.93, 1.0)
	_lamp.emission_energy_multiplier = 5.0
	_lamp_warm = _std(Color(1.0, 0.93, 0.78), 0.25)
	_lamp_warm.emission_enabled = true
	_lamp_warm.emission = Color(1.0, 0.82, 0.55)
	_lamp_warm.emission_energy_multiplier = 3.0
	_screen = _std(Color(0.02, 0.04, 0.06), 0.22)
	_screen.emission_enabled = true
	_screen.emission = Color(0.12, 0.34, 0.55)
	_screen.emission_energy_multiplier = 2.2


func _std(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _bake_repeats() -> void:
	_crate_mesh = _bake_scene(CRATE_SCENE)
	var ca := _crate_mesh.get_aabb()
	_crate_h = ca.size.y
	_crate_lift = -ca.position.y
	_pallet_mesh = _bake_scene(PALLET_SCENE)


func _bake_scene(scene: PackedScene) -> ArrayMesh:
	var inst := scene.instantiate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := _first_material(inst)
	if mat != null:
		st.set_material(mat)
	_append_meshes(inst, Transform3D.IDENTITY, st)
	var mesh := st.commit()
	inst.free()
	return mesh


func _first_material(node: Node) -> Material:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			return mi.mesh.surface_get_material(0)
	for c in node.get_children():
		var m := _first_material(c)
		if m != null:
			return m
	return null


func _append_meshes(node: Node, xform: Transform3D, st: SurfaceTool) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, s, t)
	for c in node.get_children():
		_append_meshes(c, t, st)


# --- Build helpers ----------------------------------------------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		node_name: String, rot_deg: Vector3 = Vector3.ZERO,
		shadows: bool = true) -> MeshInstance3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	var mesh: Mesh = _unit_box
	if rot_deg == Vector3.ZERO:
		basis = basis.scaled_local(size)
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, diameter: float, height: float, pos: Vector3,
		mat: Material, node_name: String, rot_deg: Vector3 = Vector3.ZERO,
		shadows: bool = true) -> MeshInstance3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	var mesh: Mesh = _unit_cyl
	if rot_deg == Vector3.ZERO:
		basis = basis.scaled_local(Vector3(diameter, height, diameter))
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = diameter * 0.5
		cm.bottom_radius = diameter * 0.5
		cm.height = height
		cm.radial_segments = 18
		cm.rings = 1
		mesh = cm
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, pixel: float,
		color: Color, font_size: int = 64, rot_deg: Vector3 = Vector3.ZERO,
		outline: int = 8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = pixel
	l.modulate = color
	l.font_size = font_size
	l.outline_size = outline
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.62)
	l.rotation_degrees = rot_deg
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	parent.add_child(l)
	return l


func _paint(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		node_name: String) -> void:
	_box(parent, Vector3(size.x, 0.012, size.z),
		Vector3(pos.x, FLOOR_TOP + 0.008, pos.z), mat, node_name, Vector3.ZERO, false)


func _paint_line(parent: Node3D, a: Vector2, b: Vector2, width: float,
		mat: Material, node_name: String) -> void:
	var d := b - a
	var len := d.length()
	if len <= 0.001:
		return
	var mid := (a + b) * 0.5
	var yaw := rad_to_deg(atan2(d.x, d.y))
	_box(parent, Vector3(width, 0.012, len),
		Vector3(mid.x, FLOOR_TOP + 0.008, mid.y), mat, node_name,
		Vector3(0.0, yaw, 0.0), false)


func _rect_outline(parent: Node3D, x0: float, z0: float, x1: float, z1: float,
		width: float, mat: Material, prefix: String) -> void:
	_paint_line(parent, Vector2(x0, z0), Vector2(x1, z0), width, mat, prefix + "N")
	_paint_line(parent, Vector2(x1, z0), Vector2(x1, z1), width, mat, prefix + "E")
	_paint_line(parent, Vector2(x1, z1), Vector2(x0, z1), width, mat, prefix + "S")
	_paint_line(parent, Vector2(x0, z1), Vector2(x0, z0), width, mat, prefix + "W")


func _bollard(parent: Node3D, pos: Vector3, height: float = 1.0,
		radius: float = 0.11) -> void:
	_cyl(parent, radius * 2.0, height, pos + Vector3(0.0, height * 0.5, 0.0),
		_yellow, "Bollard")
	_cyl(parent, radius * 2.08, 0.10,
		pos + Vector3(0.0, height * 0.30, 0.0), _black, "BollardBand", Vector3.ZERO, false)
	_cyl(parent, radius * 2.08, 0.10,
		pos + Vector3(0.0, height * 0.66, 0.0), _black, "BollardBand", Vector3.ZERO, false)


func _add_pallet(x: float, z: float, bottom_y: float, yaw: float = 0.0) -> void:
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0))
	_pallet_xforms.append(Transform3D(basis, Vector3(x, bottom_y, z)))


func _add_crate(x: float, y: float, z: float, yaw: float = 0.0,
		scale: float = 1.0) -> void:
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0))
	basis = basis.scaled_local(Vector3(scale, scale, scale))
	_crate_xforms.append(Transform3D(basis, Vector3(x, y + _crate_lift * scale, z)))


# --- Shell ------------------------------------------------------------------

func _build_shell() -> void:
	var s := Node3D.new()
	s.name = "Structure"
	add_child(s)

	# Concrete slab. The top is FLOOR_TOP, so all interior props sit on it.
	_box(s, Vector3(HX * 2.0 + 0.7, 0.3, HZ * 2.0 + 0.7),
		Vector3(0.0, FLOOR_TOP - 0.15, 0.0), _concrete, "FloorSlab")

	# Side walls with a clerestory window band (5.2..6.2 m).
	for sx in [-1.0, 1.0]:
		var wx: float = sx * (HX + WALL_T * 0.5)
		_box(s, Vector3(WALL_T, 5.2, HZ * 2.0 + WALL_T),
			Vector3(wx, 2.6, 0.0), _wall, "WallLower")
		_box(s, Vector3(WALL_T, 2.2, HZ * 2.0 + WALL_T),
			Vector3(wx, 7.3, 0.0), _wall, "WallUpper")
		_box(s, Vector3(0.05, 1.0, HZ * 2.0), Vector3(sx * 11.62, 5.7, 0.0),
			_glass, "ClerestoryGlass", Vector3.ZERO, false)
		for z in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
			_box(s, Vector3(0.12, 1.05, 0.12), Vector3(sx * 11.62, 5.7, z),
				_steel_dark, "WindowMullion")

	# North wall with the same clerestory band.
	_box(s, Vector3(HX * 2.0 + WALL_T * 2.0, 5.2, WALL_T),
		Vector3(0.0, 2.6, -(HZ + WALL_T * 0.5)), _wall, "WallNorthLower")
	_box(s, Vector3(HX * 2.0 + WALL_T * 2.0, 2.2, WALL_T),
		Vector3(0.0, 7.3, -(HZ + WALL_T * 0.5)), _wall, "WallNorthUpper")
	_box(s, Vector3(HX * 2.0, 1.0, 0.05), Vector3(0.0, 5.7, -9.62),
		_glass, "ClerestoryGlass", Vector3.ZERO, false)
	for x in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
		_box(s, Vector3(0.12, 1.05, 0.12), Vector3(x, 5.7, -9.62),
			_steel_dark, "WindowMullion")

	# South wall: solid piers and lintels around two roller doors.
	var south_z := HZ + WALL_T * 0.5
	_box(s, Vector3(4.45, WALL_H, WALL_T), Vector3(-9.425, WALL_H * 0.5, south_z),
		_wall, "WallSouthWest")
	_box(s, Vector3(2.0, WALL_H, WALL_T), Vector3(-1.8, WALL_H * 0.5, south_z),
		_wall, "WallSouthPier")
	_box(s, Vector3(8.05, WALL_H, WALL_T), Vector3(7.625, WALL_H * 0.5, south_z),
		_wall, "WallSouthEast")
	for gx in GATE_X:
		_box(s, Vector3(GATE_W, WALL_H - 4.92, WALL_T),
			Vector3(gx, (4.92 + WALL_H) * 0.5, south_z), _wall, "GateLintel")

	# Roof: three panels with two continuous skylights.
	var roof_y := 8.525
	var roof_parts := [[-9.2, 6.4], [0.0, 8.0], [9.2, 6.4]]
	for part in roof_parts:
		_box(s, Vector3(part[1], 0.25, HZ * 2.0 + 1.4),
			Vector3(part[0], roof_y, 0.0), _roof_mat, "RoofPanel",
			Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(2.0, 0.045, HZ * 2.0 + 1.3),
			Vector3(sx * 5.0, roof_y + 0.02, 0.0), _glass, "Skylight",
			Vector3.ZERO, false)
		for z in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			_box(s, Vector3(2.05, 0.07, 0.08),
				Vector3(sx * 5.0, roof_y + 0.08, z), _steel_dark, "SkylightBar")
		for sx2 in [-1.0, 1.0]:
			_box(s, Vector3(0.08, 0.09, HZ * 2.0 + 1.3),
				Vector3(sx * 5.0 + sx2, roof_y + 0.08, 0.0), _steel_dark, "SkylightRail")

	# Fascia / edge trim around the roof.
	_box(s, Vector3(24.8, 0.28, 0.18), Vector3(0.0, 8.55, 10.2),
		_steel_dark, "RoofFascia")
	_box(s, Vector3(24.8, 0.28, 0.18), Vector3(0.0, 8.55, -10.2),
		_steel_dark, "RoofFascia")
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.18, 0.28, 20.4), Vector3(sx * 12.4, 8.55, 0.0),
			_steel_dark, "RoofFascia")

	# Steel columns along the long walls.
	for z in [-7.5, -3.75, 0.0, 3.75, 7.5]:
		for sx in [-1.0, 1.0]:
			_box(s, Vector3(0.22, WALL_H, 0.22), Vector3(sx * 11.32, WALL_H * 0.5, z),
				_steel_dark, "Column")
			_box(s, Vector3(0.52, 0.10, 0.52), Vector3(sx * 11.32, 0.17, z),
				_steel_dark, "ColumnBase")

	# Metal roof trusses and purlins.
	for z in [-7.5, -3.75, 0.0, 3.75, 7.5]:
		_build_truss(s, z)
	for x in [-10.5, -7.0, -3.5, 0.0, 3.5, 7.0, 10.5]:
		_box(s, Vector3(0.09, 0.12, 19.5), Vector3(x, 8.22, 0.0),
			_steel_dark, "Purlin")

	# Interior wall girts give the walls an industrial scale.
	for sx in [-1.0, 1.0]:
		for y in [2.0, 4.0, 6.6]:
			_box(s, Vector3(0.07, 0.12, 19.0), Vector3(sx * 11.36, y, 0.0),
				_steel_dark, "WallGirt")
	for y in [2.0, 4.0, 6.6]:
		_box(s, Vector3(23.0, 0.12, 0.07), Vector3(0.0, y, -9.36),
			_steel_dark, "WallGirt")

	# Exterior canopy over the two gates.
	_box(s, Vector3(12.4, 0.18, 4.2), Vector3(-1.8, 6.15, 11.7),
		_roof_mat, "DockCanopy", Vector3.ZERO, false)
	for x in [-7.6, -1.8, 4.0]:
		_box(s, Vector3(0.16, 2.25, 0.16), Vector3(x, 5.03, 13.4),
			_steel_dark, "CanopyPost")
	_box(s, Vector3(12.5, 0.22, 0.18), Vector3(-1.8, 6.05, 13.55),
		_steel_dark, "CanopyBeam")


func _build_truss(parent: Node3D, z: float) -> void:
	var top_y := 8.18
	var bot_y := 7.38
	_box(parent, Vector3(23.3, 0.12, 0.16), Vector3(0.0, top_y, z),
		_steel_dark, "TrussTop")
	_box(parent, Vector3(23.3, 0.12, 0.16), Vector3(0.0, bot_y, z),
		_steel_dark, "TrussBottom")
	for x in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		_box(parent, Vector3(0.09, 0.8, 0.09), Vector3(x, 7.78, z),
			_steel_dark, "TrussPost")
	var angle := rad_to_deg(atan2(0.8, 2.25))
	for i in 9:
		var x0: float = -10.125 + float(i) * 2.25
		var sign := 1.0 if i % 2 == 0 else -1.0
		_box(parent, Vector3(2.39, 0.065, 0.065),
			Vector3(x0 + 1.125, 7.78, z), _steel_dark, "TrussDiagonal",
			Vector3(0.0, 0.0, sign * angle))


# --- Floor markings ---------------------------------------------------------

func _build_floor_markings() -> void:
	var m := Node3D.new()
	m.name = "FloorMarkings"
	add_child(m)

	# Yellow aisle/storage lines beside every rack row.
	for i in RACK_X.size():
		var x: float = RACK_X[i]
		for sx in [-1.0, 1.0]:
			_paint_line(m, Vector2(x + sx * 1.25, -8.35), Vector2(x + sx * 1.25, 3.35),
				0.12, _yellow, "AisleLine")
		_paint_line(m, Vector2(x - 1.18, -8.25), Vector2(x + 1.18, -8.25),
			0.12, _yellow, "RackCap")
		_paint_line(m, Vector2(x - 1.18, 2.25), Vector2(x + 1.18, 2.25),
			0.12, _yellow, "RackCap")
		_label(m, "R%02d" % (i + 1), Vector3(x, FLOOR_TOP + 0.02, 2.55),
			0.007, Color(0.92, 0.69, 0.10), 40, Vector3(-90.0, 0.0, 0.0), 4)

	# Loading/staging zone outline.
	_rect_outline(m, -11.2, 3.0, 9.75, 9.15, 0.14, _yellow, "LoadZone")
	_label(m, "LOADING  ZONE", Vector3(-4.4, FLOOR_TOP + 0.02, 7.55),
		0.012, Color(0.92, 0.69, 0.10), 64, Vector3(-90.0, 0.0, 0.0), 6)
	for i in GATE_X.size():
		var gx: float = GATE_X[i]
		_label(m, "DOCK %d" % (i + 1), Vector3(gx, FLOOR_TOP + 0.02, 6.55),
			0.010, Color(0.94, 0.72, 0.12), 56, Vector3(-90.0, 0.0, 0.0), 6)
		_build_gate_hazard(m, gx)

	# Aisle names in the driving lanes.
	var aisle_names := ["AISLE 01", "AISLE 02", "AISLE 03"]
	var aisle_x := [-6.25, -0.75, 4.75]
	for i in aisle_names.size():
		_label(m, aisle_names[i], Vector3(aisle_x[i], FLOOR_TOP + 0.02, -2.6),
			0.009, Color(0.90, 0.86, 0.62), 52, Vector3(-90.0, 0.0, 0.0), 6)

	# Pedestrian walkway along the east wall, outside the rack area.
	for z in range(-8, 9):
		var z0 := float(z) + 0.0
		_paint_line(m, Vector2(9.55, z0), Vector2(9.55, z0 + 0.55),
			0.08, _white, "WalkLine")
	_label(m, "PEDESTRIAN", Vector3(9.55, FLOOR_TOP + 0.02, -7.2),
		0.006, Color(0.86, 0.88, 0.86), 40, Vector3(-90.0, 0.0, 0.0), 4)

	# Dark expansion joints in the concrete.
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_paint_line(m, Vector2(x, -9.3), Vector2(x, 9.2), 0.035,
			_concrete_dark, "ExpansionJoint")
	for z in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_paint_line(m, Vector2(-11.3, z), Vector2(11.3, z), 0.035,
			_concrete_dark, "ExpansionJoint")

	# Storage-zone outlines around the floor stacks.
	for p in [Vector2(-9.8, 5.4), Vector2(-9.8, 8.2),
			Vector2(10.0, -6.2), Vector2(10.0, -3.0)]:
		_rect_outline(m, p.x - 0.85, p.y - 0.75, p.x + 0.85, p.y + 0.75,
			0.09, _yellow, "FloorStackZone")


func _build_gate_hazard(parent: Node3D, gx: float) -> void:
	for i in 8:
		var x: float = gx - 1.95 + float(i) * 0.56
		var mat: Material = _yellow if i % 2 == 0 else _black
		_box(parent, Vector3(0.34, 0.012, 1.25),
			Vector3(x, FLOOR_TOP + 0.009, 8.45), mat, "GateHazard",
			Vector3(0.0, 45.0, 0.0), false)


# --- Racks and crates -------------------------------------------------------

func _build_racks() -> void:
	var racks := Node3D.new()
	racks.name = "Racks"
	add_child(racks)
	for i in RACK_X.size():
		_build_rack_row(racks, RACK_X[i], i)


func _build_rack_row(parent: Node3D, x: float, index: int) -> void:
	var frames := [-8.0, -6.0, -4.0, -2.0, 0.0, 2.0]
	for z in frames:
		for sx in [-1.0, 1.0]:
			_box(parent, Vector3(0.10, RACK_H, 0.10),
				Vector3(x + sx * 1.05, FLOOR_TOP + RACK_H * 0.5, z),
				_steel, "RackUpright")
	# End-frame cross bracing.
	for z in [-8.0, 2.0]:
		for sx in [-1.0, 1.0]:
			_box(parent, Vector3(5.95, 0.07, 0.07),
				Vector3(x, FLOOR_TOP + 2.8, z), _steel_dark, "RackBrace",
				Vector3(0.0, 0.0, sx * 69.4))

	for li in RACK_LEVELS.size():
		var level: float = RACK_LEVELS[li]
		for sx in [-1.0, 1.0]:
			_box(parent, Vector3(0.09, 0.12, RACK_Z1 - RACK_Z0),
				Vector3(x + sx * 1.05, level - 0.06, (RACK_Z0 + RACK_Z1) * 0.5),
				_steel, "RackBeam")
			_box(parent, Vector3(0.98, 0.045, RACK_Z1 - RACK_Z0),
				Vector3(x + sx * 0.50, level - 0.022, (RACK_Z0 + RACK_Z1) * 0.5),
				_steel_dark, "RackDeck")
			# Orange safety clips on the end frames.
			for z in [-8.0, 2.0]:
				_box(parent, Vector3(0.13, 0.13, 0.09),
					Vector3(x + sx * 1.05, level - 0.05, z), _orange,
					"RackClip", Vector3.ZERO, false)

	# Rack identification plate at the south end.
	_box(parent, Vector3(1.15, 0.45, 0.05), Vector3(x, 4.85, 2.22),
		_steel_dark, "RackPlate")
	_label(parent, "R%02d" % (index + 1), Vector3(x, 4.85, 2.25),
		0.008, Color(0.93, 0.71, 0.12), 48, Vector3.ZERO)

	# Yellow end guards protect the rack corners from forklifts.
	for sx in [-1.0, 1.0]:
		_bollard(parent, Vector3(x + sx * 1.28, FLOOR_TOP, 2.62), 0.95, 0.10)

	# Pallets and crates on the shelves.
	for side in [-1.0, 1.0]:
		var sx: float = x + side * 0.49
		for li in RACK_LEVELS.size():
			var level: float = RACK_LEVELS[li]
			var fill: float = [0.84, 0.76, 0.64, 0.46][li]
			for bay_z in [-7.0, -5.0, -3.0, -1.0, 1.0]:
				if _rng.randf() > fill:
					continue
				_add_pallet(sx, bay_z, level, 90.0)
				var high := 1
				if li < 3 and _rng.randf() < 0.62:
					high = 2
				for h in high:
					var jitter_x := _rng.randf_range(-0.018, 0.018)
					var jitter_z := _rng.randf_range(-0.018, 0.018)
					var yaw := _rng.randf_range(-4.0, 4.0)
					_add_crate(sx + jitter_x, level + 0.115 + _crate_h * h,
						bay_z + jitter_z, yaw)


# --- Floor storage ----------------------------------------------------------

func _build_floor_storage() -> void:
	var s := Node3D.new()
	s.name = "FloorStorage"
	add_child(s)
	_stack(s, -9.8, 5.4, 4, 4.0)
	_stack(s, -9.8, 8.2, 3, -3.0)
	_stack(s, 10.0, -6.2, 4, -4.0)
	_stack(s, 10.0, -3.0, 3, 5.0)

	# Empty pallet stacks.
	for p in [Vector3(6.4, FLOOR_TOP, 8.2), Vector3(10.2, FLOOR_TOP, -8.4)]:
		for i in 8:
			_add_pallet(p.x, p.z, p.y + 0.115 * i, _rng.randf_range(-5.0, 5.0))
	_label(s, "STORAGE", Vector3(-9.8, FLOOR_TOP + 0.02, 6.8),
		0.007, Color(0.92, 0.69, 0.10), 44, Vector3(-90.0, 0.0, 0.0), 4)


func _stack(parent: Node3D, x: float, z: float, high: int, yaw: float) -> void:
	_add_pallet(x, z, FLOOR_TOP, yaw)
	for i in high:
		_add_crate(x + _rng.randf_range(-0.015, 0.015),
			FLOOR_TOP + 0.115 + _crate_h * i,
			z + _rng.randf_range(-0.015, 0.015),
			yaw + _rng.randf_range(-3.0, 3.0))
	# A small marker plate on the stack.
	_box(parent, Vector3(0.34, 0.22, 0.02),
		Vector3(x, FLOOR_TOP + 1.35, z + 0.46), _paper, "StackLabel",
		Vector3(0.0, yaw, 0.0), false)


# --- Loading area -----------------------------------------------------------

func _build_loading_area() -> void:
	var l := Node3D.new()
	l.name = "LoadingArea"
	add_child(l)

	# Asphalt truck apron in front of the gates.
	_box(l, Vector3(26.0, 0.14, 10.2), Vector3(0.0, 0.06, 14.7),
		_asphalt, "TruckApron", Vector3.ZERO, false)

	for i in GATE_X.size():
		_build_dock_door(l, GATE_X[i], i)

	# Truck bay markings on the apron.
	var bays := [
		{"x": -5.0, "name": "TRUCK BAY 1"},
		{"x": 1.4, "name": "TRUCK BAY 2"},
	]
	var bay_edges := [-6.9, -3.1, -0.5, 3.3]
	for x in bay_edges:
		_paint_line(l, Vector2(x, 10.3), Vector2(x, 18.7), 0.12,
			_white, "TruckBayLine")
	_paint_line(l, Vector2(-6.9, 18.7), Vector2(3.3, 18.7), 0.12,
		_white, "TruckBayStopLine")
	for bay in bays:
		_label(l, bay["name"], Vector3(bay["x"], 0.145, 16.3),
			0.010, Color(0.87, 0.88, 0.84), 52, Vector3(-90.0, 0.0, 0.0), 6)
		_box(l, Vector3(2.0, 0.22, 0.32), Vector3(bay["x"], 0.23, 18.55),
			_concrete_dark, "WheelStop")
		_box(l, Vector3(1.9, 0.03, 0.24), Vector3(bay["x"], 0.35, 18.55),
			_yellow, "WheelStopStripe", Vector3.ZERO, false)

	# Bollards protect the gate piers and the apron corners.
	for x in [-7.6, -2.4, -0.4, 3.9]:
		_bollard(l, Vector3(x, FLOOR_TOP, 10.9), 1.05, 0.115)
	for x in [-11.6, -8.4, 4.9, 11.6]:
		_bollard(l, Vector3(x, FLOOR_TOP, 18.9), 1.0, 0.11)

	# Signs: base identification, dock numbers, safety warnings.
	_sign_board(l, "HOLLOW CREEK LOGISTICS",
		Vector3(0.0, 7.05, 9.86), 10.5, 1.15, 0.0, _steel_dark,
		Color(0.93, 0.90, 0.76), 0.0085)
	_sign_board(l, "WAREHOUSE 01  •  LOADING / STORAGE",
		Vector3(0.0, 6.35, 9.87), 8.0, 0.55, 0.0, _steel_dark,
		Color(0.78, 0.74, 0.58), 0.0055)
	for i in GATE_X.size():
		_sign_board(l, "DOCK %d" % (i + 1),
			Vector3(GATE_X[i], 5.42, 9.87), 1.45, 0.55, 0.0, _yellow,
			Color(0.09, 0.09, 0.08), 0.0055)
	_sign_board(l, "CAUTION\nFORKLIFT TRAFFIC",
		Vector3(-10.0, 3.6, 9.87), 2.3, 1.1, 0.0, _yellow,
		Color(0.08, 0.08, 0.07), 0.0045)
	_sign_board(l, "TRUCK PARKING ONLY",
		Vector3(6.8, 2.8, 9.87), 3.1, 0.75, 0.0, _yellow,
		Color(0.08, 0.08, 0.07), 0.0050)

	# Exterior floodlights over each gate.
	for gx in GATE_X:
		_box(l, Vector3(0.42, 0.24, 0.28), Vector3(gx, 6.72, 9.95),
			_steel_dark, "FloodFixture")
		var flood := SpotLight3D.new()
		flood.name = "DockFlood"
		flood.position = Vector3(gx, 6.55, 10.7)
		flood.rotation_degrees = Vector3(-58.0, 0.0, 0.0)
		flood.light_color = Color(1.0, 0.88, 0.68)
		flood.light_energy = 5.0
		flood.spot_range = 18.0
		flood.spot_angle = 55.0
		flood.shadow_enabled = false
		l.add_child(flood)


func _build_dock_door(parent: Node3D, gx: float, index: int) -> void:
	var z := SOUTH_OUT - 0.10
	# Vertical yellow guide rails.
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.12, GATE_H, 0.16),
			Vector3(gx + sx * (GATE_W * 0.5), FLOOR_TOP + GATE_H * 0.5, z),
			_yellow, "DockRail")
	# Rolled-up sectional door above the opening.
	var slats := 9
	for i in slats:
		var mat: Material = _steel_light if i % 2 == 0 else _steel
		_box(parent, Vector3(GATE_W - 0.12, 0.30, 0.08),
			Vector3(gx, 5.05 + float(i) * 0.31, z), mat, "RollerDoorSlat")
	_cyl(parent, 0.36, GATE_W + 0.3, Vector3(gx, 7.85, z),
		_steel_dark, "RollerDrum", Vector3(0.0, 0.0, 90.0), false)
	# Rubber seals and bumpers.
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.14, 4.65, 0.18),
			Vector3(gx + sx * (GATE_W * 0.5 - 0.10), FLOOR_TOP + 2.33, z - 0.08),
			_black, "DockSeal", Vector3.ZERO, false)
		_box(parent, Vector3(0.34, 0.55, 0.26),
			Vector3(gx + sx * (GATE_W * 0.5 - 0.22), 1.05, z + 0.16),
			_black, "DockBumper")
	_box(parent, Vector3(GATE_W - 0.2, 0.16, 0.18),
		Vector3(gx, 4.78, z - 0.08), _black, "DockSealTop", Vector3.ZERO, false)

	# Dock leveler plate, flush with the floor, with a steel lip.
	_box(parent, Vector3(GATE_W - 0.25, 0.10, 1.75),
		Vector3(gx, FLOOR_TOP + 0.05, 10.45), _steel_light, "DockLeveler")
	_box(parent, Vector3(GATE_W - 0.25, 0.05, 0.12),
		Vector3(gx, FLOOR_TOP + 0.11, 11.32), _yellow, "LevelerLip",
		Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.10, 0.05, 1.72),
			Vector3(gx + sx * (GATE_W * 0.5 - 0.20), FLOOR_TOP + 0.11, 10.45),
			_yellow, "LevelerEdge", Vector3.ZERO, false)
	# Black/yellow threshold stripe.
	for i in 7:
		var mat: Material = _yellow if i % 2 == 0 else _black
		_box(parent, Vector3(0.30, 0.012, 0.75),
			Vector3(gx - 1.65 + float(i) * 0.55, FLOOR_TOP + 0.011, 9.55),
			mat, "ThresholdHazard", Vector3(0.0, 45.0, 0.0), false)


func _sign_board(parent: Node3D, text: String, pos: Vector3, width: float,
		height: float, rot_y: float, board_mat: Material, text_color: Color,
		pixel: float) -> void:
	_box(parent, Vector3(width, height, 0.08), pos, board_mat, "SignBoard",
		Vector3(0.0, rot_y, 0.0))
	var ang := deg_to_rad(rot_y)
	var front := pos + Vector3(0.0, 0.0, 0.055).rotated(Vector3.UP, ang)
	_label(parent, text, front, pixel, text_color, 52,
		Vector3(0.0, rot_y, 0.0), 6)


# --- Boss office ------------------------------------------------------------

func _build_office() -> void:
	var o := Node3D.new()
	o.name = "Office"
	add_child(o)
	var carpet := _std(Color(0.17, 0.18, 0.20), 0.98)

	# Mezzanine deck and support columns.
	_box(o, Vector3(OFFICE_X1 - OFFICE_X0 + 0.2, 0.22, OFFICE_Z1 - OFFICE_Z0 + 0.2),
		Vector3((OFFICE_X0 + OFFICE_X1) * 0.5, OFFICE_FLOOR - 0.11,
			(OFFICE_Z0 + OFFICE_Z1) * 0.5), _concrete, "MezzanineDeck")
	_box(o, Vector3(OFFICE_X1 - OFFICE_X0 - 0.1, 0.02, OFFICE_Z1 - OFFICE_Z0 - 0.1),
		Vector3((OFFICE_X0 + OFFICE_X1) * 0.5, OFFICE_FLOOR + 0.01,
			(OFFICE_Z0 + OFFICE_Z1) * 0.5), carpet, "OfficeCarpet")
	for x in [OFFICE_X0 + 0.2, OFFICE_X1 - 0.2]:
		for z in [OFFICE_Z0 + 0.2, OFFICE_Z1 - 0.2]:
			_box(o, Vector3(0.18, OFFICE_FLOOR, 0.18),
				Vector3(x, OFFICE_FLOOR * 0.5, z), _steel_dark, "MezzanineColumn")
	_box(o, Vector3(OFFICE_X1 - OFFICE_X0, 0.12, OFFICE_Z1 - OFFICE_Z0),
		Vector3((OFFICE_X0 + OFFICE_X1) * 0.5, OFFICE_CEIL,
			(OFFICE_Z0 + OFFICE_Z1) * 0.5), _white, "OfficeCeiling")

	# North glass wall (with door) and west glass wall.
	var z0 := OFFICE_Z0
	_box(o, Vector3(5.15, 0.9, 0.12), Vector3(7.575, OFFICE_FLOOR + 0.45, z0),
		_steel_dark, "OfficeKickPanel")
	_box(o, Vector3(0.45, 0.9, 0.12), Vector3(11.275, OFFICE_FLOOR + 0.45, z0),
		_steel_dark, "OfficeKickPanel")
	_box(o, Vector3(5.15, 1.8, 0.05), Vector3(7.575, OFFICE_FLOOR + 1.8, z0),
		_glass, "OfficeGlass", Vector3.ZERO, false)
	_box(o, Vector3(0.45, 1.8, 0.05), Vector3(11.275, OFFICE_FLOOR + 1.8, z0),
		_glass, "OfficeGlass", Vector3.ZERO, false)
	for x in [OFFICE_X0, 7.5, 10.15, 11.5]:
		_box(o, Vector3(0.08, 2.7, 0.10), Vector3(x, OFFICE_FLOOR + 1.35, z0),
			_steel_dark, "OfficeFrame")
	_box(o, Vector3(OFFICE_X1 - OFFICE_X0, 0.08, 0.10),
		Vector3((OFFICE_X0 + OFFICE_X1) * 0.5, OFFICE_FLOOR + 2.7, z0),
		_steel_dark, "OfficeFrame")

	# Glass door at the top of the stairs, shown open into the office.
	var door_pivot := Node3D.new()
	door_pivot.name = "OfficeDoorPivot"
	door_pivot.position = Vector3(11.05, OFFICE_FLOOR, z0)
	door_pivot.rotation_degrees.y = 72.0
	o.add_child(door_pivot)
	_box(door_pivot, Vector3(0.90, 2.10, 0.06), Vector3(-0.45, 1.05, 0.0),
		_glass_dark, "OfficeDoorGlass", Vector3.ZERO, false)
	for x in [0.0, -0.90]:
		_box(door_pivot, Vector3(0.06, 2.16, 0.10), Vector3(x, 1.08, 0.0),
			_steel_dark, "OfficeDoorFrame")
	for y in [0.0, 2.13]:
		_box(door_pivot, Vector3(0.94, 0.06, 0.10), Vector3(-0.45, y, 0.0),
			_steel_dark, "OfficeDoorFrame")
	_box(door_pivot, Vector3(0.04, 0.22, 0.04), Vector3(-0.78, 1.05, 0.06),
		_steel_light, "DoorHandle")
	_sign_board(o, "OFFICE", Vector3(10.60, OFFICE_FLOOR + 2.48, z0 - 0.06),
		0.95, 0.28, 180.0, _yellow, Color(0.08, 0.08, 0.07), 0.0035)

	# West glass wall.
	var wx := OFFICE_X0
	_box(o, Vector3(0.12, 0.9, OFFICE_Z1 - OFFICE_Z0),
		Vector3(wx, OFFICE_FLOOR + 0.45, (OFFICE_Z0 + OFFICE_Z1) * 0.5),
		_steel_dark, "OfficeKickPanel")
	_box(o, Vector3(0.05, 1.8, OFFICE_Z1 - OFFICE_Z0),
		Vector3(wx, OFFICE_FLOOR + 1.8, (OFFICE_Z0 + OFFICE_Z1) * 0.5),
		_glass, "OfficeGlass", Vector3.ZERO, false)
	for z in [OFFICE_Z0, 5.3, 7.4, OFFICE_Z1]:
		_box(o, Vector3(0.10, 2.7, 0.08), Vector3(wx, OFFICE_FLOOR + 1.35, z),
			_steel_dark, "OfficeFrame")
	_box(o, Vector3(0.10, 0.08, OFFICE_Z1 - OFFICE_Z0),
		Vector3(wx, OFFICE_FLOOR + 2.7, (OFFICE_Z0 + OFFICE_Z1) * 0.5),
		_steel_dark, "OfficeFrame")

	_build_office_furniture(o, carpet)
	_build_stairs(o)


func _build_office_furniture(o: Node3D, carpet: Material) -> void:
	# Rug.
	_box(o, Vector3(3.4, 0.02, 2.4), Vector3(7.9, OFFICE_FLOOR + 0.02, 6.5),
		_rug, "OfficeRug", Vector3.ZERO, false)

	# Desk.
	var desk_y := OFFICE_FLOOR + 0.75
	_box(o, Vector3(1.9, 0.07, 0.9), Vector3(7.4, desk_y, 6.15),
		_wood_dark, "DeskTop")
	for x in [6.55, 8.25]:
		for z in [5.75, 6.55]:
			_box(o, Vector3(0.07, 0.69, 0.07), Vector3(x, OFFICE_FLOOR + 0.345, z),
				_steel_dark, "DeskLeg")

	# Office chair.
	_cyl(o, 0.62, 0.06, Vector3(7.4, OFFICE_FLOOR + 0.03, 7.15), _black, "ChairBase")
	_cyl(o, 0.07, 0.34, Vector3(7.4, OFFICE_FLOOR + 0.22, 7.15), _steel_dark, "ChairLift")
	_box(o, Vector3(0.55, 0.09, 0.55), Vector3(7.4, OFFICE_FLOOR + 0.43, 7.15),
		_fabric, "ChairSeat")
	_box(o, Vector3(0.55, 0.62, 0.09), Vector3(7.4, OFFICE_FLOOR + 0.73, 7.45),
		_fabric, "ChairBack")
	for sx in [-1.0, 1.0]:
		_box(o, Vector3(0.06, 0.06, 0.42), Vector3(7.4 + sx * 0.31,
			OFFICE_FLOOR + 0.58, 7.20), _black, "ChairArm")

	# Computer: monitor, keyboard, mouse and tower.
	_box(o, Vector3(0.30, 0.03, 0.20), Vector3(7.05, desk_y + 0.05, 6.02),
		_black, "MonitorFoot")
	_box(o, Vector3(0.06, 0.28, 0.06), Vector3(7.05, desk_y + 0.20, 6.02),
		_black, "MonitorStem")
	_box(o, Vector3(0.68, 0.45, 0.05), Vector3(7.05, desk_y + 0.42, 6.00),
		_black, "MonitorFrame")
	_box(o, Vector3(0.62, 0.39, 0.012), Vector3(7.05, desk_y + 0.42, 5.97),
		_screen, "MonitorScreen", Vector3.ZERO, false)
	_box(o, Vector3(0.46, 0.03, 0.17), Vector3(7.05, desk_y + 0.05, 6.38),
		_black, "Keyboard")
	_box(o, Vector3(0.08, 0.03, 0.12), Vector3(7.45, desk_y + 0.05, 6.38),
		_black, "Mouse")
	_box(o, Vector3(0.23, 0.56, 0.46), Vector3(8.05, OFFICE_FLOOR + 0.28, 6.0),
		_black, "PcTower")
	_box(o, Vector3(0.02, 0.02, 0.02), Vector3(8.17, OFFICE_FLOOR + 0.43, 5.79),
		_screen, "PcLed", Vector3.ZERO, false)

	# Desk lamp with a warm local light.
	_cyl(o, 0.18, 0.03, Vector3(8.15, desk_y + 0.05, 5.9), _steel_dark, "LampBase")
	_cyl(o, 0.035, 0.34, Vector3(8.15, desk_y + 0.22, 5.9), _steel_dark, "LampStem")
	_box(o, Vector3(0.24, 0.10, 0.24), Vector3(8.15, desk_y + 0.40, 5.9),
		_lamp_warm, "LampShade", Vector3.ZERO, false)
	var lamp_light := OmniLight3D.new()
	lamp_light.name = "DeskLampLight"
	lamp_light.position = Vector3(8.15, desk_y + 0.35, 5.9)
	lamp_light.light_color = Color(1.0, 0.80, 0.55)
	lamp_light.light_energy = 1.4
	lamp_light.omni_range = 2.6
	lamp_light.shadow_enabled = false
	o.add_child(lamp_light)

	# Document cabinet against the east wall.
	_box(o, Vector3(0.45, 1.8, 1.0), Vector3(11.15, OFFICE_FLOOR + 0.9, 8.25),
		_steel_light, "DocumentCabinet")
	for i in 4:
		var y := OFFICE_FLOOR + 0.28 + float(i) * 0.43
		_box(o, Vector3(0.02, 0.36, 0.90), Vector3(10.915, y, 8.25),
			_steel, "CabinetDrawer")
		_box(o, Vector3(0.04, 0.04, 0.18), Vector3(10.89, y, 8.25),
			_steel_dark, "CabinetHandle")

	# Two visitor chairs facing the desk.
	for x in [6.35, 8.45]:
		_box(o, Vector3(0.50, 0.08, 0.50), Vector3(x, OFFICE_FLOOR + 0.42, 5.45),
			_fabric, "VisitorSeat")
		_box(o, Vector3(0.50, 0.52, 0.08), Vector3(x, OFFICE_FLOOR + 0.70, 5.20),
			_fabric, "VisitorBack")
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box(o, Vector3(0.045, 0.38, 0.045),
					Vector3(x + sx * 0.20, OFFICE_FLOOR + 0.19, 5.45 + sz * 0.20),
					_steel_dark, "VisitorLeg")

	# Office paperwork on the desk.
	_box(o, Vector3(0.30, 0.01, 0.42), Vector3(8.0, desk_y + 0.045, 6.30),
		_paper, "Papers", Vector3(0.0, 12.0, 0.0), false)

	# Ceiling light panels.
	for x in [6.8, 9.7]:
		_box(o, Vector3(1.65, 0.06, 0.34), Vector3(x, OFFICE_CEIL - 0.08, 6.3),
			_lamp, "OfficeLightPanel", Vector3.ZERO, false)
		var light := OmniLight3D.new()
		light.name = "OfficeLight"
		light.position = Vector3(x, OFFICE_CEIL - 0.35, 6.3)
		light.light_color = Color(1.0, 0.93, 0.80)
		light.light_energy = 2.2
		light.omni_range = 6.5
		light.shadow_enabled = true
		light.set_meta("skip_performance", true)
		o.add_child(light)


func _build_stairs(o: Node3D) -> void:
	var steps := 12
	var run := 4.6
	var rise := OFFICE_FLOOR - FLOOR_TOP
	var step_run := run / float(steps)
	var step_rise := rise / float(steps)
	var sx := 10.8
	var z0 := -1.4
	for i in steps:
		var top := FLOOR_TOP + step_rise * float(i + 1)
		var zc := z0 + step_run * (float(i) + 0.5)
		_box(o, Vector3(1.15, top - FLOOR_TOP, step_run),
			Vector3(sx, FLOOR_TOP + (top - FLOOR_TOP) * 0.5, zc),
			_steel_dark, "StairStep")
	# Angled stringers and a handrail.
	var angle := -rad_to_deg(atan2(rise, run))
	var mid_y := FLOOR_TOP + rise * 0.5
	var mid_z := z0 + run * 0.5
	for x in [10.20, 11.40]:
		_box(o, Vector3(0.07, 0.24, 5.85), Vector3(x, mid_y, mid_z),
			_steel, "StairStringer", Vector3(angle, 0.0, 0.0))
	_box(o, Vector3(0.06, 0.06, 5.85), Vector3(10.14, mid_y + 1.0, mid_z),
		_steel_dark, "Handrail", Vector3(angle, 0.0, 0.0))
	for i in [0, 4, 8, 12]:
		var t := float(i) / float(steps)
		var py := FLOOR_TOP + rise * t
		var pz := z0 + run * t
		_box(o, Vector3(0.06, 1.0, 0.06), Vector3(10.14, py + 0.5, pz),
			_steel_dark, "HandrailPost")
	# Small landing at the top of the stairs.
	_box(o, Vector3(1.30, 0.12, 0.55), Vector3(10.80, OFFICE_FLOOR - 0.06, 3.48),
		_steel_dark, "StairLanding")


# --- Lighting ---------------------------------------------------------------

func _build_lighting() -> void:
	var lights := Node3D.new()
	lights.name = "Lighting"
	add_child(lights)
	var idx := 0
	for x in [-7.0, 0.0, 7.0]:
		for z in [-6.0, 0.0, 6.0]:
			var y := 7.0
			_box(lights, Vector3(2.45, 0.12, 0.42), Vector3(x, y, z),
				_steel_dark, "FluorescentHousing")
			_box(lights, Vector3(2.30, 0.035, 0.30), Vector3(x, y - 0.075, z),
				_lamp, "FluorescentDiffuser", Vector3.ZERO, false)
			for sx in [-1.0, 1.0]:
				_box(lights, Vector3(0.035, 0.45, 0.035),
					Vector3(x + sx * 0.85, y + 0.27, z), _steel_dark,
					"LampHanger", Vector3.ZERO, false)
			var spot := SpotLight3D.new()
			spot.name = "Fluorescent"
			spot.position = Vector3(x, y - 0.16, z)
			spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			spot.light_color = Color(0.88, 0.95, 1.0)
			spot.light_energy = 4.6
			spot.spot_range = 12.5
			spot.spot_angle = 62.0
			spot.spot_attenuation = 1.1
			spot.shadow_enabled = idx % 3 == 0
			if spot.shadow_enabled:
				spot.set_meta("skip_performance", true)
			lights.add_child(spot)
			idx += 1


# --- Collision --------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	add_child(body)

	# Floor and perimeter walls.
	_static_box(body, Vector3(HX * 2.0 + 0.7, 0.3, HZ * 2.0 + 0.7),
		Vector3(0.0, FLOOR_TOP - 0.15, 0.0))
	for sx in [-1.0, 1.0]:
		_static_box(body, Vector3(WALL_T, WALL_H, HZ * 2.0 + WALL_T),
			Vector3(sx * (HX + WALL_T * 0.5), WALL_H * 0.5, 0.0))
	_static_box(body, Vector3(HX * 2.0 + WALL_T * 2.0, WALL_H, WALL_T),
		Vector3(0.0, WALL_H * 0.5, -(HZ + WALL_T * 0.5)))
	var sz := HZ + WALL_T * 0.5
	_static_box(body, Vector3(4.45, WALL_H, WALL_T),
		Vector3(-9.425, WALL_H * 0.5, sz))
	_static_box(body, Vector3(2.0, WALL_H, WALL_T),
		Vector3(-1.8, WALL_H * 0.5, sz))
	_static_box(body, Vector3(8.05, WALL_H, WALL_T),
		Vector3(7.625, WALL_H * 0.5, sz))
	for gx in GATE_X:
		_static_box(body, Vector3(GATE_W, WALL_H - 4.92, WALL_T),
			Vector3(gx, (4.92 + WALL_H) * 0.5, sz))

	# Rack rows.
	for x in RACK_X:
		_static_box(body, Vector3(2.3, RACK_H, RACK_Z1 - RACK_Z0 + 0.35),
			Vector3(x, FLOOR_TOP + RACK_H * 0.5, (RACK_Z0 + RACK_Z1) * 0.5))

	# Floor stacks.
	for st in [
		{"x": -9.8, "z": 5.4, "h": 2.72},
		{"x": -9.8, "z": 8.2, "h": 2.10},
		{"x": 10.0, "z": -6.2, "h": 2.72},
		{"x": 10.0, "z": -3.0, "h": 2.10},
	]:
		_static_box(body, Vector3(1.5, st["h"], 1.5),
			Vector3(st["x"], FLOOR_TOP + st["h"] * 0.5, st["z"]))

	# Mezzanine office: deck, glass partitions, furniture, stairs.
	_static_box(body, Vector3(OFFICE_X1 - OFFICE_X0 + 0.2, 0.22,
		OFFICE_Z1 - OFFICE_Z0 + 0.2),
		Vector3((OFFICE_X0 + OFFICE_X1) * 0.5, OFFICE_FLOOR - 0.11,
			(OFFICE_Z0 + OFFICE_Z1) * 0.5))
	_static_box(body, Vector3(5.15, 2.7, 0.12),
		Vector3(7.575, OFFICE_FLOOR + 1.35, OFFICE_Z0))
	_static_box(body, Vector3(0.45, 2.7, 0.12),
		Vector3(11.275, OFFICE_FLOOR + 1.35, OFFICE_Z0))
	_static_box(body, Vector3(0.12, 2.7, OFFICE_Z1 - OFFICE_Z0),
		Vector3(OFFICE_X0, OFFICE_FLOOR + 1.35,
			(OFFICE_Z0 + OFFICE_Z1) * 0.5))
	_static_box(body, Vector3(1.0, 1.9, 0.55),
		Vector3(11.15, OFFICE_FLOOR + 0.95, 8.25))
	_static_box(body, Vector3(1.9, 0.75, 0.9),
		Vector3(7.4, OFFICE_FLOOR + 0.375, 6.15))

	var rise := OFFICE_FLOOR - FLOOR_TOP
	var run := 4.6
	var length := sqrt(rise * rise + run * run)
	var angle := -rad_to_deg(atan2(rise, run))
	_static_box(body, Vector3(1.20, 0.20, length),
		Vector3(10.8, FLOOR_TOP + rise * 0.5, -1.4 + run * 0.5),
		Vector3(angle, 0.0, 0.0))


func _static_box(body: StaticBody3D, size: Vector3, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	collision.transform = Transform3D(basis, pos)
	body.add_child(collision)


# --- Instanced batches ------------------------------------------------------

func _flush_batches() -> void:
	var batches := Node3D.new()
	batches.name = "Batches"
	add_child(batches)
	_add_multimesh(batches, "Crates", _crate_mesh, _crate_xforms, true)
	_add_multimesh(batches, "Pallets", _pallet_mesh, _pallet_xforms, false)


func _add_multimesh(parent: Node3D, node_name: String, mesh: Mesh,
		xforms: Array[Transform3D], shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mi.custom_aabb = AABB(Vector3(-14.0, -1.0, -12.0), Vector3(28.0, 14.0, 26.0))
	parent.add_child(mi)
