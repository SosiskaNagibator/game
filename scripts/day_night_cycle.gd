extends Node3D
## Цикл дня и ночи для деревенской сцены.
##
## Что умеет:
##  * плавные рассветы и закаты: у горизонта свет становится тёплым,
##    в сумерках небо окрашивается в оранжево-фиолетовые тона;
##  * отдельные цвета неба, тумана и заполняющего света для дня и ночи;
##  * солнце и луна ходят по орбите, луна даёт холодный голубой свет;
##  * звёздное небо плавно проявляется ночью и медленно вращается;
##  * облака к ночи темнеют и становятся почти прозрачными;
##  * часы в правом верхнем углу (день + игровое время + фаза суток);
##  * публичный API is_night()/get_time_of_day() — им пользуются фары машины.
##
## Время: time_scale — сколько игровых минут проходит за одну реальную
## секунду. При time_scale = 60 полные сутки длятся 24 реальные минуты.

@export_group("Ссылки на ноды")
@export var world_env: WorldEnvironment
@export var player_or_camera: Node3D

@export_group("Настройки времени")
## Сколько игровых минут проходит за одну реальную секунду.
@export var time_scale: float = 60.0
## Игровое время старта в часах (0–24).
@export var start_time: float = 12.0
## Идёт ли время. Можно выключить, чтобы остановить сутки.
@export var time_flow: bool = true
@export var max_fps: int = 60
@export var vsync_enabled: bool = true
## Показывать часы в правом верхнем углу.
@export var show_clock: bool = true

@export_group("Визуал светил")
@export var sun_color: Color = Color(1.0, 0.96, 0.86)
@export var sunset_sun_color: Color = Color(1.0, 0.56, 0.28)
@export var moon_color: Color = Color(0.82, 0.88, 1.0)
@export var sun_size: float = 150.0
@export var moon_size: float = 100.0
@export var orbit_distance: float = 3000.0
@export var orbit_tilt: float = 30.0

@export_group("Освещение")
@export var max_sun_energy: float = 1.5
@export var max_moon_energy: float = 0.16
## Минимальная яркость ночного заполняющего света: ночь должна быть
## тёмной, но не чёрной, иначе на дороге ничего не видно.
@export var night_ambient_energy: float = 0.28
## Дальность теней солнца. 110 м хватает, чтобы тени читались вокруг машины,
## а shadow pass дешевеет в разы по сравнению с 300 м.
@export var shadow_distance: float = 110.0
@export var shadows_enabled: bool = true
## Как часто пересчитывать небо/свет/туман, Гц. Каждый кадр это не нужно:
## изменение освещения за 0.1 с незаметно, а цена — заметная.
@export var environment_update_hz: float = 10.0

@export_group("Цвета неба")
@export var day_sky_top: Color = Color(0.20, 0.40, 0.80)
@export var day_sky_horizon: Color = Color(0.70, 0.80, 0.90)
@export var night_sky_top: Color = Color(0.012, 0.018, 0.05)
@export var night_sky_horizon: Color = Color(0.035, 0.05, 0.11)
@export var dusk_sky_top: Color = Color(0.24, 0.19, 0.42)
@export var dusk_sky_horizon: Color = Color(0.92, 0.48, 0.24)

@export_group("Туман")
@export var day_fog_color: Color = Color(0.74, 0.80, 0.86)
@export var night_fog_color: Color = Color(0.045, 0.06, 0.12)
@export var day_fog_density: float = 0.0005
@export var night_fog_density: float = 0.0012

@export_group("Облака")
@export var cloud_radius: float = 2500.0
@export var cloud_opacity_day: float = 0.55
@export var cloud_color: Color = Color(1.0, 1.0, 1.0)
@export var cloud_noise_scale: float = 3.5
@export var cloud_scroll_speed: float = 0.02
@export var cloud_segments: int = 24
@export var cloud_rings: int = 12

@export_group("Glow (свечение)")
## Glow — дорогой полноэкранный blur; на слабых устройствах лучше держать выключенным.
@export var glow_enabled: bool = false
@export_range(1, 7, 1) var glow_level_count: int = 2

# --- Внутреннее состояние ---------------------------------------------------
var current_time: float = 0.0
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var sun_mesh: MeshInstance3D
var moon_mesh: MeshInstance3D
var star_mesh: MultiMeshInstance3D
var star_mesh_bright: MultiMeshInstance3D
var cloud_mesh: MeshInstance3D
var sky_material: ProceduralSkyMaterial
var cloud_mat: ShaderMaterial
var cloud_time: float = 0.0

## Синус высоты солнца: 1 — зенит, 0 — горизонт, -1 — глубокая ночь.
var _sun_altitude: float = 1.0
var _day_count: int = 1
var _clock_label: Label = null
var _last_clock_text: String = ""
var _star_material_dim: StandardMaterial3D
var _star_material_bright: StandardMaterial3D
## Накопитель времени для троттлинга визуальных обновлений.
var _visual_timer: float = 0.0


# ==============================================================================
# ШЕЙДЕР ОБЛАКОВ
# ==============================================================================
var cloud_shader_code = """
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_never, fog_disabled;

uniform vec4 cloud_color : source_color = vec4(1.0);
uniform float cloud_opacity = 0.0;
uniform float time = 0.0;
uniform float noise_scale = 3.5;

varying vec3 local_pos;

float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
                   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    vec3 p = normalize(local_pos);
    p.x += time * 0.02;
    p.z += time * 0.01;

    float n = noise3d(p * noise_scale) * 0.65
            + noise3d(p * noise_scale * 2.5) * 0.35;

    float cloud = smoothstep(0.42, 0.68, n);

    float up = clamp(p.y, 0.0, 1.0);
    cloud *= smoothstep(0.0, 0.3, up);

    ALBEDO = cloud_color.rgb;
    ALPHA = cloud * cloud_opacity;
}
"""


func _ready() -> void:
	add_to_group("day_night")
	Engine.max_fps = max_fps
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	current_time = fposmod(start_time, 24.0)
	_sun_altitude = sin((current_time / 24.0) * TAU - (PI / 2.0))

	if world_env == null or world_env.environment == null:
		push_error("DayNightCycle: не назначен WorldEnvironment.")
		return

	_create_lights()
	_create_sun_and_moon()
	_create_starfield()
	_create_clouds()
	_setup_environment()
	_setup_clock()
	_update_cycle(0.0)


func _create_lights() -> void:
	# --- Солнце ---
	# В сцене уже есть DirectionalLight3D "Sun" (его настраивает RuralBase).
	# Переиспользуем его: второй shadow-casting directional light — это второй
	# полный проход теней каждый кадр.
	var existing := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if existing != null:
		sun_light = existing
	else:
		sun_light = DirectionalLight3D.new()
		sun_light.name = "SunLight"
		add_child(sun_light)

	sun_light.shadow_enabled = shadows_enabled
	sun_light.directional_shadow_max_distance = shadow_distance
	# 2 каскада вместо 4 — вдвое меньше shadow-рендеров.
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun_light.directional_shadow_split_1 = 0.18
	sun_light.directional_shadow_blend_splits = false
	# Жёсткие тени: отключаем дорогое PCSS-размытие.
	sun_light.light_angular_distance = 0.0
	sun_light.shadow_bias = 0.06
	sun_light.shadow_normal_bias = 1.1

	# --- Луна ---
	# Луна даёт только мягкий заполняющий свет — тени от неё не нужны.
	moon_light = DirectionalLight3D.new()
	moon_light.name = "MoonLight"
	moon_light.shadow_enabled = false
	moon_light.directional_shadow_max_distance = shadow_distance
	moon_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon_light.light_angular_distance = 0.0
	moon_light.shadow_bias = 0.06
	moon_light.shadow_normal_bias = 1.4
	moon_light.light_color = moon_color
	moon_light.light_energy = 0.0
	add_child(moon_light)


func _create_sun_and_moon() -> void:
	sun_mesh = _create_3d_sphere(sun_color, sun_size)
	sun_mesh.name = "SunDisk"
	add_child(sun_mesh)

	moon_mesh = _create_3d_sphere(moon_color, moon_size)
	moon_mesh.name = "MoonDisk"
	add_child(moon_mesh)


func _create_3d_sphere(col: Color, size: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 32
	sphere.rings = 16
	sphere.radius = 1.0
	sphere.height = 2.0
	mesh_inst.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.8
	# Небо далеко, туман не должен съедать диск солнца/луны.
	mat.disable_fog = true

	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.scale = Vector3(size, size, size)
	return mesh_inst


func _create_starfield() -> void:
	_star_material_dim = _make_star_material(0.55)
	_star_material_bright = _make_star_material(1.0)
	star_mesh = _build_star_layer("Stars", 1500, 3.2, _star_material_dim)
	star_mesh_bright = _build_star_layer("StarsBright", 320, 5.4, _star_material_bright)


func _make_star_material(brightness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 1.0, 1.0) * brightness
	# Звёзды на 7000 м: без отключения тумана ночью их не видно.
	mat.disable_fog = true
	return mat


func _build_star_layer(
	node_name: String, count: int, size: float, material: StandardMaterial3D
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = count

	var star_quad := QuadMesh.new()
	star_quad.size = Vector2(size, size)
	star_quad.material = material
	multimesh.mesh = star_quad

	var radius := 7000.0
	for i in count:
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.02, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, dir * radius))

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 200.0
	instance.visible = false
	add_child(instance)
	return instance


func _create_clouds() -> void:
	cloud_mesh = MeshInstance3D.new()
	cloud_mesh.name = "Clouds"
	var sphere := SphereMesh.new()
	sphere.radius = cloud_radius
	sphere.height = cloud_radius * 2.0
	sphere.radial_segments = cloud_segments
	sphere.rings = cloud_rings
	cloud_mesh.mesh = sphere

	cloud_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = cloud_shader_code
	cloud_mat.shader = shader
	cloud_mat.set_shader_parameter("cloud_color", cloud_color)
	cloud_mat.set_shader_parameter("cloud_opacity", 0.0)
	cloud_mat.set_shader_parameter("noise_scale", cloud_noise_scale)
	cloud_mat.set_shader_parameter("time", 0.0)

	cloud_mesh.material_override = cloud_mat
	cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_mesh.extra_cull_margin = 100.0
	cloud_mesh.visible = false
	add_child(cloud_mesh)


func _setup_environment() -> void:
	var env := world_env.environment
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 16.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky

	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.0
	# Дешёвый тонмаппинг и никаких дорогих экранных эффектов.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = glow_enabled
	if glow_enabled:
		env.glow_enabled = true
		env.glow_intensity = 0.7
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.0
		for i in range(7):
			env.set_glow_level(i, 0.0)
		for i in range(glow_level_count):
			env.set_glow_level(i, 1.0)


# --- Часы ---------------------------------------------------------------


func _setup_clock() -> void:
	if not show_clock:
		return

	var layer := CanvasLayer.new()
	layer.name = "DayNightClockLayer"
	add_child(layer)

	_clock_label = Label.new()
	_clock_label.name = "Clock"
	_clock_label.anchor_left = 1.0
	_clock_label.anchor_top = 0.0
	_clock_label.anchor_right = 1.0
	_clock_label.anchor_bottom = 0.0
	_clock_label.offset_left = -300.0
	_clock_label.offset_top = 16.0
	_clock_label.offset_right = -24.0
	_clock_label.offset_bottom = 78.0
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.add_theme_font_size_override("font_size", 24)
	_clock_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88, 0.95))
	_clock_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	_clock_label.add_theme_constant_override("outline_size", 6)
	_clock_label.text = get_clock_text()
	layer.add_child(_clock_label)
	_last_clock_text = _clock_label.text


func _update_clock() -> void:
	if _clock_label == null:
		return
	var text := get_clock_text()
	if text != _last_clock_text:
		_last_clock_text = text
		_clock_label.text = text


# --- Основной цикл ------------------------------------------------------


func _process(delta: float) -> void:
	if time_flow:
		current_time += delta * (time_scale / 60.0)
		while current_time >= 24.0:
			current_time -= 24.0
			_day_count += 1
		while current_time < 0.0:
			current_time += 24.0

	cloud_time += delta * cloud_scroll_speed
	# Небо, туман, звёзды и облака меняются медленно: пересчитываем их
	# 10 раз в секунду вместо каждого кадра и экономим CPU/обновления ресурсов.
	_visual_timer += delta
	var interval: float = 1.0 / maxf(environment_update_hz, 1.0)
	if _visual_timer < interval:
		return
	var step := _visual_timer
	_visual_timer = 0.0
	_update_cycle(step)
	_update_clock()


func _update_cycle(delta: float) -> void:
	if world_env == null or world_env.environment == null or sun_light == null:
		return
	var env := world_env.environment

	var angle := (current_time / 24.0) * TAU - (PI / 2.0)
	var tilt := deg_to_rad(orbit_tilt)
	_sun_altitude = sin(angle)

	var sun_dir := Vector3(
		cos(angle),
		sin(angle) * cos(tilt),
		sin(angle) * sin(tilt)
	)
	var center := _focus_position()

	var sun_pos := center + sun_dir * orbit_distance
	var moon_pos := center - sun_dir * orbit_distance

	if sun_mesh != null:
		sun_mesh.global_position = sun_pos
		sun_mesh.visible = _sun_altitude > -0.12
	if sun_light != null:
		sun_light.global_position = sun_pos
		if sun_pos.distance_to(center) > 0.5:
			sun_light.look_at(center, Vector3.UP)
		sun_light.visible = _sun_altitude > -0.07

	if moon_mesh != null:
		moon_mesh.global_position = moon_pos
		moon_mesh.visible = _sun_altitude < 0.12
	if moon_light != null:
		moon_light.global_position = moon_pos
		if moon_pos.distance_to(center) > 0.5:
			moon_light.look_at(center, Vector3.UP)
		moon_light.visible = _sun_altitude < 0.07

	# Плавный день: 0 — глубокая ночь, 1 — полный день.
	var day_level := smoothstep(-0.06, 0.28, _sun_altitude)
	# Сумерки горят ярче всего у горизонта (и на рассвете, и на закате).
	var twilight := clampf(1.0 - absf(_sun_altitude) / 0.30, 0.0, 1.0)
	twilight = pow(twilight, 1.35)

	# --- Светила ---
	sun_light.light_energy = max_sun_energy * smoothstep(-0.03, 0.22, _sun_altitude)
	sun_light.light_color = sun_color.lerp(sunset_sun_color, clampf(twilight * 1.1, 0.0, 1.0))
	moon_light.light_energy = max_moon_energy * (1.0 - day_level)
	moon_light.light_color = moon_color

	# --- Заполняющий свет: ночью чуть голубой, но не чёрный ---
	var ambient_night := Color(0.16, 0.20, 0.34)
	var ambient_day := Color(0.63, 0.59, 0.52)
	env.ambient_light_color = ambient_night.lerp(ambient_day, day_level)
	env.ambient_light_energy = lerpf(night_ambient_energy, 1.0, day_level)
	env.background_energy_multiplier = lerpf(0.9, 1.0, day_level)

	# --- Небо ---
	if sky_material != null:
		var top := night_sky_top.lerp(day_sky_top, day_level)
		top = top.lerp(dusk_sky_top, twilight * 0.75)
		var horizon := night_sky_horizon.lerp(day_sky_horizon, day_level)
		horizon = horizon.lerp(dusk_sky_horizon, twilight * 0.9)
		sky_material.sky_top_color = top
		sky_material.sky_horizon_color = horizon
		sky_material.ground_horizon_color = horizon.darkened(0.3)
		sky_material.ground_bottom_color = night_sky_top.darkened(0.5)

	# --- Туман ---
	if env.fog_enabled:
		var fog_col := night_fog_color.lerp(day_fog_color, day_level)
		fog_col = fog_col.lerp(dusk_sky_horizon, twilight * 0.35)
		env.fog_light_color = fog_col
		env.fog_density = lerpf(night_fog_density, day_fog_density, day_level)
		env.fog_light_energy = lerpf(0.6, 0.9, day_level)

	_update_stars(day_level, delta)
	_update_clouds(day_level, twilight, center)

	if star_mesh != null:
		star_mesh.global_position = center
	if star_mesh_bright != null:
		star_mesh_bright.global_position = center


func _update_stars(day_level: float, delta: float) -> void:
	var visibility := clampf(1.0 - day_level * 2.2, 0.0, 1.0)
	if star_mesh != null:
		star_mesh.visible = visibility > 0.02
		star_mesh.rotation.y += delta * 0.004
	if star_mesh_bright != null:
		star_mesh_bright.visible = visibility > 0.02
		star_mesh_bright.rotation.y += delta * 0.004

	var now := Time.get_ticks_msec() * 0.001
	var twinkle := 0.85 + 0.15 * sin(now * 1.6)
	var sparkle := 0.62 + 0.38 * sin(now * 2.7 + 1.3)
	if _star_material_dim != null:
		_star_material_dim.albedo_color = Color(0.75, 0.80, 0.95) * (visibility * twinkle)
	if _star_material_bright != null:
		_star_material_bright.albedo_color = Color(1.0, 0.97, 0.9) * (visibility * sparkle)


func _update_clouds(day_level: float, twilight: float, center: Vector3) -> void:
	if cloud_mat == null or cloud_mesh == null:
		return
	cloud_mesh.global_position = center
	var opacity := lerpf(0.10, cloud_opacity_day, day_level) * (1.0 - twilight * 0.35)
	cloud_mat.set_shader_parameter("cloud_opacity", opacity)
	cloud_mat.set_shader_parameter("time", cloud_time)

	var tint := cloud_color.lerp(Color(0.70, 0.78, 1.0), 1.0 - day_level)
	tint = tint.lerp(dusk_sky_horizon, twilight * 0.55)
	tint *= lerpf(0.35, 1.0, day_level)
	cloud_mat.set_shader_parameter("cloud_color", tint)
	cloud_mesh.visible = opacity > 0.01


func _focus_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	if player_or_camera != null:
		return player_or_camera.global_position
	return global_position


# --- Публичный API ------------------------------------------------------


## Ночь ли сейчас (солнце ниже горизонта). Фары и фонари используют это.
func is_night() -> bool:
	return _sun_altitude < 0.06


## Текущее игровое время в часах (0–24).
func get_time_of_day() -> float:
	return current_time


## Перевести часы, не меняя счётчик дней.
func set_time_of_day(hours: float) -> void:
	current_time = fposmod(hours, 24.0)


## Текст для часов в HUD.
func get_clock_text() -> String:
	var total_minutes := int(floor(current_time * 60.0))
	var hours := int(total_minutes / 60.0) % 24
	var minutes := total_minutes % 60
	var phase := "ДЕНЬ"
	if _sun_altitude < 0.02:
		phase = "НОЧЬ"
	elif _sun_altitude < 0.18:
		phase = "СУМЕРКИ"
	return "День %d   %02d:%02d   %s" % [_day_count, hours, minutes, phase]

