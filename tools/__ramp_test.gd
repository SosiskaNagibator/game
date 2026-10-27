extends SceneTree
## Временная проверка: проезд пикапа в ворота склада.

var _frames: int = 0
var _scene: Node = null
var _vehicle: VehicleBody3D = null


func _initialize() -> void:
	var packed := load("res://scenes/rural_base.tscn") as PackedScene
	_scene = packed.instantiate()
	get_root().add_child(_scene)


func _physics_process(_delta: float) -> bool:
	_frames += 1

	if _frames == 5:
		_vehicle = _scene.get_node_or_null("BaseVehicle") as VehicleBody3D
		var player: Node = _scene.get_node_or_null("Player")
		_vehicle.driver = player
		_vehicle.global_transform = Transform3D(
			Basis.IDENTITY, Vector3(26.4, RuralHeight.yard_height() + 1.2, 115.0)
		)

	if _frames == 20:
		Input.action_press("accelerate")

	if _frames == 200:
		Input.action_release("accelerate")
		print(
			"RAMP test: pos=", _vehicle.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
			" km/h=", snappedf(_vehicle.linear_velocity.length() * 3.6, 0.1),
			" upright=", snappedf(_vehicle.global_transform.basis.y.dot(Vector3.UP), 0.001)
		)
		quit(0)
		return true

	return false
