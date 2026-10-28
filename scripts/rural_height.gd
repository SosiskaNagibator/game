class_name RuralHeight
extends RefCounted
## Общая функция высоты для всей сцены: сплошной лес, сеть просёлочных дорог,
## скрытая база в низине и деревня у южной кромки карты.
##
## Рельеф, дороги, заборы, лес и постройки используют одни и те же вычисления,
## поэтому ничего не «висит» в воздухе и не проваливается.

const WORLD_HALF := 400.0
## Версия мира: при изменении формулы высоты/сети дорог увеличиваем — поле
## пересобирается, не дожидаясь перезапуска редактора.
const WORLD_EPOCH := 3

# --- Скрытая база в чаще ----------------------------------------------------
const BASE_CENTER := Vector2(-228.0, -166.0)
const YARD_HALF := Vector2(18.0, 18.0)
const YARD_FEATHER := 5.5
# Цвет площадки растекается по земле гораздо уже, чем сам рельеф.
const YARD_COLOR_FEATHER := 2.2
# Лесная просека вокруг базы: деревья стоят плотным кольцом в 12–13 м
# от края двора и полностью скрывают постройки.
const CLEARING_HALF := Vector2(27.0, 25.0)
const CLEARING_FEATHER := 9.0

# --- Деревня у южной кромки -------------------------------------------------
const SETTLEMENT_CENTER := Vector2(140.0, 300.0)
const SETTLEMENT_HALF := Vector2(60.0, 46.0)
const SETTLEMENT_FEATHER := 16.0

## Небольшие лесные поляны: там светлее, растёт трава и стоят пни.
const GLADES := [
	Vector3(62.0, -92.0, 16.0),
	Vector3(-118.0, 118.0, 20.0),
	Vector3(252.0, 120.0, 18.0),
	Vector3(-305.0, 78.0, 16.0),
	Vector3(28.0, 196.0, 14.0),
	Vector3(255.0, 245.0, 18.0),
]

static var _world_ready: bool = false
static var _yard_y: float = 0.0
static var _settlement_y: float = 0.0

static var _base_noise: FastNoiseLite
static var _micro_noise: FastNoiseLite
static var _density_noise: FastNoiseLite


static func _ensure_world() -> void:
	if _world_ready:
		return
	ForestRoads.build(WORLD_EPOCH)
	_yard_y = _flat_height(BASE_CENTER, 16.0) + 0.12
	_settlement_y = _flat_height(SETTLEMENT_CENTER, 22.0)
	_world_ready = true


static func _flat_height(center: Vector2, radius: float) -> float:
	var sum: float = 0.0
	sum += natural_height(center.x, center.y) * 2.0
	sum += natural_height(center.x + radius, center.y)
	sum += natural_height(center.x - radius, center.y)
	sum += natural_height(center.x, center.y + radius)
	sum += natural_height(center.x, center.y - radius)
	return sum / 6.0


# --- Шум --------------------------------------------------------------------


static func _get_base_noise() -> FastNoiseLite:
	if _base_noise == null:
		_base_noise = FastNoiseLite.new()
		_base_noise.seed = 7321
		_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_base_noise.frequency = 0.0056
		_base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_base_noise.fractal_octaves = 4
		_base_noise.fractal_gain = 0.52
		_base_noise.fractal_lacunarity = 2.05
	return _base_noise


static func _get_micro_noise() -> FastNoiseLite:
	if _micro_noise == null:
		_micro_noise = FastNoiseLite.new()
		_micro_noise.seed = 991
		_micro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_micro_noise.frequency = 0.045
		_micro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_micro_noise.fractal_octaves = 2
	return _micro_noise


static func _get_density_noise() -> FastNoiseLite:
	if _density_noise == null:
		_density_noise = FastNoiseLite.new()
		_density_noise.seed = 4242
		_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_density_noise.frequency = 0.016
		_density_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_density_noise.fractal_octaves = 3
	return _density_noise


# --- Рельеф -----------------------------------------------------------------


## Чистый рельеф без дорог и площадок. Дороги строят по нему свой профиль,
## поэтому эта функция не должна вызывать _ensure_world().
static func natural_height(x: float, z: float) -> float:
	var n1: float = _get_base_noise().get_noise_2d(x, z)
	var n2: float = _get_base_noise().get_noise_2d(x * 2.7 + 140.0, z * 2.7 - 70.0)
	var n3: float = _get_micro_noise().get_noise_2d(x, z)

	var h: float = 9.0 * n1 + 2.4 * n2 + 0.45 * n3

	# Скрытая низина под базой: чаща вокруг выше, постройки не видно
	# с дороги, пока не подойдёшь к воротам.
	var to_base: float = Vector2(x, z).distance_to(BASE_CENTER)
	h -= 5.2 * (1.0 - smoothstep(35.0, 150.0, to_base))

	# Гряды по краям карты, чтобы горизонт не обрывался в пустоту.
	var edge: float = smoothstep(295.0, 400.0, maxf(absf(x), absf(z)))
	h += edge * edge * 12.0
	return h


## Высота земли в мировых координатах: холмы, насыпь под дорогой, площадки.
static func terrain_height(x: float, z: float) -> float:
	_ensure_world()
	var h: float = natural_height(x, z)

	var road: Vector3 = ForestRoads.sample3(x, z)
	if road.x < 10.0:
		var blend: float = 1.0 - smoothstep(road.z + 0.55, road.z + 4.4, road.x)
		h = lerpf(h, road.y, blend)

	var yard: float = yard_mask(x, z)
	if yard > 0.0:
		h = lerpf(h, _yard_y, yard)

	var settlement: float = settlement_mask(x, z)
	if settlement > 0.0:
		h = lerpf(h, _settlement_y, settlement)
	return h


## Нормаль рельефа — пригодится для посадки объектов.
static func terrain_normal(x: float, z: float) -> Vector3:
	var e: float = 1.0
	var hx: float = terrain_height(x + e, z) - terrain_height(x - e, z)
	var hz: float = terrain_height(x, z + e) - terrain_height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


# --- Площадки ---------------------------------------------------------------


static func yard_height() -> float:
	_ensure_world()
	return _yard_y


static func settlement_height() -> float:
	_ensure_world()
	return _settlement_y


## 1 внутри двора базы, 0 снаружи, плавный переход по краям.
static func yard_mask(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - BASE_CENTER.x) - YARD_HALF.x, 0.0)
	var dz: float = maxf(absf(z - BASE_CENTER.y) - YARD_HALF.y, 0.0)
	return 1.0 - smoothstep(0.0, YARD_FEATHER, sqrt(dx * dx + dz * dz))


## Более узкая маска для цвета земли: двор не «расплывается» на газон.
static func yard_color_mask(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - BASE_CENTER.x) - YARD_HALF.x, 0.0)
	var dz: float = maxf(absf(z - BASE_CENTER.y) - YARD_HALF.y, 0.0)
	return 1.0 - smoothstep(0.0, YARD_COLOR_FEATHER, sqrt(dx * dx + dz * dz))


## Лесная просека вокруг базы (1 — открытое место, 0 — лес).
static func base_clearing_mask(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - BASE_CENTER.x) - CLEARING_HALF.x, 0.0)
	var dz: float = maxf(absf(z - BASE_CENTER.y) - CLEARING_HALF.y, 0.0)
	return 1.0 - smoothstep(0.0, CLEARING_FEATHER, sqrt(dx * dx + dz * dz))


## Деревенская поляна.
static func settlement_mask(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - SETTLEMENT_CENTER.x) - SETTLEMENT_HALF.x, 0.0)
	var dz: float = maxf(absf(z - SETTLEMENT_CENTER.y) - SETTLEMENT_HALF.y, 0.0)
	return 1.0 - smoothstep(0.0, SETTLEMENT_FEATHER, sqrt(dx * dx + dz * dz))


## Поляны: 1 в центре, 0 к краю.
static func glade_mask(x: float, z: float) -> float:
	var result: float = 0.0
	for glade in GLADES:
		var d: float = Vector2(x - glade.x, z - glade.y).length()
		result = maxf(result, 1.0 - smoothstep(glade.z * 0.42, glade.z, d))
	return result


## Насколько густо здесь сажать лес, 0…1.
static func forest_density(x: float, z: float) -> float:
	_ensure_world()
	var road: Vector3 = ForestRoads.sample3(x, z)
	var density: float = smoothstep(road.z + 1.4, road.z + 4.6, road.x)
	density *= 1.0 - base_clearing_mask(x, z)
	density *= 1.0 - settlement_mask(x, z)
	density *= 1.0 - glade_mask(x, z)

	# Прорехи и чащобы: лес не должен быть ровным «ковром».
	var n: float = _get_density_noise().get_noise_2d(x, z) * 0.5 + 0.5
	var patches: float = smoothstep(0.28, 0.62, n)
	density *= 0.56 + 0.44 * patches
	return clampf(density, 0.0, 1.0)


static func road_distance(x: float, z: float) -> float:
	return ForestRoads.sample3(x, z).x


static func road_half_width(x: float, z: float) -> float:
	return ForestRoads.sample3(x, z).z


static func foliage_color(rng: RandomNumberGenerator) -> Color:
	var palette := [
		Color(0.26, 0.41, 0.13),
		Color(0.19, 0.33, 0.09),
		Color(0.33, 0.44, 0.15),
		Color(0.15, 0.28, 0.07),
		Color(0.38, 0.45, 0.17),
		Color(0.22, 0.37, 0.11),
	]
	return palette[rng.randi_range(0, palette.size() - 1)]
