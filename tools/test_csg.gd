extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await process_frame
	var root := CSGCombiner3D.new()
	get_root().add_child(root)
	var box := CSGBox3D.new()
	box.size = Vector3(2, 1, 3)
	root.add_child(box)
	var cyl := CSGCylinder3D.new()
	cyl.radius = 0.6
	cyl.height = 3.0
	cyl.rotation_degrees = Vector3(0, 0, 90)
	cyl.position = Vector3(0, -0.6, 0)
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_child(cyl)
	await process_frame
	await process_frame
	var mesh: ArrayMesh = root.bake_static_mesh()
	print("BAKED: ", mesh)
	if mesh:
		print("AABB ", mesh.get_aabb(), " surfaces=", mesh.get_surface_count())
	quit()
