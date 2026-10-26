@tool
extends Node3D
## Строит полотно рельефа и коллизию (HeightMapShape3D) по функции RuralHeight.
## Работает и в редакторе (@tool), и в игре.

const TERRAIN_SHADER := preload("res://shaders/terrain_grass.gdshader")

@export var terrain_size: float = 800.0
@export_range(65, 513, 1) var resolution: int = 321


func _ready() -> void:
	if get_node_or_null("TerrainMesh") != null:
		return
	_build()


func _build() -> void:
	var cells: int = resolution - 1
	var step: float = terrain_size / float(cells)
	var half: float = terrain_size * 0.5
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)

	var color_noise := FastNoiseLite.new()
	color_noise.seed = 4451
	color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	color_noise.frequency = 0.045
	color_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	color_noise.fractal_octaves = 3

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var grass_dark := Color(0.16, 0.29, 0.07)
	var grass_light := Color(0.38, 0.53, 0.14)
	var dry_grass := Color(0.62, 0.58, 0.32)
	var dirt := Color(0.49, 0.42, 0.31)
	var gravel := Color(0.55, 0.52, 0.45)

	for iz in resolution:
		var z: float = -half + float(iz) * step
		for ix in resolution:
			var x: float = -half + float(ix) * step
			var y: float = RuralHeight.terrain_height(x, z)
			heights[iz * resolution + ix] = y

			var n: float = color_noise.get_noise_2d(x * 1.15, z * 1.15) * 0.5 + 0.5
			var broad: float = color_noise.get_noise_2d(x * 0.22 + 120.0, z * 0.22 - 40.0) * 0.5 + 0.5
			var col: Color = grass_dark.lerp(grass_light, clampf(n * 0.75 + broad * 0.35, 0.0, 1.0))
			col = col.lerp(dry_grass, smoothstep(0.55, 0.92, broad) * 0.45)

			var road_distance: float = absf(x - RuralHeight.road_x(z))
			var road_mix: float = 1.0 - smoothstep(3.6, 5.6, road_distance)
			var dirt_col: Color = dirt.lerp(Color(0.61, 0.54, 0.42), n)
			col = col.lerp(dirt_col, road_mix * 0.88)

			var yard: float = RuralHeight.yard_mask(x, z)
			var gravel_col: Color = gravel * (0.88 + n * 0.22)
			col = col.lerp(gravel_col, smoothstep(0.12, 0.92, yard))

			st.set_color(col)
			st.add_vertex(Vector3(x, y, z))

	for iz in cells:
		for ix in cells:
			var i: int = iz * resolution + ix
			st.add_index(i)
			st.add_index(i + resolution)
			st.add_index(i + 1)

			st.add_index(i + 1)
			st.add_index(i + resolution)
			st.add_index(i + resolution + 1)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

	# HeightMapShape3D всегда использует шаг 1 м, поэтому масштабируем узел.
	var shape := HeightMapShape3D.new()
	shape.map_width = resolution
	shape.map_depth = resolution
	var scaled_data := PackedFloat32Array()
	scaled_data.resize(heights.size())
	for i in heights.size():
		scaled_data[i] = heights[i] / step
	shape.map_data = scaled_data

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.scale = Vector3(step, step, step)

	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
