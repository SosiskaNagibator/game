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

	var grass_deep := Color(0.10, 0.19, 0.055)
	var grass_mid := Color(0.18, 0.29, 0.085)
	var grass_light := Color(0.28, 0.39, 0.115)
	var dry_grass := Color(0.47, 0.43, 0.24)
	var dirt := Color(0.36, 0.30, 0.21)
	var gravel := Color(0.38, 0.34, 0.27)

	for iz in resolution:
		var z: float = -half + float(iz) * step
		for ix in resolution:
			var x: float = -half + float(ix) * step
			var y: float = RuralHeight.terrain_height(x, z)
			heights[iz * resolution + ix] = y

			var n: float = color_noise.get_noise_2d(x * 1.15, z * 1.15) * 0.5 + 0.5
			var broad: float = color_noise.get_noise_2d(x * 0.22 + 120.0, z * 0.22 - 40.0) * 0.5 + 0.5
			var fine: float = color_noise.get_noise_2d(x * 3.3 - 80.0, z * 3.3 + 33.0) * 0.5 + 0.5
			var col: Color = grass_deep.lerp(grass_mid, smoothstep(0.05, 0.85, n))
			col = col.lerp(grass_light, smoothstep(0.25, 0.95, n * 0.55 + broad * 0.45) * 0.8)

			# Выгоревшие луговые пятна — неровные, разного размера.
			var dry: float = smoothstep(0.54, 0.88, broad) * (0.45 + 0.55 * fine)
			col = col.lerp(dry_grass, dry * 0.5)

			# Тёмные пятна сырой земли/бурьяна между луговинами.
			var patch: float = smoothstep(0.68, 0.94, fine * 0.7 + n * 0.3)
			col = col.lerp(Color(0.15, 0.21, 0.08), patch * 0.35)

			var road_distance: float = absf(x - RuralHeight.road_x(z))
			var road_mix: float = 1.0 - smoothstep(3.6, 5.6, road_distance)
			var dirt_col: Color = dirt.lerp(Color(0.50, 0.43, 0.32), n)
			col = col.lerp(dirt_col, road_mix * 0.88)

			var yard: float = RuralHeight.yard_color_mask(x, z)
			var gravel_col: Color = gravel.lerp(Color(0.30, 0.26, 0.20), fine * 0.55)
			gravel_col = gravel_col * (0.88 + n * 0.26)
			# Утоптанная тёмная кромка двора.
			var rim: float = smoothstep(0.45, 0.85, yard) * (1.0 - smoothstep(0.88, 1.0, yard))
			gravel_col = gravel_col.darkened(rim * 0.22)
			col = col.lerp(gravel_col, smoothstep(0.18, 0.92, yard))

			st.set_color(col)
			st.add_vertex(Vector3(x, y, z))

	for iz in cells:
		for ix in cells:
			var i: int = iz * resolution + ix
			# Так нормали смотрят вверх. При обратном порядке они были
			# направлены вниз, и весь рельеф отсекался как обратная
			# сторона — вместо земли была видна «земля» из шейдера неба.
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + resolution)

			st.add_index(i + 1)
			st.add_index(i + resolution + 1)
			st.add_index(i + resolution)

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
