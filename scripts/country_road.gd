@tool
extends Node3D
## Ленты всех просёлочных дорог: повторяют сплайны и рельеф из RuralHeight.
## Каждая дорога получает свой материал — от укатанного гравия до
## почти заросшей лесовозной колеи.

const ROAD_SHADER := preload("res://shaders/road_gravel.gdshader")

@export var surface_offset: float = 0.05
@export var crown_height: float = 0.018

## Поперечные полосы: сгущаем вершины к краям, чтобы кромка читалась.
const OFFSETS := [-1.0, -0.88, -0.66, -0.4, -0.14, 0.0, 0.14, 0.4, 0.66, 0.88, 1.0]


func _ready() -> void:
	if get_node_or_null("RoadMeshes") != null:
		return
	_build()


func _build() -> void:
	var root := Node3D.new()
	root.name = "RoadMeshes"
	add_child(root)

	var roads: Array[Dictionary] = ForestRoads.roads()
	for i in roads.size():
		_build_road(root, roads[i], i)


func _build_road(root: Node3D, road: Dictionary, index: int) -> void:
	var pts: PackedVector3Array = road["points"]
	if pts.size() < 2:
		return
	var half_width: float = road["half_width"]
	var overgrown: float = road["overgrown"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var traveled: float = 0.0
	for row in pts.size():
		var p: Vector3 = pts[row]
		var prev: Vector3 = pts[maxi(row - 1, 0)]
		var next: Vector3 = pts[mini(row + 1, pts.size() - 1)]
		var ahead := Vector3(next.x - prev.x, 0.0, next.z - prev.z).normalized()
		if ahead.length_squared() < 0.0001:
			ahead = Vector3.FORWARD
		var lateral := Vector3(-ahead.z, 0.0, ahead.x)
		if row > 0:
			traveled += Vector2(p.x - prev.x, p.z - prev.z).length()

		var base_y: float = RuralHeight.terrain_height(p.x, p.z)
		for offset in OFFSETS:
			var lateral_offset: float = offset * half_width
			var side_x: float = p.x + lateral.x * lateral_offset
			var side_z: float = p.z + lateral.z * lateral_offset
			var crown: float = (1.0 - absf(offset)) * crown_height
			var surface_y: float = base_y + surface_offset + crown
			# Край полотна постепенно принимает высоту обочины. В центре
			# остаётся ровная колея, а последний метр дороги не обрывается.
			var edge_blend: float = smoothstep(0.58, 1.0, absf(offset)) * 0.78
			var shoulder_y: float = RuralHeight.terrain_height(side_x, side_z) + surface_offset * 0.4
			var pos := Vector3(side_x, lerpf(surface_y, shoulder_y, edge_blend), side_z)
			st.set_uv(Vector2((offset + 1.0) * 0.5, traveled * 0.045))
			st.add_vertex(pos)

	var columns: int = OFFSETS.size()
	for row in pts.size() - 1:
		for col in columns - 1:
			var i: int = row * columns + col
			st.add_index(i)
			st.add_index(i + columns)
			st.add_index(i + 1)

			st.add_index(i + 1)
			st.add_index(i + columns)
			st.add_index(i + columns + 1)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var material := _make_material(overgrown)

	var instance := MeshInstance3D.new()
	instance.name = "Road_%d" % index
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


func _make_material(overgrown: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROAD_SHADER

	# Гравий светлеет по мере «укатанности», старая колея уходит в бурый мох.
	var light: Color = Color(0.52, 0.46, 0.36).lerp(Color(0.33, 0.30, 0.20), overgrown)
	var dark: Color = Color(0.33, 0.28, 0.21).lerp(Color(0.20, 0.19, 0.12), overgrown)
	var track: Color = Color(0.46, 0.40, 0.30).lerp(Color(0.29, 0.26, 0.17), overgrown)
	var edge: Color = Color(0.36, 0.31, 0.22).lerp(Color(0.22, 0.21, 0.13), overgrown)
	var grass: Color = Color(0.19, 0.30, 0.10).lerp(Color(0.15, 0.25, 0.08), overgrown)

	material.set_shader_parameter("gravel_light", light)
	material.set_shader_parameter("gravel_dark", dark)
	material.set_shader_parameter("track_color", track)
	material.set_shader_parameter("edge_color", edge)
	material.set_shader_parameter("grass_color", grass)
	material.set_shader_parameter("grass_amount", clampf(overgrown * 0.4, 0.0, 0.4))
	material.set_shader_parameter("track_strength", 0.95)
	material.set_shader_parameter("edge_strength", 0.8)
	material.set_shader_parameter("pebble_amount", lerpf(0.34, 0.12, overgrown))
	return material
