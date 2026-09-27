extends Control

@onready var time_option: OptionButton = $CenterContainer/VBoxContainer/TimeOption
@onready var elo_option: OptionButton = $CenterContainer/VBoxContainer/EloOption
@onready var btn_local: Button = $CenterContainer/VBoxContainer/BtnLocal
@onready var btn_ai: Button = $CenterContainer/VBoxContainer/BtnAI

func _ready() -> void:
	# 1. Варианты контроля времени (передаем минуты как ID)
	time_option.add_item("1 минута (Пуля)", 1)
	time_option.add_item("3 минуты (Блиц)", 3)
	time_option.add_item("5 минут (Блиц)", 5)
	time_option.add_item("10 минут (Рапид)", 10)
	time_option.add_item("30 минут (Классика)", 30)
	
	# Выбираем по умолчанию 10 минут (это 4-й элемент, индекс 3)
	time_option.select(3) 
	time_option.item_selected.connect(_on_time_selected)

	# 2. Варианты ELO для Stockfish (передаем рейтинг как ID)
	elo_option.add_item("Бот Новичок (ELO 1000)", 1000)
	elo_option.add_item("Бот Любитель (ELO 1400)", 1400)
	elo_option.add_item("Бот Профи (ELO 1800)", 1800)
	elo_option.add_item("Мастер Stockfish (ELO 2200)", 2200)
	
	# Выбираем по умолчанию ELO 1400 (это 2-й элемент, индекс 1)
	elo_option.select(1)
	elo_option.item_selected.connect(_on_elo_selected)

	# 3. Подключаем кнопки старта игры
	btn_local.pressed.connect(_on_local_pressed)
	btn_ai.pressed.connect(_on_ai_pressed)

# ИСПРАВЛЕНО: Читаем ID вместо Метаданных
func _on_time_selected(index: int) -> void:
	var minutes = time_option.get_item_id(index)
	GameManager.time_control_minutes = minutes
	print("Выбран контроль времени: ", minutes, " мин.")

# ИСПРАВЛЕНО: Читаем ID вместо Метаданных
func _on_elo_selected(index: int) -> void:
	var elo = elo_option.get_item_id(index)
	GameManager.selected_elo = elo
	print("Выбрана сложность ИИ: ", elo, " ELO")

func _on_local_pressed() -> void:
	_sync_game_manager_settings()
	GameManager.game_mode = GameManager.Mode.LOCAL
	get_tree().change_scene_to_file("res://main.tscn")

func _on_ai_pressed() -> void:
	_sync_game_manager_settings()
	GameManager.game_mode = GameManager.Mode.AI
	get_tree().change_scene_to_file("res://main.tscn")

# Синхронизация на случай, если игрок ничего не менял в списках
func _sync_game_manager_settings() -> void:
	GameManager.time_control_minutes = time_option.get_item_id(time_option.selected)
	GameManager.selected_elo = elo_option.get_item_id(elo_option.selected)
