shader_type spatial;

// Простая шахматная текстура в локальных координатах объекта.
// Работает без UV и не растягивается на разных гранях BoxMesh.

uniform vec3 color_a : source_color = vec3(0.28, 0.34, 0.42);
uniform vec3 color_b : source_color = vec3(0.37, 0.44, 0.53);
uniform float cell_size = 0.8;
uniform float roughness_value = 0.55;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	// Выбираем плоскость проекции по доминирующей оси нормали.
	vec3 n = abs(local_normal);
	vec2 uv;
	if (n.y > n.x && n.y > n.z) {
		uv = local_pos.xz;
	} else if (n.x > n.z) {
		uv = local_pos.zy;
	} else {
		uv = local_pos.xy;
	}

	float checker = mod(floor(uv.x / cell_size) + floor(uv.y / cell_size), 2.0);
	ALBEDO = mix(color_a, color_b, checker);
	ROUGHNESS = roughness_value;
	METALLIC = 0.05;
}
