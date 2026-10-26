shader_type spatial;

// Процедурная сетка на земле в мировых координатах.
// Не требует UV-развёртки и не «мылится» на больших плоскостях.

uniform vec3 base_color : source_color = vec3(0.38, 0.40, 0.34);
uniform vec3 cell_color : source_color = vec3(0.44, 0.46, 0.39);
uniform vec3 line_color : source_color = vec3(0.68, 0.71, 0.62);
uniform vec3 major_line_color : source_color = vec3(0.92, 0.94, 0.84);
uniform float cell_size = 1.0;
uniform float major_every = 10.0;
uniform float line_strength = 0.55;
uniform float major_strength = 0.9;
uniform float fade_start = 60.0;
uniform float fade_end = 160.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Мелкая сетка — 1 метр.
	vec2 p = world_pos.xz / cell_size;
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(0.0001));
	float line = 1.0 - min(min(g.x, g.y), 1.0);

	// Крупная сетка — каждые 10 метров.
	vec2 pm = p / major_every;
	vec2 gm = abs(fract(pm - 0.5) - 0.5) / max(fwidth(pm), vec2(0.0001));
	float major = 1.0 - min(min(gm.x, gm.y), 1.0);

	// Лёгкий шахматный оттенок по клеткам — помогает замечать движение.
	float checker = mod(floor(p.x) + floor(p.y), 2.0);
	vec3 color = mix(base_color, cell_color, checker * 0.35);

	// Дальнюю сетку приглушаем, чтобы не было муара.
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	color = mix(color, line_color, line * line_strength * fade);
	color = mix(color, major_line_color, major * major_strength * (0.25 + 0.75 * fade));

	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
