# GameManager.gd
extends Node

enum Mode { LOCAL, AI }

# Настройки по умолчанию
var game_mode: Mode = Mode.LOCAL
var selected_elo: int = 1500      # Выбранное ELO бота (например: 1000, 1500, 2000)
var time_control_minutes: int = 10 # Время на партию в минутах (например: 1, 3, 5, 10)
