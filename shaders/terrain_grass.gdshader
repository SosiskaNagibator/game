shader_type spatial;
// Трава/земля для процедурного рельефа.
// Цвет берётся из вершинных цветов (трава, сухие пятна, придорожная грязь),
// шейдер добавляет мелкую фактуру и налёт на склонах.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 dry_tint : source_color = vec3(0.78, 0.68, 0.38);
uniform vec3 rock_tint : source_color = vec3(0.47, 0.43, 0.35);
uniform float detail_strength : hint_range(0.0, 1.0) = 0.22;
uniform float slope_rock : hint_range(0.0, 1.0) = 0.55;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_color = COLOR.rgb;
}

void fragment() {
	vec3 base = vertex_color;

	// Крупные пятна выгоревшей травы.
	float patches = fbm(world_pos.xz * 0.045);
	float dry = smoothstep(0.48, 0.82, patches);
	base = mix(base, base * dry_tint * 1.35, dry * 0.30);

	// Мелкая фактура: травинки, камешки.
	float fine = noise2(world_pos.xz * 2.2) * 0.55 + noise2(world_pos.xz * 7.3) * 0.45;
	base *= 1.0 - detail_strength * 0.5 + detail_strength * fine;

	// Склоны — земля и камень.
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(0.18, 0.55, slope) * slope_rock;
	base = mix(base, rock_tint, rock * 0.7);

	// Чуть больше зелени в низинах.
	float lush = smoothstep(0.6, 0.2, world_pos.y * 0.02 + fbm(world_pos.xz * 0.02));
	base = mix(base, vec3(0.23, 0.36, 0.12), lush * 0.06);

	ALBEDO = base;
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
}
