extends Node3D
## 3D main menu: the world is the menu backdrop, while CanvasLayer handles input.

var start_button: Button
var settings_button: Button
var exit_button: Button
var close_settings_button: Button
var settings_panel: PanelContainer
var brightness_slider: HSlider
var volume_slider: HSlider
var fullscreen_toggle: CheckButton
var antialiasing_option: OptionButton
var camera: Camera3D
var lights: Array[OmniLight3D] = []
var _light_base_energy: Array[float] = []
var _time := 0.0
## Пульсацию фонарей обновляем 10 раз в секунду, а не каждый кадр.
var _pulse_timer := 0.0
## Low three-quarter shot by the pickup's front, looking into the loading bay.
var _base_camera_position := Vector3(-2.70117, 2.243596, 7.406117)
var _camera_target := Vector3(2.29, 3.38, 0.0)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = get_node_or_null("Camera3D") as Camera3D
	start_button = get_node_or_null("Interface/UI/MenuPanel/Margin/Content/StartButton") as Button
	settings_button = get_node_or_null("Interface/UI/MenuPanel/Margin/Content/SettingsButton") as Button
	exit_button = get_node_or_null("Interface/UI/MenuPanel/Margin/Content/ExitButton") as Button
	settings_panel = get_node_or_null("Interface/UI/SettingsPanel") as PanelContainer
	close_settings_button = get_node_or_null("Interface/UI/SettingsPanel/Margin/Content/CloseButton") as Button
	brightness_slider = get_node_or_null("Interface/UI/SettingsPanel/Margin/Content/BrightnessSlider") as HSlider
	volume_slider = get_node_or_null("Interface/UI/SettingsPanel/Margin/Content/VolumeSlider") as HSlider
	fullscreen_toggle = get_node_or_null("Interface/UI/SettingsPanel/Margin/Content/FullscreenToggle") as CheckButton
	antialiasing_option = get_node_or_null("Interface/UI/SettingsPanel/Margin/Content/AntiAliasingOption") as OptionButton

	# Фоновая музыка меню должна играть непрерывно, даже если импорт
	# пересоздан без включённого цикла.
	var music := get_node_or_null("MenuMusic") as AudioStreamPlayer
	if music != null and music.stream is AudioStreamOggVorbis:
		(music.stream as AudioStreamOggVorbis).loop = true

	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		start_button.grab_focus()
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	if close_settings_button:
		close_settings_button.pressed.connect(_on_close_settings_pressed)
	# Показываем сохранённые настройки и пишем изменения в PlayerSettings,
	# который сам применяет их и хранит в user://player_settings.cfg.
	if brightness_slider:
		brightness_slider.value = PlayerSettings.brightness
		brightness_slider.value_changed.connect(PlayerSettings.set_brightness)
	if volume_slider:
		volume_slider.value = PlayerSettings.volume
		volume_slider.value_changed.connect(PlayerSettings.set_volume)
	if fullscreen_toggle:
		fullscreen_toggle.set_pressed_no_signal(PlayerSettings.fullscreen)
		fullscreen_toggle.toggled.connect(PlayerSettings.set_fullscreen)
	if antialiasing_option:
		antialiasing_option.clear()
		for label in PlayerSettings.ANTI_ALIASING_LABELS:
			antialiasing_option.add_item(label)
		antialiasing_option.select(PlayerSettings.antialiasing)
		antialiasing_option.item_selected.connect(PlayerSettings.set_antialiasing)
	PlayerSettings.apply_to_tree()

	for path in ["Warehouse/BayLightLeft", "Warehouse/BayLightCenter", "Warehouse/BayLightRight", "YardSign/SignLight", "PickupLight"]:
		var light := get_node_or_null(path) as OmniLight3D
		if light:
			lights.append(light)
			_light_base_energy.append(light.light_energy)

func _process(delta: float) -> void:
	_time += delta
	if camera:
		camera.position = _base_camera_position + Vector3(
			sin(_time * 0.18) * 0.16,
			cos(_time * 0.23) * 0.08,
			cos(_time * 0.18) * 0.12
		)
		camera.look_at(_camera_target, Vector3.UP)

	_pulse_timer -= delta
	if _pulse_timer > 0.0:
		return
	_pulse_timer = 0.1
	for index in lights.size():
		var light := lights[index]
		var pulse := 1.0 + sin(_time * 2.0 + float(index) * 0.8) * 0.035
		light.light_energy = _light_base_energy[index] * pulse

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_panel and settings_panel.visible:
		_on_close_settings_pressed()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/rural_base.tscn")

func _on_settings_pressed() -> void:
	if settings_panel:
		settings_panel.visible = true
		if close_settings_button:
			close_settings_button.grab_focus()

func _on_close_settings_pressed() -> void:
	if settings_panel:
		settings_panel.visible = false
		if settings_button:
			settings_button.grab_focus()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _build_star_layer(
	node_name: String, count: int, size: float, material: StandardMaterial3D
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = count
	multimesh.use_colors = true # Включаем поддержку цветов на инстанс

	var star_quad := QuadMesh.new()
	star_quad.size = Vector2(size, size)
	star_quad.material = material
	multimesh.mesh = star_quad

	var radius := 7000.0
	
	# Единый цикл, где мы задаем и позицию, и размер, и цвет
	for i in count:
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.02, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()

		# лёгкий разброс размера
		var s := randf_range(0.6, 1.4)
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * s)
		
		# Задаем трансформацию (позиция + масштаб)
		multimesh.set_instance_transform(i, Transform3D(basis, dir * radius))

		# яркость и лёгкий цветовой оттенок (голубые/оранжевые/белые звёзды)
		var b := randf_range(0.5, 1.0) # яркость/прозрачность
		var tint := Color(0.8, 0.9, 1.0).lerp(Color(1.0, 0.85, 0.7), randf())
		
		# Задаем цвет (включая альфа-канал b)
		multimesh.set_instance_color(i, Color(tint.r, tint.g, tint.b, b))

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 200.0
	instance.visible = false
	add_child(instance)
	return instance
