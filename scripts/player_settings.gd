extends Node
## Настройки игрока: сохраняются в user://player_settings.cfg и
## восстанавливаются при следующем запуске игры.

const SETTINGS_PATH := "user://player_settings.cfg"

const MIN_BRIGHTNESS := 0.5
const MAX_BRIGHTNESS := 1.5
const DEFAULT_BRIGHTNESS := 0.9
const DEFAULT_VOLUME := 0.8

## Режимы сглаживания. Порядок должен совпадать с порядком в настройках.
enum AntiAliasing { OFF, FXAA, MSAA_2X, MSAA_4X, TAA }
const ANTI_ALIASING_LABELS := ["ВЫКЛЮЧЕНО", "FXAA", "MSAA 2X", "MSAA 4X", "TAA"]
const DEFAULT_ANTI_ALIASING := AntiAliasing.FXAA

signal brightness_changed(value: float)
signal volume_changed(value: float)
signal fullscreen_changed(enabled: bool)
signal antialiasing_changed(mode: int)

## Текущие значения. Читайте их, чтобы инициализировать элементы UI.
var brightness := DEFAULT_BRIGHTNESS
var volume := DEFAULT_VOLUME
var fullscreen := false
var antialiasing := DEFAULT_ANTI_ALIASING

## Запись на диск откладываем, чтобы перетаскивание ползунка
## не сохраняло файл десятки раз в секунду.
var _save_timer: Timer

func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)

	load_settings()
	apply_to_tree()
	# Смена сцен создаёт новые WorldEnvironment/Camera3D. Подписываемся на их
	# появление, чтобы яркость работала во всей игре, а не только в меню.
	get_tree().node_added.connect(_on_node_added)

func _exit_tree() -> void:
	# Не теряем изменения, если игру закрыли сразу после правки настройки.
	if _save_timer != null and not _save_timer.is_stopped():
		save_settings()

func _request_save() -> void:
	if _save_timer != null:
		_save_timer.start()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		# Файла ещё нет (первый запуск): берём текущий режим окна,
		# чтобы не менять поведение игры.
		fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		_apply_audio()
		_apply_fullscreen()
		return

	brightness = clampf(
		float(config.get_value("video", "brightness", DEFAULT_BRIGHTNESS)),
		MIN_BRIGHTNESS,
		MAX_BRIGHTNESS
	)
	volume = clampf(
		float(config.get_value("audio", "master_volume", DEFAULT_VOLUME)),
		0.0,
		1.0
	)
	fullscreen = bool(config.get_value(
		"video",
		"fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	))
	antialiasing = clampi(
		int(config.get_value("video", "antialiasing", DEFAULT_ANTI_ALIASING)),
		AntiAliasing.OFF,
		AntiAliasing.size() - 1
	)

	_apply_audio()
	_apply_fullscreen()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "brightness", brightness)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "antialiasing", antialiasing)
	config.set_value("audio", "master_volume", volume)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("PlayerSettings: не удалось сохранить %s (код %d)" % [SETTINGS_PATH, err])

func set_brightness(value: float) -> void:
	value = clampf(value, MIN_BRIGHTNESS, MAX_BRIGHTNESS)
	if is_equal_approx(value, brightness):
		return
	brightness = value
	apply_brightness()
	_request_save()
	brightness_changed.emit(brightness)

func set_volume(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, volume):
		return
	volume = value
	_apply_audio()
	_request_save()
	volume_changed.emit(volume)

func set_fullscreen(enabled: bool) -> void:
	if enabled == fullscreen:
		return
	fullscreen = enabled
	_apply_fullscreen()
	_request_save()
	fullscreen_changed.emit(fullscreen)

func set_antialiasing(mode: int) -> void:
	mode = clampi(mode, AntiAliasing.OFF, AntiAliasing.size() - 1)
	if mode == antialiasing:
		return
	antialiasing = mode
	apply_antialiasing()
	_request_save()
	antialiasing_changed.emit(antialiasing)

## Применяет все сохранённые настройки к текущему дереву сцен.
## Обычно вызывать вручную не нужно: новые сцены и WorldEnvironment
## подхватываются автоматически через node_added.
func apply_to_tree() -> void:
	_apply_audio()
	_apply_fullscreen()
	apply_brightness()
	apply_antialiasing()

func apply_brightness() -> void:
	_apply_to_subtree(get_tree().root)

func apply_antialiasing() -> void:
	var viewport := get_viewport()
	if viewport == null:
		# Страховка для вызовов до/вне дерева сцен (например, в тестах).
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			viewport = (main_loop as SceneTree).root
	if viewport == null:
		return
	# Сбрасываем все виды сглаживания, затем включаем выбранный.
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	match antialiasing:
		AntiAliasing.FXAA:
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AntiAliasing.MSAA_2X:
			viewport.msaa_3d = Viewport.MSAA_2X
		AntiAliasing.MSAA_4X:
			viewport.msaa_3d = Viewport.MSAA_4X
		AntiAliasing.TAA:
			viewport.use_taa = true

func _on_node_added(node: Node) -> void:
	# Новые WorldEnvironment и камеры могут появиться в любой момент: при смене
	# сцены, спавне из кода и т.д. Отложенный вызов гарантирует, что к этому
	# моменту сцена уже назначила свой Environment.
	if node is WorldEnvironment or node is Camera3D:
		_apply_to_node.call_deferred(node)

func _apply_to_subtree(node: Node) -> void:
	_apply_to_node(node)
	for child in node.get_children():
		_apply_to_subtree(child)

func _apply_to_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var env: Environment = null
	if node is WorldEnvironment:
		env = (node as WorldEnvironment).environment
	elif node is Camera3D:
		# Environment у камеры перекрывает WorldEnvironment — его тоже
		# нужно держать в актуальном состоянии.
		env = (node as Camera3D).environment
	_apply_to_environment(env)

func _apply_to_environment(env: Environment) -> void:
	if env == null:
		return
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness

func _apply_audio() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(volume, 0.001)))
	AudioServer.set_bus_mute(master_bus, is_zero_approx(volume))

func _apply_fullscreen() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

