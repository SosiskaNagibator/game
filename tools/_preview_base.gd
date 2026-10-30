extends Node3D

var _camera: Camera3D
var _base: Node3D


func _ready() -> void:
	var ps := load("res://scenes/rural_base.tscn") as PackedScene
	_base = ps.instantiate()
	add_child(_base)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.near = 0.1
	_camera.far = 400.0
	add_child(_camera)
	_camera.current = true
	await get_tree().create_timer(1.2).timeout
	var y := RuralHeight.yard_height()
	var c := Vector3(-220.5, y, -167.5)
	await _shot(c + Vector3(29.0, 11.5, 33.0), c + Vector3(-1.0, 3.2, 2.0),
		"res://temp_base_exterior.png")
	await _shot(c + Vector3(-6.25, 2.05, 8.8), c + Vector3(-6.25, 1.7, -7.5),
		"res://temp_base_aisle.png")
	await _shot(c + Vector3(-2.0, 3.7, 20.0), c + Vector3(-2.0, 3.0, 5.0),
		"res://temp_base_loading.png")
	await _shot(c + Vector3(6.0, 5.55, 8.9), c + Vector3(9.3, 3.9, 5.6),
		"res://temp_base_office.png")
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
