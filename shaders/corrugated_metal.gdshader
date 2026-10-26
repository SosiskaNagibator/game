shader_type spatial;
// Гофрированный металл: силосы, крыши, ворота.
// rib_axis = 0 — вертикальные рёбра (по U), 1 — горизонтальные кольца (по V).

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.55, 0.58, 0.56);
uniform vec3 rust_color : source_color = vec3(0.36, 0.20, 0.11);
uniform float rib_frequency : hint_range(0.0, 80.0) = 26.0;
uniform float rib_depth : hint_range(0.0, 1.0) = 0.22;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.18;
uniform int rib_axis = 1;

varying vec3 world_pos;

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
}

void fragment() {
	float coord = rib_axis == 0 ? UV.x : UV.y;
	float rib = sin(coord * 6.2831853 * rib_frequency) * 0.5 + 0.5;

	float weather = noise2(world_pos.xz * 0.7) * 0.5 + noise2(world_pos.xz * 4.0) * 0.5;

	vec3 col = base_color * (0.82 + rib * rib_depth + weather * 0.12);
	float rust = smoothstep(0.68, 0.88, weather) * rust_amount;
	col = mix(col, rust_color, rust);

	ALBEDO = col;
	METALLIC = metallic_value * (1.0 - rust);
	ROUGHNESS = mix(roughness_value, 0.9, rust);
	SPECULAR = 0.4;
}
