extends Node
var base_noise: FastNoiseLite
var micro_noise: FastNoiseLite
var road_pts_list: Array = []
func _ready() -> void:
	_setup_noise()
	_setup_roads()
	_gen()
	get_tree().quit()
func _setup_noise() -> void:
	base_noise = FastNoiseLite.new()
	base_noise.seed = 7321
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = 0.0056
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 4
	base_noise.fractal_gain = 0.52
	base_noise.fractal_lacunarity = 2.05
	micro_noise = FastNoiseLite.new()
	micro_noise.seed = 991
	micro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	micro_noise.frequency = 0.045
	micro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	micro_noise.fractal_octaves = 2
func natural_height(x: float, z: float) -> float:
	var n1: float = base_noise.get_noise_2d(x, z)
	var n2: float = base_noise.get_noise_2d(x * 2.7 + 140.0, z * 2.7 - 70.0)
	var n3: float = micro_noise.get_noise_2d(x, z)
	var h: float = 9.0 * n1 + 2.4 * n2 + 0.45 * n3
	var to_base: float = Vector2(x, z).distance_to(Vector2(-228.0, -166.0))
	h -= 5.2 * (1.0 - smoothstep(35.0, 150.0, to_base))
	var edge: float = smoothstep(295.0, 400.0, maxf(absf(x), absf(z)))
	h += edge * edge * 12.0
	return h
func _setup_roads() -> void:
	var defs: Array = [
		[Vector2(152,352),Vector2(147,324),Vector2(136,296),Vector2(128,268),Vector2(139,238),Vector2(152,208),Vector2(139,176),Vector2(113,148),Vector2(97,118),Vector2(70,94),Vector2(57,62),Vector2(31,39),Vector2(4,21),Vector2(-21,3),Vector2(-45,-19),Vector2(-58,-53),Vector2(-68,-89),Vector2(-71,-128),Vector2(-57,-167),Vector2(-29,-197),Vector2(5,-221),Vector2(45,-239),Vector2(83,-267),Vector2(110,-301),Vector2(122,-341),Vector2(111,-382)],
		[Vector2(-45,-19),Vector2(-68,-7),Vector2(-98,-15),Vector2(-131,-41),Vector2(-164,-69),Vector2(-195,-95),Vector2(-214,-121),Vector2(-223,-142),Vector2(-225,-152)],
		[Vector2(-164,-69),Vector2(-198,-58),Vector2(-238,-70),Vector2(-278,-97),Vector2(-301,-136),Vector2(-292,-178),Vector2(-258,-204),Vector2(-222,-207),Vector2(-191,-192),Vector2(-175,-160),Vector2(-168,-119),Vector2(-164,-69)],
		[Vector2(139,314),Vector2(118,312),Vector2(104,300),Vector2(100,280),Vector2(102,266)],
	]
	for def in defs:
		var pts := PackedVector2Array()
		var ctrl: Array = def
		var cnt: int = ctrl.size()
		if cnt < 2:
			road_pts_list.append(pts); continue
		for i in range(cnt - 1):
			var p0: Vector2 = ctrl[maxi(i-1,0)]
			var p1: Vector2 = ctrl[i]
			var p2: Vector2 = ctrl[i+1]
			var p3: Vector2 = ctrl[mini(i+2, cnt-1)]
			var steps: int = maxi(1, int(ceil(p1.distance_to(p2) / 1.8)))
			for s in range(steps):
				var t: float = float(s)/float(steps)
				var t2: float = t*t; var t3: float = t2*t
				var pt: Vector2 = 0.5*(2.0*p1 + (p2-p0)*t + (2.0*p0 -5.0*p1 +4.0*p2 - p3)*t2 + (-p0 +3.0*p1 -3.0*p2 + p3)*t3)
				pts.append(pt)
		pts.append(ctrl[cnt-1])
		road_pts_list.append(pts)
func road_dist(x: float, z: float) -> float:
	var best := 999.0
	for pts in road_pts_list:
		for k in range(pts.size()-1):
			var a: Vector2 = pts[k]; var b: Vector2 = pts[k+1]
			var sx: float = b.x - a.x; var sz: float = b.y - a.y
			var seg2: float = sx*sx + sz*sz
			var t: float = 0.0
			if seg2 > 0.0001:
				t = clampf(((x-a.x)*sx + (z-a.y)*sz)/seg2, 0.0, 1.0)
			var dx: float = x - (a.x + sx*t)
			var dz: float = z - (a.y + sz*t)
			best = minf(best, sqrt(dx*dx + dz*dz))
	return best
func _gen() -> void:
	var tree_paths: Array[String] = [
		"res://scenes/props/Tree_1.tscn","res://scenes/props/Tree_2.tscn",
		"res://scenes/props/Tree_3.tscn","res://scenes/props/Tree_5.tscn",
		"res://scenes/props/Tree_7.tscn",
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99123
	var placements: Array = []
	# light roadside
	for pts in road_pts_list:
		var i := 0
		while i < pts.size() - 1:
			var a: Vector2 = pts[i]; var b: Vector2 = pts[i+1]
			var seg_len := a.distance_to(b)
			var steps := maxi(1, int(seg_len / 25.0))
			for s in range(steps):
				var t := float(s) / float(steps)
				var px := lerpf(a.x, b.x, t)
				var pz := lerpf(a.y, b.y, t)
				var ahead := Vector2(b.x-a.x, b.y-a.y).normalized()
				if ahead.length_squared() < 0.0001:
					ahead = Vector2(0,1)
				var lateral := Vector2(-ahead.y, ahead.x)
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.6:
						continue
					var off: float = rng.randf_range(10.0, 16.0) * float(side)
					var x: float = px + lateral.x * off
					var z: float = pz + lateral.y * off
					if Vector2(x+253, z+264).length() < 60.0:
						continue
					if road_dist(x, z) < 12.0:
						continue
					var y := natural_height(x, z)
					var scene_path: String = tree_paths[rng.randi_range(0, tree_paths.size()-1)]
					var sc := rng.randf_range(0.8, 1.0)
					placements.append({"scene": scene_path, "x": x, "y": y, "z": z, "rot": rng.randf()*TAU, "scale": sc})
			i += 1
	# dense fill
	var grid_step := 20.0
	var half := 360.0
	var gx := -half
	while gx <= half:
		var gz := -half
		while gz <= half:
			if road_dist(gx, gz) < 12.0:
				gz += grid_step; continue
			if Vector2(gx+253, gz+264).length() < 70.0:
				gz += grid_step; continue
			if rng.randf() < 0.4:
				gz += grid_step; continue
			var y := natural_height(gx + rng.randf_range(-3,3), gz + rng.randf_range(-3,3))
			var scene_path: String = tree_paths[rng.randi_range(0, tree_paths.size()-1)]
			var sc := rng.randf_range(0.8, 1.1)
			placements.append({"scene": scene_path, "x": gx + rng.randf_range(-3,3), "y": y, "z": gz + rng.randf_range(-3,3), "rot": rng.randf()*TAU, "scale": sc})
			gz += grid_step
		gx += grid_step
	print("placements: ", placements.size())
	var json := JSON.stringify(placements)
	var f := FileAccess.open("res://placements.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
		print("wrote placements.json")
	else:
		print("FAIL write")
	get_tree().quit()
