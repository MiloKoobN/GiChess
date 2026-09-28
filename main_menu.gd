# main_menu.gd
extends Control

@onready var time_option: OptionButton = $CenterContainer/VBoxContainer/TimeOption
@onready var elo_option: OptionButton = $CenterContainer/VBoxContainer/EloOption
@onready var color_option: OptionButton = $CenterContainer/VBoxContainer/ColorOption # Фича v0.1.1.0
@onready var btn_local: Button = $CenterContainer/VBoxContainer/BtnLocal
@onready var btn_ai: Button = $CenterContainer/VBoxContainer/BtnAI

func _ready() -> void:
	# 1. Time Control Options (International Chess Standards)
	time_option.add_item("1 Minute (Bullet)", 1)
	time_option.add_item("3 Minutes (Blitz)", 3)
	time_option.add_item("5 Minutes (Blitz)", 5)
	time_option.add_item("10 Minutes (Rapid)", 10)
	time_option.add_item("30 Minutes (Classical)", 30)
	
	# Select 10 Minutes by default (index 3)
	time_option.select(3) 
	time_option.item_selected.connect(_on_time_selected)

	# 2. 8 Lichess-style ELO Difficulty Levels for Stockfish (v0.0.5.0)
	elo_option.add_item("Level 1: Beginner (Elo 800)", 800)
	elo_option.add_item("Level 2: Beginner (Elo 1000)", 1000)
	elo_option.add_item("Level 3: Intermediate (Elo 1200)", 1200)
	elo_option.add_item("Level 4: Intermediate (Elo 1400)", 1400)
	elo_option.add_item("Level 5: Advanced (Elo 1600)", 1600)
	elo_option.add_item("Level 6: Advanced (Elo 1800)", 1800)
	elo_option.add_item("Level 7: Expert (Elo 2000)", 2000)
	elo_option.add_item("Level 8: Candidate Master [CM] (Elo 2200)", 2200)

	# Select ELO 1400 by default (index 3)
	elo_option.select(3)
	elo_option.item_selected.connect(_on_elo_selected)

	# 3. Фича «Выбор цвета стороны» (v0.1.1.0)
	color_option.add_item("Play as White", 0)
	color_option.add_item("Play as Black", 1)
	color_option.add_item("Play as Random", 2)
	
	# По умолчанию выбираем Белых (индекс 0)
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
	GameManager.time_control_minutes = time_option.get_item_id(time_option.selected)
	GameManager.selected_elo = elo_option.get_item_id(elo_option.selected)
	GameManager.player_color_choice = color_option.get_item_id(color_option.selected)
	# Рассчитываем итоговый цвет (на случай если выбран Random)
	GameManager.determine_actual_color()
