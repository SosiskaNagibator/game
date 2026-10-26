shader_type spatial;
// Кустик травы: несколько процедурных травинок на одном кваде.
// Ветер качает верхушку, у основания цвет темнее.

render_mode cull_disabled, shadows_disabled, diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.20, 0.33, 0.10);
uniform vec3 tip_color : source_color = vec3(0.56, 0.66, 0.26);
uniform vec3 dry_color : source_color = vec3(0.60, 0.57, 0.30);
uniform vec3 flower_color : source_color = vec3(0.94, 0.83, 0.35);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.16;
uniform float blade_sharpness : hint_range(0.5, 8.0) = 2.2;

varying float blade_height;
varying vec2 blade_uv;
// INSTANCE_CUSTOM доступен только в vertex() — передаём данные в фрагмент.
varying vec2 inst_data;
varying float flower;

float hash12(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	inst_data = INSTANCE_CUSTOM.rg;
	flower = step(0.94, hash12(floor(INSTANCE_CUSTOM.rg * 7.0 + 3.0)));
	float h = UV.y;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float sway = sin(TIME * 1.35 + phase) * 0.85 + sin(TIME * 2.6 + phase * 1.7) * 0.15;
	float gust = 0.55 + 0.45 * sin(TIME * 0.35 + phase * 0.4);
	VERTEX.x += sway * wind_strength * gust * h * h;
	VERTEX.z += cos(TIME * 1.1 + phase) * wind_strength * 0.25 * h * h;

	blade_height = h;
	blade_uv = UV;
}

void fragment() {
	vec2 uv = blade_uv;
	float h = blade_height;

	// Три травинки в пучке: у каждой свой наклон и сужение.
	float mask = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float center = 0.18 + fi * 0.32;
		float lean = sin(h * 2.6 + fi * 1.9) * 0.075;
		float half_width = 0.052 * (1.0 - h * 0.88);
		float d = abs(uv.x - center - lean * h);
		float blade = 1.0 - smoothstep(half_width * 0.45, half_width, d);
		blade *= smoothstep(1.0, 0.9, h);
		mask = max(mask, blade);
	}
	// Одиночный колосок-цветок сверху у некоторых кустов.
	float seed_head = smoothstep(0.10, 0.03, abs(uv.x - 0.82 - sin(h * 3.0) * 0.03)) * smoothstep(0.72, 0.80, h);

	float alpha = max(mask, seed_head * flower);
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.45;

	vec3 col = mix(base_color, tip_color, smoothstep(0.05, 0.95, h));
	col = mix(col, dry_color, inst_data.g * 0.32);
	col = mix(col, flower_color, seed_head * flower);

	// Задние грани не должны быть чёрными.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
	AO = mix(0.35, 1.0, h);
	BACKLIGHT = col * 0.35;
}
