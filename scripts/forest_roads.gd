class_name ForestRoads
extends RefCounted
## Сеть просёлочных дорог через густой лес.
##
## Дороги задаются опорными точками и сглаживаются сплайном Катмулла-Рома.
## Здесь же строится сетка «ближайшая дорога» (расстояние, высота полотна,
## ширина, номер дороги), по которой рельеф делает пологие насыпи под дорогой,
## а растительность не сажается на проезжую часть.

const WORLD_HALF := 400.0
## Шаг сетки дорог, м. Двух метров достаточно: расстояние интерполируется,
## поэтому кромка полотна остаётся плавной, а построение — быстрым.
const GRID_STEP := 2.0
const GRID_RES := 401
## Радиус заливки поля дорог: чуть больше зоны влияния, чтобы высота полотна
## была корректной у самой границы смешивания.
const SPLAT_RADIUS := 16.0

static var _epoch: int = -1
static var _roads: Array[Dictionary] = []
static var _dist := PackedFloat32Array()
static var _elev := PackedFloat32Array()
static var _half := PackedFloat32Array()
static var _ids := PackedInt32Array()


## Пересобрать сеть, если изменилась версия мира.
static func build(epoch: int) -> void:
	if epoch == _epoch:
		return
	_epoch = epoch
	_roads.clear()
	_create_roads()
	_build_field()


static func roads() -> Array[Dictionary]:
	return _roads


## Расстояние до осевой линии, высота полотна и половина ширины.
## x — расстояние (м), y — высота (м), z — половина ширины (м).
static func sample3(x: float, z: float) -> Vector3:
	if _dist.is_empty():
		return Vector3(999.0, 0.0, 0.0)
	var fx: float = clampf((x + WORLD_HALF) / GRID_STEP, 0.0, float(GRID_RES - 2))
	var fz: float = clampf((z + WORLD_HALF) / GRID_STEP, 0.0, float(GRID_RES - 2))
	var x0: int = int(fx)
	var z0: int = int(fz)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var i: int = z0 * GRID_RES + x0
	var tx1: float = 1.0 - tx
	var tz1: float = 1.0 - tz

	var d: float = (
		_dist[i] * tx1 * tz1
		+ _dist[i + 1] * tx * tz1
		+ _dist[i + GRID_RES] * tx1 * tz
		+ _dist[i + GRID_RES + 1] * tx * tz
	)
	var h: float = (
		_elev[i] * tx1 * tz1
		+ _elev[i + 1] * tx * tz1
		+ _elev[i + GRID_RES] * tx1 * tz
		+ _elev[i + GRID_RES + 1] * tx * tz
	)
	var w: float = (
		_half[i] * tx1 * tz1
		+ _half[i + 1] * tx * tz1
		+ _half[i + GRID_RES] * tx1 * tz
		+ _half[i + GRID_RES + 1] * tx * tz
	)
	return Vector3(d, h, w)


static func road_id_at(x: float, z: float) -> int:
	if _ids.is_empty():
		return -1
	var ix: int = clampi(int(round((x + WORLD_HALF) / GRID_STEP)), 0, GRID_RES - 1)
	var iz: int = clampi(int(round((z + WORLD_HALF) / GRID_STEP)), 0, GRID_RES - 1)
	return _ids[iz * GRID_RES + ix]


## Насколько дорога заросла: 0 — укатанный гравий, 1 — старая лесовозная колея.
static func overgrown_at(x: float, z: float) -> float:
	var id: int = road_id_at(x, z)
	if id < 0 or id >= _roads.size():
		return 0.0
	return float(_roads[id]["overgrown"])


# --- Описание дорог ---------------------------------------------------------


static func _create_roads() -> void:
	var defs: Array[Dictionary] = [
		{
			"name": "Hollow Creek Road",
			"width": 5.8,
			"overgrown": 0.08,
			"points": PackedVector2Array([
				Vector2(152.0, 352.0), Vector2(147.0, 324.0),
				Vector2(136.0, 296.0), Vector2(128.0, 268.0),
				Vector2(139.0, 238.0), Vector2(152.0, 208.0),
				Vector2(139.0, 176.0), Vector2(113.0, 148.0),
				Vector2(97.0, 118.0), Vector2(70.0, 94.0),
				Vector2(57.0, 62.0), Vector2(31.0, 39.0),
				Vector2(4.0, 21.0), Vector2(-21.0, 3.0),
				Vector2(-45.0, -19.0), Vector2(-58.0, -53.0),
				Vector2(-68.0, -89.0), Vector2(-71.0, -128.0),
				Vector2(-57.0, -167.0), Vector2(-29.0, -197.0),
				Vector2(5.0, -221.0), Vector2(45.0, -239.0),
				Vector2(83.0, -267.0), Vector2(110.0, -301.0),
				Vector2(122.0, -341.0), Vector2(111.0, -382.0),
			]),
		},
		{
			# Скрытый отворот к базе: узкая лесовозная дорога.
			"name": "Logging Spur",
			"width": 4.2,
			"overgrown": 0.32,
			"points": PackedVector2Array([
				Vector2(-45.0, -19.0), Vector2(-68.0, -7.0),
				Vector2(-98.0, -15.0), Vector2(-131.0, -41.0),
				Vector2(-164.0, -69.0), Vector2(-195.0, -95.0),
				Vector2(-214.0, -121.0), Vector2(-223.0, -142.0),
				Vector2(-225.0, -152.0),
			]),
		},
		{
			# Старая лесовозная петля вокруг базы, почти заросшая.
			"name": "Old Timber Loop",
			"width": 3.6,
			"overgrown": 0.85,
			"points": PackedVector2Array([
				Vector2(-164.0, -69.0), Vector2(-198.0, -58.0),
				Vector2(-238.0, -70.0), Vector2(-278.0, -97.0),
				Vector2(-301.0, -136.0), Vector2(-292.0, -178.0),
				Vector2(-258.0, -204.0), Vector2(-222.0, -207.0),
				Vector2(-191.0, -192.0), Vector2(-175.0, -160.0),
				Vector2(-168.0, -119.0), Vector2(-164.0, -69.0),
			]),
		},
		{
			# Деревенская грунтовка от главной улицы к хутору.
			"name": "Farm Lane",
			"width": 3.4,
			"overgrown": 0.28,
			"points": PackedVector2Array([
				Vector2(139.0, 314.0), Vector2(118.0, 312.0),
				Vector2(104.0, 300.0), Vector2(100.0, 280.0),
				Vector2(102.0, 266.0),
			]),
		},
	]

	for i in defs.size():
		var def: Dictionary = defs[i]
		var raw: PackedVector2Array = _resample(def["points"], 1.8)
		var ys := PackedFloat32Array()
		ys.resize(raw.size())
		for k in raw.size():
			ys[k] = RuralHeight.natural_height(raw[k].x, raw[k].y)
		ys = _smooth_profile(ys)

		var pts := PackedVector3Array()
		pts.resize(raw.size())
		for k in raw.size():
			pts[k] = Vector3(raw[k].x, ys[k], raw[k].y)

		_roads.append({
			"name": String(def["name"]),
			"half_width": float(def["width"]) * 0.5,
			"overgrown": float(def["overgrown"]),
			"points": pts,
		})


static func _resample(control: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count: int = control.size()
	if count < 2:
		return control
	for i in count - 1:
		var p0: Vector2 = control[maxi(i - 1, 0)]
		var p1: Vector2 = control[i]
		var p2: Vector2 = control[i + 1]
		var p3: Vector2 = control[mini(i + 2, count - 1)]
		var steps: int = maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for s in steps:
			var t: float = float(s) / float(steps)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(control[count - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


## Сглаживание продольного профиля: дорога не повторяет каждую кочку,
## а плавно обходит холмы.
static func _smooth_profile(values: PackedFloat32Array) -> PackedFloat32Array:
	var cur: PackedFloat32Array = values.duplicate()
	for _pass in 3:
		var next: PackedFloat32Array = cur.duplicate()
		for i in range(1, cur.size() - 1):
			next[i] = (cur[i - 1] + 2.0 * cur[i] + cur[i + 1]) * 0.25
		cur = next
	for _pass in 2:
		var next: PackedFloat32Array = cur.duplicate()
		for i in cur.size():
			var sum: float = 0.0
			var amount: float = 0.0
			for k in range(-5, 6):
				var j: int = clampi(i + k, 0, cur.size() - 1)
				sum += cur[j]
				amount += 1.0
			next[i] = sum / amount
		cur = next
	return cur


# --- Поле дорог -------------------------------------------------------------


static func _build_field() -> void:
	var cells: int = GRID_RES * GRID_RES
	_dist.resize(cells)
	_dist.fill(999.0)
	_elev.resize(cells)
	_elev.fill(0.0)
	_half.resize(cells)
	_half.fill(0.0)
	_ids.resize(cells)
	_ids.fill(-1)

	for road_index in _roads.size():
		var road: Dictionary = _roads[road_index]
		var pts: PackedVector3Array = road["points"]
		var half_width: float = road["half_width"]
		for s in pts.size() - 1:
			var a: Vector3 = pts[s]
			var b: Vector3 = pts[s + 1]
			var sx: float = b.x - a.x
			var sz: float = b.z - a.z
			var seg_len2: float = sx * sx + sz * sz
			var min_x: float = minf(a.x, b.x) - SPLAT_RADIUS
			var max_x: float = maxf(a.x, b.x) + SPLAT_RADIUS
			var min_z: float = minf(a.z, b.z) - SPLAT_RADIUS
			var max_z: float = maxf(a.z, b.z) + SPLAT_RADIUS
			var ix0: int = clampi(int(floor((min_x + WORLD_HALF) / GRID_STEP)), 0, GRID_RES - 1)
			var ix1: int = clampi(int(ceil((max_x + WORLD_HALF) / GRID_STEP)), 0, GRID_RES - 1)
			var iz0: int = clampi(int(floor((min_z + WORLD_HALF) / GRID_STEP)), 0, GRID_RES - 1)
			var iz1: int = clampi(int(ceil((max_z + WORLD_HALF) / GRID_STEP)), 0, GRID_RES - 1)

			for iz in range(iz0, iz1 + 1):
				var wz: float = -WORLD_HALF + float(iz) * GRID_STEP
				var row: int = iz * GRID_RES
				for ix in range(ix0, ix1 + 1):
					var wx: float = -WORLD_HALF + float(ix) * GRID_STEP
					var t: float = 0.0
					if seg_len2 > 0.0001:
						t = clampf(
							((wx - a.x) * sx + (wz - a.z) * sz) / seg_len2,
							0.0, 1.0
						)
					var dx: float = wx - (a.x + sx * t)
					var dz: float = wz - (a.z + sz * t)
					var d2: float = dx * dx + dz * dz
					var idx: int = row + ix
					if d2 < _dist[idx] * _dist[idx]:
						_dist[idx] = sqrt(d2)
						_elev[idx] = a.y + (b.y - a.y) * t
						_half[idx] = half_width
						_ids[idx] = road_index
