extends Node3D

# ==============================================================================
# НАСТРОЙКИ
# ==============================================================================
@export_group("Ссылки на ноды")
@export var world_env: WorldEnvironment
@export var player_or_camera: Node3D 

@export_group("Настройки времени")
@export var time_scale: float = 60.0 
@export var start_time: float = 12.0 
@export var max_fps: int = 60
@export var vsync_enabled: bool = true

@export_group("Визуал Светил")
@export var sun_color: Color = Color(1.0, 0.95, 0.8)
@export var moon_color: Color = Color(0.8, 0.9, 1.0)
@export var sun_size: float = 150.0 
@export var moon_size: float = 100.0 
@export var orbit_distance: float = 3000.0 
@export var orbit_tilt: float = 30.0 

@export_group("Освещение")
@export var max_sun_energy: float = 1.5
@export var max_moon_energy: float = 0.08
@export var shadow_distance: float = 300.0 # Увеличил дистанцию теней для больших сцен
@export var shadows_enabled: bool = true

@export_group("Цвета Неба")
@export var day_sky_top: Color = Color(0.2, 0.4, 0.8)
@export var day_sky_horizon: Color = Color(0.7, 0.8, 0.9)
@export var night_sky_top: Color = Color(0.0, 0.0, 0.0)
@export var night_sky_horizon: Color = Color(0.02, 0.02, 0.05)

@export_group("Облака")
@export var cloud_radius: float = 2500.0
@export var cloud_opacity_day: float = 0.55
@export var cloud_color: Color = Color(1.0, 1.0, 1.0)
@export var cloud_noise_scale: float = 3.5
@export var cloud_scroll_speed: float = 0.02
@export var cloud_segments: int = 24
@export var cloud_rings: int = 12

@export_group("Glow (свечение)")
@export var glow_enabled: bool = true
@export_range(1, 7, 1) var glow_level_count: int = 4

# Внутренние переменные
var current_time: float = 0.0
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var sun_mesh: MeshInstance3D
var moon_mesh: MeshInstance3D
var star_mesh: MultiMeshInstance3D
var cloud_mesh: MeshInstance3D
var sky_material: ProceduralSkyMaterial
var cloud_mat: ShaderMaterial
var cloud_time: float = 0.0

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
	Engine.max_fps = max_fps
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	current_time = start_time
	if not world_env:
		printerr("ОШИБКА: Не назначен World_Env!")
		return
		
	# --- СОЛНЕЧНЫЙ СВЕТ ---
	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = shadows_enabled
	sun_light.directional_shadow_max_distance = shadow_distance
	# 4 каскада для более четких теней
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	
	# Делаем тени мягкими (убирает "лесенку" на краях)
	sun_light.light_angular_distance = 0.5 
	# Убираем черные полосы на стволах и листьях
	sun_light.shadow_bias = 0.03
	sun_light.shadow_normal_bias = 1.5
	add_child(sun_light)
	
	# --- ЛУННЫЙ СВЕТ ---
	moon_light = DirectionalLight3D.new()
	moon_light.shadow_enabled = shadows_enabled
	moon_light.directional_shadow_max_distance = shadow_distance
	moon_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon_light.light_angular_distance = 0.5
	moon_light.shadow_bias = 0.03
	moon_light.shadow_normal_bias = 1.5
	add_child(moon_light)
	
	sun_mesh = _create_3d_sphere(sun_color, sun_size)
	moon_mesh = _create_3d_sphere(moon_color, moon_size)
	add_child(sun_mesh)
	add_child(moon_mesh)
	
	_create_starfield()
	_create_clouds()
	_setup_environment()

func _create_3d_sphere(col: Color, size: float) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radial_segments = 32
	sphere.rings = 16
	sphere.radius = 1.0
	sphere.height = 2.0
	mesh_inst.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0

	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.scale = Vector3(size, size, size)
	return mesh_inst

func _create_starfield() -> void:
	star_mesh = MultiMeshInstance3D.new()
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = 1500
	
	var star_quad = QuadMesh.new()
	star_quad.size = Vector2(3, 3)
	multimesh.mesh = star_quad
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1, 1, 1, 1)
	star_quad.material = mat
	
	var radius = 7000.0
	for i in range(multimesh.instance_count):
		var pos = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.05, 1.0),
			randf_range(-1.0, 1.0)
		).normalized() * radius
		
		var t = Transform3D()
		t.origin = pos
		multimesh.set_instance_transform(i, t)
		
	star_mesh.multimesh = multimesh
	add_child(star_mesh)

func _create_clouds() -> void:
	cloud_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = cloud_radius
	sphere.height = cloud_radius * 2.0
	sphere.radial_segments = cloud_segments
	sphere.rings = cloud_rings
	cloud_mesh.mesh = sphere
	
	cloud_mat = ShaderMaterial.new()
	var shader = Shader.new()
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
	var env = world_env.environment
	if not env: return
	
	sky_material = ProceduralSkyMaterial.new()
	var sky = Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	
	if glow_enabled:
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.0 # Убрали блюр (замыливание)
		env.glow_hdr_threshold = 1.0
		
		for i in range(7):
			env.set_glow_level(i, 0.0)
		for i in range(glow_level_count):
			env.set_glow_level(i, 1.0)
	else:
		env.glow_enabled = false

func _process(delta: float) -> void:
	current_time += delta * (time_scale / 60.0)
	if current_time >= 24.0:
		current_time -= 24.0 
	
	cloud_time += delta * cloud_scroll_speed
	_update_cycle()

func _update_cycle() -> void:
	if not world_env or not world_env.environment: return
	var env = world_env.environment

	var angle = (current_time / 24.0) * TAU - (PI / 2.0)
	var tilt_rad = deg_to_rad(orbit_tilt)
	
	var sun_x = cos(angle) * orbit_distance
	var sun_y = sin(angle) * orbit_distance * cos(tilt_rad)
	var sun_z = sin(angle) * orbit_distance * sin(tilt_rad)
	
	var moon_angle = angle + PI
	var moon_x = cos(moon_angle) * orbit_distance
	var moon_y = sin(moon_angle) * orbit_distance * cos(tilt_rad)
	var moon_z = sin(moon_angle) * orbit_distance * sin(tilt_rad)

	var center_pos = Vector3.ZERO
	if player_or_camera:
		center_pos = player_or_camera.global_position
	else:
		var cam = get_viewport().get_camera_3d()
		if cam: center_pos = cam.global_position
		
	if star_mesh:
		star_mesh.global_position = center_pos

	if cloud_mesh:
		cloud_mesh.global_position = center_pos

	if sun_mesh and sun_light:
		sun_mesh.global_position = center_pos + Vector3(sun_x, sun_y, sun_z)
		sun_light.global_position = sun_mesh.global_position
		if sun_light.global_position.distance_to(center_pos) > 0.1:
			sun_light.look_at(center_pos, Vector3.UP)
		var show_sun = sun_y > -0.05 
		sun_mesh.visible = show_sun
		sun_light.visible = show_sun
	
	if moon_mesh and moon_light:
		moon_mesh.global_position = center_pos + Vector3(moon_x, moon_y, moon_z)
		moon_light.global_position = moon_mesh.global_position
		if moon_light.global_position.distance_to(center_pos) > 0.1:
			moon_light.look_at(center_pos, Vector3.UP)
		var show_moon = moon_y > -0.05
		moon_mesh.visible = show_moon
		moon_light.visible = show_moon

	var sun_height = sin(angle)
	var day_amount = clamp(sun_height * 2.0, 0.0, 1.0)
	
	sun_light.light_energy = day_amount * max_sun_energy
	moon_light.light_energy = (1.0 - day_amount) * max_moon_energy
	moon_light.light_color = Color(0.6, 0.7, 1.0)
	
	var light_factor = smoothstep(0.0, 0.6, day_amount)
	
	# Сделали цвет теней чуть светлее и голубее (Color(0.55, 0.55, 0.6)), чтобы не было черноты
	env.ambient_light_color = Color(0.0, 0.0, 0.0).lerp(Color(0.55, 0.55, 0.6), day_amount)
	env.ambient_light_energy = light_factor
	
	if sky_material:
		sky_material.sky_top_color = night_sky_top.lerp(day_sky_top, day_amount)
		sky_material.sky_horizon_color = night_sky_horizon.lerp(day_sky_horizon, day_amount)
		env.background_energy_multiplier = light_factor
	
	if star_mesh:
		var star_vis = clamp(1.0 - day_amount * 3.0, 0.0, 1.0)
		star_mesh.visible = star_vis > 0.05
	
	if cloud_mat and cloud_mesh:
		var cloud_vis = smoothstep(0.15, 0.5, day_amount)
		var final_opacity = cloud_vis * cloud_opacity_day
		if final_opacity > 0.01:
			cloud_mesh.visible = true
			cloud_mat.set_shader_parameter("cloud_opacity", final_opacity)
			cloud_mat.set_shader_parameter("time", cloud_time)
		else:
			cloud_mesh.visible = false
