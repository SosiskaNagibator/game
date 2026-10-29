@tool
class_name WorldPerformance
extends RefCounted
## Общие настройки производительности для больших уличных сцен.
##
## Скрипт ничего не создаёт: он приводит уже готовые ноды (сгенерированные
## поселение, ферму, рельеф и т.д.) к «дешёвому» виду:
##  * мелкие меши перестают отбрасывать тени и исчезают на расстоянии;
##  * у всех статических мешей отключается GI (SDFGI/светмапы не нужны);
##  * точечные и прожекторные фонари гаснут по дистанции и не тратят
##    shadow-атлас, если это не критично.
##
## Вызывать один раз после того, как сцена сгенерировала детей
## (например, в _ready() корневой сцены).

## Максимальная дальность теней солнца. Меньше — дешевле shadow pass.
const SUN_SHADOW_DISTANCE := 110.0
## Меши меньше этого размера (по самой длинной стороне AABB) не отбрасывают тени.
const SMALL_MESH_SIZE := 1.8
## Дальность видимости мелких деталей (декор, заборы, мелкие части построек).
const SMALL_DETAIL_VISIBILITY := 220.0
## Дальность видимости средних объектов (камни, кусты).
const MEDIUM_DETAIL_VISIBILITY := 320.0

## Ноды, которые нельзя трогать: игрок и машины должны оставаться как есть.
const SKIP_NAMES := ["Player", "BaseVehicle", "ThirdPersonCamera"]
const SKIP_GROUPS := ["player", "vehicles"]


## Применить настройки к Environment: убрать дорогие эффекты.
static func configure_environment(env: Environment) -> void:
	if env == null:
		return
	# SSAO/SSIL/Glow/Volumetric fog — самые дорогие пост-эффекты в Forward+.
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	# Filmic заметно дешевле AgX и не «съедает» контраст.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC


## Настроить DirectionalLight3D (солнце) на дешёвые тени.
static func configure_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.shadow_enabled = true
	# 2 PSSM-каскада вместо 4: вдвое меньше рендеров карты теней.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_blend_splits = false
	# Жёсткие тени без PCSS: убирает дорогой фильтр мягких теней.
	sun.light_angular_distance = 0.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.1


## Пройти по дереву сцены и применить дешёвые настройки ко всем мешам/светам.
static func optimize_world(root: Node) -> void:
	if root == null:
		return
	_optimize_node(root)


static func _optimize_node(node: Node) -> void:
	if node is Node3D:
		var node3d := node as Node3D
		if SKIP_NAMES.has(String(node3d.name)):
			return
		for group in SKIP_GROUPS:
			if node3d.is_in_group(group):
				return
		if node3d.has_meta("skip_performance"):
			return

	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null:
		_optimize_mesh_instance(mesh_instance)

	var multi_mesh := node as MultiMeshInstance3D
	if multi_mesh != null:
		multi_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var light := node as Light3D
	if light != null and not (light is DirectionalLight3D):
		_optimize_light(light)

	for child in node.get_children():
		_optimize_node(child)


static func _optimize_mesh_instance(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	# GI для статики бесполезен без запечённых светмап и только ест память.
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if mesh_instance.has_meta("always_shadow"):
		return

	var aabb: AABB = mesh_instance.mesh.get_aabb()
	var size: Vector3 = aabb.size * mesh_instance.global_transform.basis.get_scale()
	var longest: float = maxf(size.x, maxf(size.y, size.z))

	if longest < SMALL_MESH_SIZE:
		# Мелкие детали (планки, горшки, ящики) не дают заметной тени,
		# но каждый такой меш — отдельный draw call в shadow pass.
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_apply_visibility(mesh_instance, SMALL_DETAIL_VISIBILITY)
	elif longest < SMALL_MESH_SIZE * 2.5:
		_apply_visibility(mesh_instance, MEDIUM_DETAIL_VISIBILITY)


static func _apply_visibility(
	mesh_instance: MeshInstance3D, distance: float
) -> void:
	# Не перебиваем уже настроенную вручную видимость.
	if mesh_instance.visibility_range_end > 0.0:
		return
	mesh_instance.visibility_range_end = distance
	mesh_instance.visibility_range_end_margin = distance * 0.1
	mesh_instance.visibility_range_fade_mode = (
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	)


static func _optimize_light(light: Light3D) -> void:
	# Фонари далеко от игрока всё равно не видны: гасим их по дистанции.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 55.0
	light.distance_fade_shadow = 35.0
	light.distance_fade_length = 12.0
	# Тени от точечных источников дороги (6 граней cubemap). Для фонарей
	# на столбах/в доках они почти не читаются, поэтому выключаем.
	if light.light_energy < 30.0 and light.shadow_enabled:
		light.shadow_enabled = false
