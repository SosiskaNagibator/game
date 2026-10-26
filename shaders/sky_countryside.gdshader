shader_type sky;
// Большое кучевое небо для сельской местности.
// Облака рисуются процедурным 3D-шумом по направлению взгляда,
// поэтому нет радиальных полос и швов на сфере неба.

uniform vec3 zenith_color : source_color = vec3(0.16, 0.35, 0.66);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.78, 0.90);
uniform vec3 haze_color : source_color = vec3(0.76, 0.81, 0.84);
uniform vec3 ground_color : source_color = vec3(0.24, 0.28, 0.18);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_shadow : source_color = vec3(0.50, 0.56, 0.67);
uniform vec3 sun_color : source_color = vec3(1.0, 0.87, 0.68);

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.49;
uniform float cloud_scale : hint_range(0.5, 8.0) = 3.0;
uniform float cloud_softness : hint_range(0.02, 0.4) = 0.08;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.003;
uniform float sun_size : hint_range(1.0, 4000.0) = 1500.0;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise3(p) * amp;
		p = p * 2.03 + vec3(17.1, 9.2, 5.7);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = max(dir.y, 0.0);

	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.55));

	vec3 sun_dir = normalize(-LIGHT0_DIRECTION);
	float sun_dot = max(dot(dir, sun_dir), 0.0);
	// Диск солнца и мягкое гало.
	col += sun_color * pow(sun_dot, sun_size) * 3.0;
	col += sun_color * pow(sun_dot, 10.0) * 0.28;

	if (dir.y > 0.0) {
		vec3 drift = vec3(TIME * cloud_speed, 0.0, TIME * cloud_speed * 0.55);
		vec3 p = dir * cloud_scale + drift;

		// Крупные массы + рваная кромка.
		float base = fbm3(p);
		float detail = fbm3(p * 2.7 + base * 0.7);
		float shape = base * 0.76 + detail * 0.24;

		float cover = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, shape);
		// У горизонта облака истончаются и растворяются в дымке.
		cover *= smoothstep(0.015, 0.11, dir.y);

		// Псевдо-объём: плотные ядра светлее, кромка мягче и темнее.
		float lit = smoothstep(cloud_coverage - 0.02, cloud_coverage + 0.19, shape);
		lit = clamp(lit * 0.88 + 0.12 + sun_dot * 0.22, 0.0, 1.0);
		vec3 cloud_col = mix(cloud_shadow, cloud_light, lit);
		// Нижние части облаков холоднее.
		cloud_col *= 0.86 + 0.14 * smoothstep(0.03, 0.28, dir.y);
		// Тёплый край на солнечной стороне облака.
		cloud_col = mix(cloud_col, sun_color, pow(sun_dot, 5.0) * 0.40 * lit);
		// Дальние облака сильнее растворяются у горизонта.
		cloud_col = mix(horizon_color * 1.04, cloud_col, smoothstep(0.02, 0.26, dir.y));

		col = mix(col, cloud_col, cover);
	}

	// Дымка у горизонта, чтобы край земли растворялся.
	col = mix(haze_color, col, smoothstep(-0.04, 0.14, dir.y));

	if (dir.y < 0.0) {
		col = mix(col, ground_color, smoothstep(0.0, -0.12, dir.y));
	}

	COLOR = col;
}
