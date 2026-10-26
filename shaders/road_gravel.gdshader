shader_type spatial;
// Просёлочная гравийная дорога: колеи, камешки, пыльные края.
// Шум строится в мировых координатах с поворотом домена на каждой октаве,
// поэтому на поверхности нет видимых квадратных ячеек и швов.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 gravel_light : source_color = vec3(0.56, 0.50, 0.40);
uniform vec3 gravel_dark : source_color = vec3(0.38, 0.33, 0.26);
uniform vec3 track_color : source_color = vec3(0.50, 0.44, 0.34);
uniform vec3 edge_color : source_color = vec3(0.41, 0.36, 0.27);
uniform float track_offset : hint_range(0.15, 0.45) = 0.31;
uniform float pebble_amount : hint_range(0.0, 1.0) = 0.35;
uniform float track_strength : hint_range(0.0, 1.0) = 1.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;
varying vec2 road_uv;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Гладкий value-noise с квинтической интерполяцией.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// FBM с поворотом координат между октавами — убирает осевую сетку.
float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 5; i++) {
		sum += value_noise(p) * amp;
		p = rot * p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return sum;
}

// F1-расстояние до ближайшей точки ячейки: гравийные камешки.
float worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			vec2 r = g + o - f;
			d = min(d, dot(r, r));
		}
	}
	return sqrt(d);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	road_uv = UV;
}

void fragment() {
	float u = road_uv.x;
	float edge = abs(u * 2.0 - 1.0);
	vec2 p = world_pos.xz;

	// Размер пикселя в мировых единицах — плавно гасим слишком мелкие детали.
	float footprint = length(fwidth(p));
	float fine_fade = 1.0 - smoothstep(0.10, 0.45, footprint);
	float grain_fade = 1.0 - smoothstep(0.025, 0.12, footprint);

	// Крупные пятна, средний рисунок и мелкая фактура.
	float macro = fbm(p * 0.22 + vec2(3.7, -8.2));
	float mid = fbm(p * 1.15 + vec2(-5.1, 2.4));
	float fine = fbm(p * 5.4 + vec2(11.0, 7.0));
	float grain = value_noise(p * 31.0);

	float tonal = macro * 0.52 + mid * 0.30 + fine * 0.13 * fine_fade;
	vec3 col = mix(gravel_dark, gravel_light, smoothstep(0.18, 0.86, tonal));

	// Пыльные/осветлённые разводы, не привязанные к геометрии.
	float dust = smoothstep(0.55, 0.82, fbm(p * 0.65 + vec2(21.0, -4.0)));
	col = mix(col, gravel_light * 1.05, dust * 0.22);
	col *= 0.94 + grain * 0.12 * grain_fade;

	// Гравий: светлые камешки и тёмные промежутки между ними.
	float cell = worley(p * 12.0);
	float stone = smoothstep(0.32, 0.05, cell);
	float stone_mask = smoothstep(0.36, 0.70, fbm(p * 3.2 + vec2(-9.0, 5.0)));
	col = mix(col, gravel_light * 1.16, stone * stone_mask * pebble_amount * fine_fade * 0.85);
	float gaps = smoothstep(0.10, 0.38, cell) * smoothstep(0.55, 0.9, value_noise(p * 14.0));
	col = mix(col, gravel_dark * 0.84, gaps * 0.18 * fine_fade);

	// Две накатанные колеи с лёгким искривлением вдоль дороги.
	float along = road_uv.y * 7.0;
	float wobble = (value_noise(vec2(along, 3.1)) - 0.5) * 0.035;
	float track_w = 0.075 + footprint * 1.6;
	float du_l = abs(u - (0.5 - track_offset) + wobble);
	float du_r = abs(u - (0.5 + track_offset) + wobble);
	float tracks = smoothstep(track_w + 0.045, track_w * 0.45, du_l);
	tracks += smoothstep(track_w + 0.045, track_w * 0.45, du_r);
	tracks = clamp(tracks, 0.0, 1.0);
	// В колее гравий утрамбован, цвет ровнее и темнее.
	col = mix(col, track_color, tracks * 0.46 * track_strength);

	// Пыльный гребень по центру.
	float crown = smoothstep(0.34, 0.0, abs(u - 0.5));
	col = mix(col, gravel_light * 1.07, crown * 0.16);

	// Плавный переход к обочине с неровной границей.
	float edge_n = edge + (value_noise(vec2(p.y * 1.7, p.x * 1.7)) - 0.5) * 0.05;
	float shoulder = smoothstep(0.74, 0.995, edge_n);
	col = mix(col, edge_color, shoulder * 0.82 * edge_strength);

	// Мелкая пыль на обочине.
	col *= 1.0 - shoulder * 0.06 * grain;

	ALBEDO = col;
	// Накатанные колеи чуть глянцевее утрамбованы, камешки — шершавее.
	float rough = mix(0.95, 0.86, tracks * track_strength);
	rough = mix(rough, 0.78, stone * stone_mask * pebble_amount * fine_fade * 0.7);
	rough = mix(rough, 0.97, shoulder);
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	SPECULAR = 0.13;
}
