extends Control
## Главное меню игры.

@onready var _start_button: Button = $StartButton
@onready var _exit_button: Button = $ExitButton

func _ready() -> void:
	print("MainMenu: _ready вызван")
	print("MainMenu: StartButton =", _start_button)
	print("MainMenu: ExitButton =", _exit_button)
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	_start_button.mouse_filter = 2
	_exit_button.mouse_filter = 2
	
	_start_button.pressed.connect(_on_start_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	
	_start_button.grab_focus()
	print("MainMenu: сигналы подключены")

func _on_start_pressed() -> void:
	print("MainMenu: НАЧАТЬ ИГРУ нажата")
	get_tree().change_scene_to_file("res://scenes/rural_base.tscn")

func _on_exit_pressed() -> void:
	print("MainMenu: ВЫХОД нажата")
	get_tree().quit()