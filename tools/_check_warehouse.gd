extends Node3D

func _ready() -> void:
	var ps := load("res://scenes/Warehouse.tscn") as PackedScene
	if ps == null:
		print("WAREHOUSE LOAD FAILED")
		get_tree().quit(1)
		return
	var w := ps.instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var counts := {}
	_count(w, counts)
	print("WAREHOUSE OK")
	print("CHILDREN: ", w.get_child_count())
	print("COUNTS: ", counts)
	print("POSITION: ", w.position)
	var boxes := 0
	var mm := 0
	for n in w.find_children("*", "MultiMeshInstance3D", true, false):
		mm += 1
		var m := n as MultiMeshInstance3D
		print("MM ", n.name, " instances=", m.multimesh.instance_count)
	for n in w.find_children("*", "MeshInstance3D", true, false):
		boxes += 1
	print("MESH INSTANCES: ", boxes)
	get_tree().quit(0)


func _count(node: Node, counts: Dictionary) -> void:
	var k := node.get_class()
	counts[k] = int(counts.get(k, 0)) + 1
	for c in node.get_children():
		_count(c, counts)
