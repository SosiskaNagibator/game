shader_type spatial;
// Трава/земля для процедурного рельефа.
// Цвет берётся из вершинных цветов (трава, сухие пятна, придорожная грязь),
// шейдер добавляет мелкую фактуру, неровности и налёт на склонах.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 dry_tint : source_color = vec3(0.58, 0.52, 0.30);
uniform vec3 rock_tint : source_color = vec3(0.38, 0.35, 0.28);
uniform vec3 soil_tint : source_color = vec3(0.23, 0.18, 0.12);
uniform float detail_strength : hint_range(0.0, 1.5) = 0.55;
uniform float soil_strength : hint_range(0.0, 1.0) = 0.28;
uniform float slope_rock : hint_range(0.0, 1.0) = 0.5;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.65;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 vertex_color;

float hash12(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += noise2(p) * amp;
		p = p * 2.07 + vec2(13.7, 7.1);
		amp *= 0.5;
	}
	return v;
}

// Невысокий микрорельеф: трава, кочки, рыхлая земля.
float ground_height(vec2 p) {
	float h = noise2(p * 2.1) * 0.050;
	h += noise2(p * 6.4 + 17.0) * 0.020;
	h += noise2(p * 15.0 + 43.0) * 0.008;
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_color = COLOR.rgb;
}

void fragment() {
	vec2 wxz = world_pos.xz;

	// Размер пикселя в метрах: мелкую фактуру гасим вдали,
	// чтобы не было мерцания и «шума».
	float pixel = length(fwidth(wxz));
	float near_fade = 1.0 - smoothstep(0.10, 0.75, pixel);
	float micro_fade = 1.0 - smoothstep(0.035, 0.22, pixel);

	vec3 base = vertex_color;

	// Крупные пятна выгоревшей травы.
	float patches = fbm(wxz * 0.035);
	base = mix(base, base * dry_tint * 1.12, smoothstep(0.42, 0.78, patches) * 0.30);

	// Проплешины земли: не дают полю выглядеть однотонной заливкой.
	float soil = smoothstep(0.52, 0.80, fbm(wxz * 0.19 + vec2(31.0, 7.0)));
	base = mix(base, soil_tint, soil * soil_strength);

	// Кочек и пучков травы: несколько масштабов, чтобы фактура читалась
	// и вблизи, и на среднем плане.
	float clumps = fbm(wxz * 0.42);
	float clumps2 = fbm(wxz * 1.35 + vec2(11.0, 5.0));
	float grain = noise2(wxz * 6.5) * 0.55 + hash12(floor(wxz * 23.0)) * 0.45;

	base *= 0.78 + 0.34 * clumps;
	base = mix(base, base * vec3(0.82, 0.88, 0.70), clumps2 * 0.24);
	base *= 1.0 + detail_strength * (grain - 0.5) * 1.1 * near_fade;

	// Редкие сухие соломинки — тонкие штрихи, без «диагонального смаза».
	float straw = smoothstep(0.88, 0.99, noise2(wxz * vec2(34.0, 6.0) + 5.0));
	base = mix(base, dry_tint * 1.05, straw * 0.22 * near_fade);

	// Мелкая земляная крошка между травинками.
	float fleck = smoothstep(0.84, 0.98, hash12(floor(wxz * 47.0) + 7.0));
	base = mix(base, soil_tint * 1.3, fleck * 0.28 * micro_fade);

	// Склоны — земля и камень.
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(0.18, 0.55, slope) * slope_rock;
	base = mix(base, rock_tint, rock * 0.65);

	// Чуть больше зелени в низинах.
	float lush = smoothstep(0.6, 0.2, world_pos.y * 0.02 + fbm(wxz * 0.02));
	base = mix(base, vec3(0.17, 0.28, 0.09), lush * 0.07);

	// Нормали: лёгкие неровности поверхности, чтобы свет лепил траву.
	float hgt = ground_height(wxz);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-6) {
		vec3 grad = (r1 * dFdx(hgt) + r2 * dFdy(hgt)) / det;
		NORMAL = normalize(NORMAL - bump_strength * near_fade * grad);
	}

	ALBEDO = base;
	AO = mix(0.80, 1.0, clamp(clumps * 0.5 + clumps2 * 0.5, 0.0, 1.0));
	ROUGHNESS = 0.93;
	SPECULAR = 0.05;
}
