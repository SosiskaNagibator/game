@tool
class_name DecorGrounding
extends Node3D

const GROUND_CLEARANCE := 0.02


func _ready() -> void:
	for child in get_children():
		var prop := child as Node3D
		if prop == null:
			continue
		var bottom: float = bottom_offset(prop)
		if not is_finite(bottom):
			continue
		prop.position.y = (
				RuralHeight.terrain_height(prop.position.x, prop.position.z)
				- bottom
				+ GROUND_CLEARANCE
		)


static func bottom_offset(root: Node3D) -> float:
	return _lowest_mesh_y(root, Transform3D.IDENTITY, root)


static func _lowest_mesh_y(node: Node, parent_transform: Transform3D, root: Node3D) -> float:
	var current_transform := parent_transform
	if node == root:
		current_transform = Transform3D(root.transform.basis, Vector3.ZERO)
	elif node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform

	var lowest: float = INF
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner in 8:
			lowest = minf(lowest, (current_transform * bounds.get_endpoint(corner)).y)

	for child in node.get_children():
		lowest = minf(lowest, _lowest_mesh_y(child, current_transform, root))
	return lowest
