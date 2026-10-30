extends SceneTree

func _init() -> void:
	var ps: PackedScene = load("res://scenes/props/WarehouseCrate.tscn")
	if ps == null:
		print("CRATE LOAD FAILED")
		quit()
		return
	var n: Node3D = ps.instantiate()
	var aabb := _aabb(n, Transform3D.IDENTITY)
	print("CRATE AABB: ", aabb)
	var ps2: PackedScene = load("res://scenes/props/WarehousePallet.tscn")
	var p: Node3D = ps2.instantiate()
	print("PALLET AABB: ", _aabb(p, Transform3D.IDENTITY))
	var ps3: PackedScene = load("res://scenes/props/WarehouseRack.tscn")
	var r: Node3D = ps3.instantiate()
	print("RACK AABB: ", _aabb(r, Transform3D.IDENTITY))
	n.free()
	p.free()
	r.free()
	quit()

func _aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var b: AABB = t * (node as MeshInstance3D).mesh.get_aabb()
		result = b
		first = false
	for c in node.get_children():
		var cb := _aabb(c, t)
		if cb.size != Vector3.ZERO:
			if first:
				result = cb
				first = false
			else:
				result = result.merge(cb)
	return result
