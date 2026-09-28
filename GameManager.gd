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
