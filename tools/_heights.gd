extends SceneTree

func _init() -> void:
	var base := Vector2(-228.0, -166.0)
	var y := RuralHeight.yard_height()
	print("YARD Y=", y)
	for z in [0.0, 5.0, 10.0, 12.0, 15.0, 18.0, 20.0, 22.0, 25.0, 28.0]:
		var line := "LOCAL Z %5.1f :" % z
		for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			var h := RuralHeight.terrain_height(base.x + x, base.y + z) - y
			line += " %6.2f" % h
		print(line, "   (world z=", base.y + z, ")")
	quit()
