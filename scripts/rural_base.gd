@tool
extends Node3D
## Настройка солнечного света для сцены. Держим ориентацию в скрипте,
## чтобы солнце было одинаковым и в редакторе, и в игре.

@export var sun_rotation_degrees := Vector3(-40.0, -55.0, 0.0)
@export var sun_color := Color(1.0, 0.92, 0.78)
@export var sun_energy: float = 1.50


func _ready() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	sun.rotation_degrees = sun_rotation_degrees
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 190.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
