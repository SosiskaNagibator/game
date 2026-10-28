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
var world_environment: WorldEnvironment
var camera: Camera3D
var lights: Array[OmniLight3D] = []
var _time := 0.0
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
	world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment

	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		start_button.grab_focus()
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	if close_settings_button:
		close_settings_button.pressed.connect(_on_close_settings_pressed)
	if brightness_slider:
		brightness_slider.value_changed.connect(_on_brightness_changed)
		_on_brightness_changed(brightness_slider.value)
	if volume_slider:
		volume_slider.value_changed.connect(_on_volume_changed)
		_on_volume_changed(volume_slider.value)
	if fullscreen_toggle:
		fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
		fullscreen_toggle.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

	for path in ["Warehouse/BayLightLeft", "Warehouse/BayLightCenter", "Warehouse/BayLightRight", "YardSign/SignLight", "PickupLight"]:
		var light := get_node_or_null(path) as OmniLight3D
		if light:
			lights.append(light)

func _process(delta: float) -> void:
	_time += delta
	if camera:
		camera.position = _base_camera_position + Vector3(
			sin(_time * 0.18) * 0.16,
			cos(_time * 0.23) * 0.08,
			cos(_time * 0.18) * 0.12
		)
		camera.look_at(_camera_target, Vector3.UP)
	for index in lights.size():
		var light := lights[index]
		var pulse := 1.0 + sin(_time * 2.0 + float(index) * 0.8) * 0.035
		light.light_energy = light.light_energy * 0.98 + light.light_energy * 0.02 * pulse

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

func _on_brightness_changed(value: float) -> void:
	if world_environment and world_environment.environment:
		world_environment.environment.adjustment_brightness = value

func _on_volume_changed(value: float) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(value, 0.001)))
		AudioServer.set_bus_mute(master_bus, is_zero_approx(value))

func _on_fullscreen_toggled(enabled: bool) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _on_exit_pressed() -> void:
	get_tree().quit()
