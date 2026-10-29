@tool
extends Node3D
@export var populate: bool = false:
	set(v):
		populate = v
		if v and Engine.is_editor_hint():
			_do_populate()
func _ready():
	print("POPULATE _ready called, editor=", Engine.is_editor_hint(), " populate=", populate)
	if Engine.is_editor_hint() and populate:
		_do_populate()
func _do_populate():
	ForestRoads.build(RuralHeight.WORLD_EPOCH)
	var tree_paths: Array[String] = [
		"res://scenes/props/Tree_1.tscn",
		"res://scenes/props/Tree_2.tscn",
		"res://scenes/props/Tree_3.tscn",
		"res://scenes/props/Tree_5.tscn",
		"res://scenes/props/Tree_7.tscn",
	]
	var cache: Dictionary = {}
	for p in tree_paths:
		cache[p] = load(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99123
	var placements: Array = []
	# light roadside
	var roads: Array = ForestRoads.roads()
	for road in roads:
		var pts: PackedVector3Array = road["points"]
		if pts.size() < 2:
			continue
		var i := 0
		while i < pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i+1]
			var seg_len := Vector2(b.x-a.x, b.z-a.z).length()
			var steps := maxi(1, int(seg_len / 25.0))
			for s in range(steps):
				var t := float(s) / float(steps)
				var px := lerpf(a.x, b.x, t)
				var pz := lerpf(a.z, b.z, t)
				var ahead := Vector3(b.x-a.x, 0.0, b.z-a.z).normalized()
				if ahead.length_squared() < 0.0001:
					ahead = Vector3.FORWARD
				var lateral := Vector3(-ahead.z, 0.0, ahead.x)
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.6:
						continue
					var off: float = rng.randf_range(10.0, 16.0) * float(side)
					var x: float = px + lateral.x * off
					var z: float = pz + lateral.z * off
					if Vector2(x+253, z+264).length() < 60.0:
						continue
					if ForestRoads.sample3(x, z).x < 12.0:
						continue
					var y := RuralHeight.terrain_height(x, z)
					var scene_path: String = tree_paths[rng.randi_range(0, tree_paths.size()-1)]
					var sc := rng.randf_range(0.8, 1.0)
					placements.append({"scene": scene_path, "pos": Vector3(x, y, z), "rot": rng.randf() * TAU, "scale": sc})
			i += 1
	# grid fill
	var grid_step := 24.0
	var half := 360.0
	var gx := -half
	while gx <= half:
		var gz := -half
		while gz <= half:
			var info: Vector3 = ForestRoads.sample3(gx, gz)
			if info.x < 12.0:
				gz += grid_step
				continue
			if Vector2(gx+253, gz+264).length() < 70.0:
				gz += grid_step
				continue
			if rng.randf() < 0.45:
				gz += grid_step
				continue
			var placement_x: float = gx + rng.randf_range(-3.0, 3.0)
			var placement_z: float = gz + rng.randf_range(-3.0, 3.0)
			var y := RuralHeight.terrain_height(placement_x, placement_z)
			var scene_path: String = tree_paths[rng.randi_range(0, tree_paths.size()-1)]
			var sc := rng.randf_range(0.8, 1.1)
			placements.append({"scene": scene_path, "pos": Vector3(placement_x, y, placement_z), "rot": rng.randf() * TAU, "scale": sc})
			gz += grid_step
		gx += grid_step
	print("total placements: ", placements.size())

	# load rural_base, add Decor node with individual instances
	var rb_packed = load("res://scenes/rural_base.tscn")
	if rb_packed == null:
		print("FAIL load rural_base"); populate=false; return
	var rb_inst = rb_packed.instantiate()
	add_child(rb_inst)
	var decor: Node3D = rb_inst.get_node_or_null("Decor") as Node3D
	if decor == null:
		decor = Node3D.new()
		decor.name = "Decor"
		rb_inst.add_child(decor)
		decor.owner = rb_inst
	else:
		for c in decor.get_children():
			decor.remove_child(c)
			c.queue_free()
	for pl in placements:
		var ps = load(pl["scene"])
		if ps == null:
			continue
		var node = ps.instantiate()
		node.position = pl["pos"]
		node.rotation.y = pl["rot"]
		var sc: float = pl["scale"]
		node.scale *= Vector3(sc, sc, sc)
		var bottom: float = DecorGrounding.bottom_offset(node)
		if is_finite(bottom):
			node.position.y = RuralHeight.terrain_height(node.position.x, node.position.z) - bottom + 0.02
		decor.add_child(node)
		node.owner = decor
	# repack into a fresh PackedScene
	var fresh := PackedScene.new()
	var e: int = fresh.pack(rb_inst)
	if e != OK:
		print("pack fail rural_base: ", e)
	else:
		e = ResourceSaver.save(fresh, "res://scenes/rural_base.tscn")
		if e != OK:
			print("save fail rural_base: ", e)
		else:
			print("saved rural_base.tscn with ", placements.size(), " decor instances")
	rb_inst.queue_free()
	populate = false
