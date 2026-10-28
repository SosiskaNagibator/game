shader_type spatial;
// Листва и кора отдельного дерева-объекта.
// Цвет запечён в COLOR при сборке меша (кора и крона в одном меше),
// альфа COLOR — маска покачивания: 0 у листвы, 1 у ствола.

render_mode diffuse_burley, specular_schlick_ggx;

uniform float sway_strength : hint_range(0.0, 0.2) = 0.025;

varying vec3 tree_tint;

void vertex() {
	tree_tint = COLOR.rgb;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway_mask = 1.0 - COLOR.a;
	float phase = world_pos.x * 0.12 + world_pos.z * 0.09;
	float sway = sin(TIME * 0.85 + phase) * sway_strength;
	float height_factor = clamp(world_pos.y * 0.10, 0.0, 1.0);
	VERTEX.x += sway * height_factor * sway_mask;
	VERTEX.z += cos(TIME * 0.63 + phase * 1.4) * sway * 0.6 * height_factor * sway_mask;
}

void fragment() {
	// Плоская грань — та же инди-стилистика, что у леса из MultiMesh.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (!FRONT_FACING) {
		n = -n;
	}
	NORMAL = n;

	ALBEDO = tree_tint;
	ROUGHNESS = 0.88;
	SPECULAR = 0.08;
}
