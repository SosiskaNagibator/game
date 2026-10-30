extends Node3D

var _camera: Camera3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.47, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.86)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.13)
	sky_mat.ground_horizon_color = Color(0.55, 0.56, 0.52)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.near = 0.1
	_camera.far = 200.0
	add_child(_camera)
	_camera.current = true

	var wh := (load("res://scenes/Warehouse.tscn") as PackedScene).instantiate()
	wh.position = Vector3(0, 0, 0)
	add_child(wh)
	wh.position.y = 0.0

	await get_tree().process_frame
	await get_tree().process_frame
	await _shot(Vector3(29.0, 11.5, 33.0), Vector3(-1.0, 3.2, 2.0), "res://temp_wh_exterior.png")
	await _shot(Vector3(-6.25, 2.05, 8.8), Vector3(-6.25, 1.7, -7.5), "res://temp_wh_aisle.png")
	await _shot(Vector3(-2.0, 3.8, 20.0), Vector3(-2.0, 3.2, 5.0), "res://temp_wh_loading.png")
	await _shot(Vector3(6.0, 5.55, 8.9), Vector3(9.3, 3.9, 5.6), "res://temp_wh_office.png")
	get_tree().quit(0)


func _shot(pos: Vector3, target: Vector3, path: String) -> void:
	_camera.position = pos
	_camera.look_at(target, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
