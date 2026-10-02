# GameManager.gd
extends Node

enum Mode { LOCAL, AI }

# Настройки по умолчанию
var game_mode: Mode = Mode.LOCAL
var selected_elo: int = 1500      # Выбранное ELO бота (например: 1000, 1500, 2000)
var base_match_time: int = 600       # Базовое время матча в секундах (дефолт 10 мин)
var time_increment_seconds: int = 0  # Секунды инкремента Фишера за ход


# Фича «Выбор цвета стороны» (v0.1.1.0)
# 0 = Play as White, 1 = Play as Black, 2 = Play as Random
var player_color_choice: int = 0
# Реальный цвет игрока ("w" или "b")
var actual_player_color: String = "w"

# Хранилище для анализа (v0.0.5.0)
var last_moves_history: Array[String] = []
var last_pgn_history: Array[String] = []

# Метод определения финального цвета перед стартом матча
func determine_actual_color() -> void:
	if player_color_choice == 0:
		actual_player_color = "w"
	elif player_color_choice == 1:
		actual_player_color = "b"
	else:
		# Рандом 50 на 50
		actual_player_color = "w" if randf() > 0.5 else "b"
	print("--- GiChess: Финальный цвет игрока определен: ", actual_player_color, " ---")

## Получить параметры Skill Level и Depth на основе выбранного ELO
func get_bot_parameters() -> Dictionary:
	var skill: int = 20
	var depth: int = -1 # -1 означает без ограничений по глубине
	
	if selected_elo <= 900:
		skill = 0
		depth = 1
	elif selected_elo <= 1100:
		skill = 0
		depth = 2
	elif selected_elo <= 1300:
		skill = 3
		depth = 3
	elif selected_elo <= 1500:
		skill = 6
		depth = 5
	elif selected_elo <= 1700:
		skill = 10
		depth = 8
	elif selected_elo <= 1900:
		skill = 14
		depth = 12
	elif selected_elo <= 2100:
		skill = 18
		depth = 16
	else:
		skill = 20
		depth = -1
		
	return {"skill_level": skill, "depth": depth}

## Возвращает массив UCI-команд для инициализации сложности (вызывать при старте матча)
func get_difficulty_init_commands() -> Array[String]:
	var bot_params = get_bot_parameters()
	return [
		"setoption name UCI_LimitStrength value false",
		"setoption name Skill Level value " + str(bot_params["skill_level"])
	]


## Формирует финальную команду "go" с учётом тайм-менеджмента и ограничений глубины
func build_ai_go_command(wtime: int, btime: int, winc: int, binc: int) -> String:
	var bot_params = get_bot_parameters()
	var cmd = "go wtime %d btime %d winc %d binc %d" % [wtime, btime, winc, binc]
	
	# Если для уровня предусмотрено ограничение глубины, добавляем его в строку
	if bot_params["depth"] > 0:
		cmd += " depth " + str(bot_params["depth"])
		
	return cmd
