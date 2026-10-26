@tool
extends Node3D
## Лента просёлочной дороги, повторяющая кривую и рельеф из RuralHeight.

const ROAD_SHADER := preload("res://shaders/road_gravel.gdshader")

@export var start_z: float = 320.0
@export var end_z: float = -380.0
@export var segment_length: float = 2.0
@export var width: float = 7.8
@export var surface_offset: float = 0.045


func _ready() -> void:
	if get_node_or_null("RoadMesh") != null:
		return
	_build()


func _build() -> void:
	var offsets: Array[float] = [-3.9, -2.9, -1.7, -0.75, 0.0, 0.75, 1.7, 2.9, 3.9]
	var rows: Array[float] = []
	var z: float = start_z
	while z >= end_z:
		rows.append(z)
		z -= segment_length

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for row_z in rows:
		var center_x: float = RuralHeight.road_x(row_z)
		var base_y: float = RuralHeight.road_y(row_z)

		# Направление дороги на север (-Z) и поперечная ось.
		var ahead: Vector3 = Vector3(
			RuralHeight.road_x(row_z - 0.5) - RuralHeight.road_x(row_z + 0.5),
			0.0,
			-1.0
		).normalized()
		var lateral := Vector3(-ahead.z, 0.0, ahead.x)

		for offset in offsets:
			var u: float = (offset / 3.9 + 1.0) * 0.5
			var crown: float = (1.0 - absf(offset) / 3.9) * 0.035
			var pos: Vector3 = Vector3(center_x, base_y + surface_offset + crown, row_z) + lateral * offset
			st.set_uv(Vector2(u, row_z * 0.02))
			st.add_vertex(pos)

	var columns: int = offsets.size()
	for row in rows.size() - 1:
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

	var material := ShaderMaterial.new()
	material.shader = ROAD_SHADER

	var instance := MeshInstance3D.new()
	instance.name = "RoadMesh"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
