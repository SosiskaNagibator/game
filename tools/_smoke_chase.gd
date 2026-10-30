extends SceneTree
## Временный smoke-тест: проверяет структуру police_car.tscn и checkpoint.tscn.
## Запуск: godot --headless --script res://tools/_smoke_chase.gd


func _initialize() -> void:
	var failures: int = 0

	var car_scene := load("res://scenes/police_car.tscn") as PackedScene
	if car_scene == null:
		print("FAIL: police_car.tscn not loaded")
		quit(1)
		return

	var car := car_scene.instantiate()
	print("car root class: ", car.get_class())
	if not (car is CharacterBody3D):
		print("FAIL: root is not CharacterBody3D")
		failures += 1
	if not (car is PoliceCar):
		print("FAIL: script is not PoliceCar")
		failures += 1
	print("collision_layer=", car.collision_layer, " collision_mask=", car.collision_mask)
	if car.collision_layer != 1:
		print("FAIL: collision_layer must be 1")
		failures += 1

	var shape := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null or not (shape.shape is BoxShape3D):
		print("FAIL: CollisionShape3D/BoxShape3D missing")
		failures += 1
	else:
		print("box size=", (shape.shape as BoxShape3D).size)

	var agent := car.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent == null:
		print("FAIL: NavigationAgent3D missing")
		failures += 1
	else:
		print("agent radius=", agent.radius, " height=", agent.height)

	if car.get_node_or_null("SirenAudio") is not AudioStreamPlayer3D:
		print("FAIL: SirenAudio missing")
		failures += 1
	if car.get_node_or_null("RedLight") == null or car.get_node_or_null("BlueLight") == null:
		print("FAIL: siren lights missing")
		failures += 1
	if car.get_node_or_null("NavigationAgent3D") == null:
		print("FAIL: nav agent missing")
		failures += 1

	var cp_scene := load("res://scenes/checkpoint.tscn") as PackedScene
	if cp_scene == null:
		print("FAIL: checkpoint.tscn not loaded")
		failures += 1
	else:
		var cp := cp_scene.instantiate()
		var cp_car := cp.get_node_or_null("PoliceCar")
		if cp_car == null:
			print("FAIL: Checkpoint/PoliceCar missing")
			failures += 1
		else:
			print("checkpoint car class: ", cp_car.get_class())
			if not (cp_car is PoliceCar):
				print("FAIL: Checkpoint/PoliceCar has no PoliceCar script")
				failures += 1
			if not cp_car.has_signal("player_caught"):
				print("FAIL: player_caught signal missing")
				failures += 1
		cp.free()

	car.free()
	print("RESULT: ", "OK" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
