shader_type spatial;
// Низкополигональная листва: плоские нормали, лёгкое покачивание,
// оттенок задаётся через INSTANCE_CUSTOM (данные MultiMesh).
// В Godot 4 INSTANCE_CUSTOM доступен только в vertex(), поэтому
// оттенок передаём во фрагментный шейдер через varying.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 shadow_color : source_color = vec3(0.15, 0.28, 0.075);
uniform vec3 light_color : source_color = vec3(0.40, 0.55, 0.16);
uniform float sway_strength : hint_range(0.0, 0.2) = 0.035;

varying vec3 world_pos;
varying vec3 inst_tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	inst_tint = INSTANCE_CUSTOM.rgb;
	float phase = world_pos.x * 0.12 + world_pos.z * 0.09;
	float sway = sin(TIME * 0.85 + phase) * sway_strength;
	// Чем выше крона, тем сильнее качается.
	float height_factor = clamp(world_pos.y * 0.10, 0.0, 1.0);
	VERTEX.x += sway * height_factor;
	VERTEX.z += cos(TIME * 0.63 + phase * 1.4) * sway * 0.6 * height_factor;
}

void fragment() {
	// Плоская грань — инди-стилистика.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (!FRONT_FACING) {
		n = -n;
	}
	NORMAL = n;

	vec3 tint = inst_tint;
	if (dot(tint, tint) < 0.01) {
		tint = vec3(0.7, 0.85, 0.55);
	}

	vec3 col = mix(shadow_color, light_color, tint.g);
	col *= 0.75 + tint.r * 0.55;

	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.08;
}
