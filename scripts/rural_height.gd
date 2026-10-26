class_name RuralHeight
extends RefCounted
## Общая функция высоты для всей сцены.
##
## Рельеф, дорога, заборы, трава и постройки используют одни и те же
## вычисления, поэтому ничего не «висит» в воздухе и не проваливается.

const WORLD_HALF := 400.0
const ROAD_HALF_WIDTH := 3.9
const FENCE_OFFSET := 6.4

# Прямоугольная площадка базы с закруглёнными краями.
const YARD_CENTER := Vector2(25.0, 98.0)
const YARD_HALF := Vector2(18.0, 18.0)
const YARD_FEATHER := 5.5

static var _base_noise: FastNoiseLite
static var _micro_noise: FastNoiseLite


static func _get_base_noise() -> FastNoiseLite:
	if _base_noise == null:
		_base_noise = FastNoiseLite.new()
		_base_noise.seed = 7321
		_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_base_noise.frequency = 0.0042
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
		_micro_noise.frequency = 0.09
		_micro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_micro_noise.fractal_octaves = 2
	return _micro_noise


## Медленная S-образная кривая дороги. Ось Z — направление на север.
static func road_x(z: float) -> float:
	return 6.0 * sin((z + 20.0) * 0.018) + 2.5 * sin(z * 0.045)


## Высота дорожного полотна: пологий подъём к горизонту и лёгкие волны.
static func road_y(z: float) -> float:
	return 0.9 * sin((z + 30.0) * 0.025) + 0.5 * sin(z * 0.06) + (80.0 - z) * 0.010


static func yard_height() -> float:
	return road_y(98.0) + 0.10


## 1 внутри площадки базы, 0 снаружи, плавный переход по краям.
static func yard_mask(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - YARD_CENTER.x) - YARD_HALF.x, 0.0)
	var dz: float = maxf(absf(z - YARD_CENTER.y) - YARD_HALF.y, 0.0)
	var distance: float = sqrt(dx * dx + dz * dz)
	return 1.0 - smoothstep(0.0, YARD_FEATHER, distance)


## Высота земли в мировых координатах.
static func terrain_height(x: float, z: float) -> float:
	var ry: float = road_y(z)
	var rx: float = road_x(z)
	var d: float = absf(x - rx)

	var n1: float = _get_base_noise().get_noise_2d(x, z)
	var n2: float = _get_base_noise().get_noise_2d(x * 0.32 + 140.0, z * 0.32 - 70.0)
	# Два шума для дальних гряд холмов: средний и крупный.
	var n3: float = _get_base_noise().get_noise_2d(x * 1.7 + 610.0, z * 1.7 - 320.0)
	var n4: float = _get_base_noise().get_noise_2d(x * 0.45 - 90.0, z * 0.45 + 210.0)

	# У дороги плоско, дальше — насыпи и пологие холмы.
	var bank: float = smoothstep(5.0, 32.0, d)
	var rise: float = 2.4 + 7.5 * (n1 * 0.5 + 0.5) + 7.0 * maxf(n2, 0.0)
	var far_hills: float = smoothstep(50.0, 230.0, d) * (5.0 + 11.0 * (n3 * 0.5 + 0.5) + 7.0 * maxf(n4, 0.0))
	var natural: float = ry + bank * rise + far_hills

	var micro: float = _get_micro_noise().get_noise_2d(x, z)
	natural += micro * 0.18 * smoothstep(5.0, 12.0, d)

	var ym: float = yard_mask(x, z)
	return lerpf(natural, yard_height(), ym)


## Нормаль рельефа — пригодится для посадки объектов.
static func terrain_normal(x: float, z: float) -> Vector3:
	var e: float = 1.0
	var hx: float = terrain_height(x + e, z) - terrain_height(x - e, z)
	var hz: float = terrain_height(x, z + e) - terrain_height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


static func foliage_color(rng: RandomNumberGenerator) -> Color:
	var palette := [
		Color(0.42, 0.52, 0.20),
		Color(0.36, 0.48, 0.18),
		Color(0.50, 0.55, 0.22),
		Color(0.30, 0.43, 0.16),
		Color(0.55, 0.56, 0.26),
	]
	return palette[rng.randi_range(0, palette.size() - 1)]
