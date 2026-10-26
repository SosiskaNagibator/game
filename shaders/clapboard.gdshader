shader_type spatial;
// Крашеная деревянная обшивка (сарай): горизонтальные доски, потёртости.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 paint_color : source_color = vec3(0.42, 0.10, 0.08);
uniform vec3 bare_wood : source_color = vec3(0.34, 0.24, 0.15);
uniform float board_frequency = 3.2;
uniform float wear : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

varying vec3 world_pos;
varying vec3 world_normal;

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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float f = fract(world_pos.y * board_frequency);
	float seam = 1.0 - smoothstep(0.0, 0.035, min(f, 1.0 - f));

	float grain = noise2(vec2(world_pos.x * 2.0 + world_pos.z * 2.0, world_pos.y * 19.0));
	float weather = noise2(world_pos.xz * 0.55) * 0.5 + noise2(world_pos.xz * 2.7) * 0.5;

	vec3 col = paint_color * (0.86 + grain * 0.22);
	col *= 1.0 - seam * 0.32;

	float peeled = smoothstep(0.72 - wear * 0.25, 0.85, weather) * wear;
	col = mix(col, bare_wood, peeled * 0.55);

	// Пыль у земли.
	float dust = 1.0 - smoothstep(0.0, 1.8, world_pos.y);
	col = mix(col, bare_wood * 0.9, dust * 0.16);

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.12;
}
