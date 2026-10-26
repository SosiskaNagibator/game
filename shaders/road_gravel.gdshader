shader_type spatial;
// Просёлочная гравийная дорога: колеи, камешки, пыльные края.

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	road_uv = UV;
}

void fragment() {
	float u = road_uv.x;
	float edge = abs(u * 2.0 - 1.0);

	float coarse = noise2(world_pos.xz * 0.8);
	float fine = noise2(world_pos.xz * 5.0);
	float tiny = noise2(world_pos.xz * 22.0);

	vec3 col = mix(gravel_dark, gravel_light, coarse * 0.65 + fine * 0.35);
	col *= 0.93 + tiny * 0.14;

	// Крупные пятна утоптанной земли и пыли.
	float worn = noise2(world_pos.xz * 0.17 + vec2(3.1, 7.7));
	col = mix(col, col * vec3(0.80, 0.75, 0.66), smoothstep(0.42, 0.84, worn) * 0.40);

	// Песчано-гравийные камешки.
	float pebble = smoothstep(0.78, 0.94, noise2(world_pos.xz * 13.0));
	col = mix(col, gravel_light * 1.2, pebble * pebble_amount);

	// Отдельные крупные камни и тёмная галька.
	float stone = smoothstep(0.84, 0.97, noise2(world_pos.xz * 4.3 + vec2(9.0, 1.0)));
	col = mix(col, mix(gravel_light * 1.3, gravel_dark * 0.85, fine), stone * 0.45);

	// Две накатанные колеи.
	float tracks = smoothstep(0.10, 0.025, abs(u - (0.5 - track_offset)));
	tracks += smoothstep(0.10, 0.025, abs(u - (0.5 + track_offset)));
	col = mix(col, track_color, clamp(tracks, 0.0, 1.0) * 0.42 * track_strength);

	// Пыльный центр и края.
	float crown = smoothstep(0.32, 0.0, abs(u - 0.5));
	col = mix(col, gravel_light * 1.06, crown * 0.18);
	float shoulder = smoothstep(0.72, 1.0, edge);
	col = mix(col, edge_color, shoulder * 0.80 * edge_strength);

	ALBEDO = col;
	ROUGHNESS = 0.93;
	SPECULAR = 0.14;
}
