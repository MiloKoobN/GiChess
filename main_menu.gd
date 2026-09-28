# main_menu.gd
extends Control

# Временные настройки времени до старта матча (v0.1.2.0)
var _selected_base_time: int = 600 # 10 минут по умолчанию
var _selected_increment: int = 0   # 0 секунд по умолчанию

@onready var time_option: MenuButton = $CenterContainer/VBoxContainer/TimeOption
@onready var elo_option: OptionButton = $CenterContainer/VBoxContainer/EloOption
@onready var color_option: OptionButton = $CenterContainer/VBoxContainer/ColorOption # Фича v0.1.1.0
@onready var btn_local: Button = $CenterContainer/VBoxContainer/BtnLocal
@onready var btn_ai: Button = $CenterContainer/VBoxContainer/BtnAI

func _ready() -> void:
	# 1. Настройка многоуровневого контроля времени MenuButton (v0.1.2.0)
	time_option.text = "Time: 10 Minutes (Rapid)" # Текст кнопки по умолчанию
	
	time_option.flat = false
	
	var main_popup: PopupMenu = time_option.get_popup()
	main_popup.clear()
	
	# Создаем подменю №1: Без инкремента (Flat Time)
	var flat_popup = PopupMenu.new()
	flat_popup.name = "FlatTimeSubMenu"
	flat_popup.id_pressed.connect(_on_flat_time_selected)
	flat_popup.add_item("1 Minute (Bullet)", 1)
	flat_popup.add_item("3 Minutes (Blitz)", 3)
	flat_popup.add_item("5 Minutes (Blitz)", 5)
	flat_popup.add_item("10 Minutes (Rapid)", 10)
	flat_popup.add_item("30 Minutes (Classical)", 30)
	main_popup.add_child(flat_popup)
	main_popup.add_submenu_item("Flat Time (No Increment)", "FlatTimeSubMenu", 0)
	
	# Создаем подменю №2: С инкрементом Фишера (Fischer Increment)
	var fischer_popup = PopupMenu.new()
	fischer_popup.name = "FischerTimeSubMenu"
	fischer_popup.id_pressed.connect(_on_fischer_time_selected)
	fischer_popup.add_item("1 min + 1s (Bullet)", 11)
	fischer_popup.add_item("3 min + 2s (Blitz)", 32)
	fischer_popup.add_item("5 min + 3s (Blitz)", 53)
	fischer_popup.add_item("5 min + 5s (Blitz)", 55)     # <-- НОВЫЙ ПОПУЛЯРНЫЙ
	fischer_popup.add_item("10 min + 5s (Rapid)", 105)
	fischer_popup.add_item("10 min + 10s (Rapid)", 110)  # <-- НОВЫЙ ПОПУЛЯРНЫЙ
	fischer_popup.add_item("10 min + 15s (Rapid)", 115)  # <-- НОВЫЙ ПОПУЛЯРНЫЙ
	fischer_popup.add_item("15 min + 10s (Rapid)", 1510) # <-- Классика FIDE
	fischer_popup.add_item("30 min + 30s (Classical)", 330) # <-- НОВЫЙ ПОПУЛЯРНЫЙ
	main_popup.add_child(fischer_popup)
	main_popup.add_submenu_item("Fischer Time (+Seconds)", "FischerTimeSubMenu", 1)

	# 2. 8 Lichess-style ELO Difficulty Levels for Stockfish
	elo_option.add_item("Level 1: Beginner (Elo 800)", 800)
	elo_option.add_item("Level 2: Beginner (Elo 1000)", 1000)
	elo_option.add_item("Level 3: Intermediate (Elo 1200)", 1200)
	elo_option.add_item("Level 4: Intermediate (Elo 1400)", 1400)
	elo_option.add_item("Level 5: Advanced (Elo 1600)", 1600)
	elo_option.add_item("Level 6: Advanced (Elo 1800)", 1800)
	elo_option.add_item("Level 7: Expert (Elo 2000)", 2000)
	elo_option.add_item("Level 8: Candidate Master [CM] (Elo 2200)", 2200)

	elo_option.select(3)
	elo_option.item_selected.connect(_on_elo_selected)

	# 3. Выбор цвета стороны (v0.1.1.0)
	color_option.add_item("Play as White", 0)
	color_option.add_item("Play as Black", 1)
	color_option.add_item("Play as Random", 2)
	
	color_option.select(0)
	color_option.item_selected.connect(_on_color_selected)

	# 4. Game Start Button Connections
	btn_local.pressed.connect(_on_local_pressed)
	btn_ai.pressed.connect(_on_ai_pressed)

func _on_time_selected(index: int) -> void:
	var minutes = time_option.get_item_id(index)
	GameManager.time_control_minutes = minutes
	print("Выбран контроль времени: ", minutes, " мин.")

func _on_elo_selected(index: int) -> void:
	var elo = elo_option.get_item_id(index)
	GameManager.selected_elo = elo
	print("Выбрана сложность ИИ: ", elo, " ELO")

func _on_color_selected(index: int) -> void:
	var color_id = color_option.get_item_id(index)
	GameManager.player_color_choice = color_id
	print("Выбран режим цвета: ID ", color_id)

func _on_local_pressed() -> void:
	_sync_game_manager_settings()
	GameManager.game_mode = GameManager.Mode.LOCAL
	get_tree().change_scene_to_file("res://main.tscn")

func _on_ai_pressed() -> void:
	_sync_game_manager_settings()
	GameManager.game_mode = GameManager.Mode.AI
	get_tree().change_scene_to_file("res://main.tscn")

func _sync_game_manager_settings() -> void:
	GameManager.selected_elo = elo_option.get_item_id(elo_option.selected)
	GameManager.player_color_choice = color_option.get_item_id(color_option.selected)
	# Рассчитываем итоговый цвет (на случай если выбран Random)
	GameManager.determine_actual_color()
	# Передаем выбранные настройки времени в глобальный менеджер игры (v0.1.2.0)
	GameManager.base_match_time = _selected_base_time
	GameManager.time_increment_seconds = _selected_increment

func _on_flat_time_selected(id: int) -> void:
	_selected_increment = 0
	
	match id:
		1:  _selected_base_time = 60;   time_option.text = "Time: 1 Minute"
		3:  _selected_base_time = 180;  time_option.text = "Time: 3 Minutes"
		5:  _selected_base_time = 300;  time_option.text = "Time: 5 Minutes"
		10: _selected_base_time = 600;  time_option.text = "Time: 10 Minutes"
		30: _selected_base_time = 1800; time_option.text = "Time: 30 Minutes"
		
	print("--- GiChess: Выбран Flat Time: ", _selected_base_time, " сек. ---")

func _on_fischer_time_selected(id: int) -> void:
	match id:
		11:
			_selected_base_time = 60
			_selected_increment = 1
			time_option.text = "Time: 1 min + 1s"
		32:
			_selected_base_time = 180
			_selected_increment = 2
			time_option.text = "Time: 3 min + 2s"
		53:
			_selected_base_time = 300
			_selected_increment = 3
			time_option.text = "Time: 5 min + 3s"
		55:
			_selected_base_time = 300
			_selected_increment = 5
			time_option.text = "Time: 5 min + 5s"
		105:
			_selected_base_time = 600
			_selected_increment = 5
			time_option.text = "Time: 10 min + 5s"
		110:
			_selected_base_time = 600
			_selected_increment = 10
			time_option.text = "Time: 10 min + 10s"
		115:
			_selected_base_time = 600
			_selected_increment = 15
			time_option.text = "Time: 10 min + 15s"
		1510:
			_selected_base_time = 900
			_selected_increment = 10
			time_option.text = "Time: 15 min + 10s"
		330:
			_selected_base_time = 1800
			_selected_increment = 30
			time_option.text = "Time: 30 min + 30s"
			
	print("--- GiChess: Fischer Time Selected. Base: ", _selected_base_time, "s, Inc: ", _selected_increment, "s ---")
