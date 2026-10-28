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

	# Лесная подстилка: тёмный мох, хвоя, прелая листва.
	var floor_deep := Color(0.050, 0.082, 0.030)
	var floor_mid := Color(0.085, 0.130, 0.048)
	var floor_moss := Color(0.125, 0.185, 0.062)
	var leaf_litter := Color(0.185, 0.145, 0.085)

	# Открытые места: поляны и деревенские луга.
	var grass_deep := Color(0.105, 0.175, 0.052)
	var grass_mid := Color(0.185, 0.280, 0.082)
	var grass_light := Color(0.295, 0.385, 0.110)
	var dry_grass := Color(0.455, 0.420, 0.230)

	var dirt := Color(0.325, 0.265, 0.180)
	var gravel := Color(0.370, 0.335, 0.265)

	for iz in resolution:
		var z: float = -half + float(iz) * step
		for ix in resolution:
			var x: float = -half + float(ix) * step
			var y: float = RuralHeight.terrain_height(x, z)
			heights[iz * resolution + ix] = y

			var n: float = color_noise.get_noise_2d(x * 1.15, z * 1.15) * 0.5 + 0.5
			var broad: float = color_noise.get_noise_2d(x * 0.22 + 120.0, z * 0.22 - 40.0) * 0.5 + 0.5
			var fine: float = color_noise.get_noise_2d(x * 3.3 - 80.0, z * 3.3 + 33.0) * 0.5 + 0.5

			# Основа — тёмный лесной пол.
			var col: Color = floor_deep.lerp(floor_mid, smoothstep(0.08, 0.82, n))
			col = col.lerp(floor_moss, smoothstep(0.30, 0.95, n * 0.5 + broad * 0.5) * 0.7)

			# Пятна прелой листвы и хвои под кронами.
			var litter: float = smoothstep(0.52, 0.86, broad * 0.6 + fine * 0.4)
			col = col.lerp(leaf_litter, litter * 0.42)

			# Поляны, двор и деревня — луговые, более светлые.
			var clearing: float = RuralHeight.base_clearing_mask(x, z)
			var village: float = RuralHeight.settlement_mask(x, z)
			var glade: float = RuralHeight.glade_mask(x, z)
			var open: float = clampf(maxf(maxf(clearing, village), glade), 0.0, 1.0)

			var meadow: Color = grass_deep.lerp(grass_mid, smoothstep(0.05, 0.85, n))
			meadow = meadow.lerp(grass_light, smoothstep(0.25, 0.95, n * 0.55 + broad * 0.45) * 0.8)
			var dry: float = smoothstep(0.54, 0.88, broad) * (0.45 + 0.55 * fine)
			meadow = meadow.lerp(dry_grass, dry * 0.45)
			col = col.lerp(meadow, open)

			# Дороги: земляное полотно с узкой пыльной обочиной.
			var road: Vector3 = ForestRoads.sample3(x, z)
			if road.x < road.z + 2.2:
				var road_mix: float = 1.0 - smoothstep(road.z * 0.94, road.z + 1.05, road.x)
				var overgrown: float = ForestRoads.overgrown_at(x, z)
				var dirt_col: Color = dirt.lerp(Color(0.46, 0.39, 0.28), n)
				if overgrown > 0.4:
					dirt_col = dirt_col.lerp(Color(0.215, 0.235, 0.105), overgrown * 0.45)
				col = col.lerp(dirt_col, road_mix * 0.9)

			# Утоптанный двор базы: гравий.
			var yard: float = RuralHeight.yard_color_mask(x, z)
			var gravel_col: Color = gravel.lerp(Color(0.285, 0.250, 0.195), fine * 0.55)
			gravel_col = gravel_col * (0.88 + n * 0.26)
			var rim: float = smoothstep(0.45, 0.85, yard) * (1.0 - smoothstep(0.88, 1.0, yard))
			gravel_col = gravel_col.darkened(rim * 0.22)
			col = col.lerp(gravel_col, smoothstep(0.18, 0.92, yard))

			# Деревенские дворы чуть вытоптаны у дороги.
			if village > 0.3:
				var worn: float = smoothstep(road.z + 0.8, road.z + 5.5, road.x)
				col = col.lerp(Color(0.315, 0.285, 0.185), (1.0 - worn) * village * 0.35)

			# В чаще темнее: меньше света до земли.
			var density: float = RuralHeight.forest_density(x, z)
			col = col.darkened(clampf(density * 0.30, 0.0, 0.30))

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
	# Метка «это земля»: по ней редактор ландшафта отличает рельеф от прочих тел,
	# деревьев, заборов и построек, сквозь которые луч должен проходить.
	body.set_meta("terrain_ground", true)

	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
