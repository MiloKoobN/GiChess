extends Control

var position_history: Array[String] = [] # Хранит слепки позиций для правила 3-кратного повторения

@export var cell_scene: PackedScene = preload("res://cell.tscn")

@export var light_color: Color = Color("f0d9b5")
@export var dark_color: Color = Color("b58863")

@onready var board: GridContainer = $CenterContainer/GameLayout/AspectRatioContainer/BoardWrapper/Board
@onready var white_timer_label: Label = $CenterContainer/GameLayout/SidePanel/WhiteTimerLabel
@onready var black_timer_label: Label = $CenterContainer/GameLayout/SidePanel/BlackTimerLabel
@onready var white_name_label: Label = $CenterContainer/GameLayout/SidePanel/WhiteNameLabel
@onready var black_name_label: Label = $CenterContainer/GameLayout/SidePanel/BlackNameLabel
@onready var btn_resign: Button = $CenterContainer/GameLayout/SidePanel/BtnResign
@onready var sound_player: AudioStreamPlayer = find_child("SoundPlayer", true, false)
# Вставь это в самый верх main_board.gd вместо старых @onready переменных:

var initial_board = [
	["r", "n", "b", "q", "k", "b", "n", "r"],
	["p", "p", "p", "p", "p", "p", "p", "p"],
	[".", ".", ".", ".", ".", ".", ".", "."],
	[".", ".", ".", ".", ".", ".", ".", "."],
	[".", ".", ".", ".", ".", ".", ".", "."],
	[".", ".", ".", ".", ".", ".", ".", "."],
	["P", "P", "P", "P", "P", "P", "P", "P"],
	["R", "N", "B", "Q", "K", "B", "N", "R"]
]

var cells_dict = {}
var selected_cell: ColorRect = null
var current_turn: String = "w"
var game_over: bool = false

var promotion_pending_cell: ColorRect = null
var promotion_ui: PanelContainer = null

var moves_history: Array[String] = []
var is_ai_thinking: bool = false

var white_time_left: float = 0.0
var black_time_left: float = 0.0
var game_timer: Timer = null

# Флаги истории ходов для реализации рокировки
var white_king_moved: bool = false
var white_rook_a1_moved: bool = false
var white_rook_h1_moved: bool = false

var black_king_moved: bool = false
var black_rook_a8_moved: bool = false
var black_rook_h8_moved: bool = false

var en_passant_target_square: Vector2i = Vector2i(-1, -1) # Клетка за прыгнувшей пешкой

var halfmove_clock: int = 0 # Счетчик полуходов для правила 50 ходов

func _ready() -> void:
	generate_board()
	setup_initial_pieces()
	
	white_name_label.text = "Вы (Белые)"
	if GameManager.game_mode == GameManager.Mode.AI:
		black_name_label.text = "Stockfish (" + str(GameManager.selected_elo) + " ELO)"
	else:
		black_name_label.text = "Друг (Черные)"
		
	white_time_left = GameManager.time_control_minutes * 60.0
	black_time_left = GameManager.time_control_minutes * 60.0
	update_timer_labels()
	
	if not btn_resign.pressed.is_connected(_on_resign_pressed):
		btn_resign.pressed.connect(_on_resign_pressed)
	
	game_timer = Timer.new()
	game_timer.wait_time = 1.0
	game_timer.autostart = true
	game_timer.timeout.connect(_on_timer_tick)
	add_child(game_timer)

func _on_resign_pressed() -> void:
	game_over = true
	show_game_over_screen("КОНЕЦ ИГРЫ", "Вы сдались")

func _on_timer_tick() -> void:
	if game_over: return
	
	if current_turn == "w":
		white_time_left -= 1.0
		if white_time_left <= 0:
			game_over = true
			show_game_over_screen("ВРЕМЯ ИСТЕКЛО", "Черные победили!")
	else:
		black_time_left -= 1.0
		if black_time_left <= 0:
			game_over = true
			show_game_over_screen("ВРЕМЯ ИСТЕКЛО", "Белые победили!")
			
	update_timer_labels()

func update_timer_labels() -> void:
	white_timer_label.text = format_time(white_time_left)
	black_timer_label.text = format_time(black_time_left)

func format_time(time_in_seconds: float) -> String:
	var minutes = int(time_in_seconds) / 60
	var seconds = int(time_in_seconds) % 60
	return "%02d:%02d" % [minutes, seconds]

# Замени метод generate_board() и добавь код ниже в main_board.gd

func generate_board() -> void:
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	
	cells_dict.clear()
	for child in board.get_children():
		child.queue_free()
		
	# Удаляем старую внешнюю разметку, если она была (для перезапуска партии)
	for child in get_children():
		if child.name == "LeftRanks" or child.name == "BottomFiles":
			child.queue_free()
	
	board.columns = 8
	
	for row in range(8):
		for col in range(8):
			var cell = cell_scene.instantiate()
			var current_color = light_color if (row + col) % 2 == 0 else dark_color
			var chess_name = files[col] + ranks[row]
			var grid_pos = Vector2i(col, row)
			
			cell.setup(grid_pos, chess_name, current_color)
			cell.name = chess_name
			cell.cell_clicked.connect(_on_cell_clicked)
			
			board.add_child(cell)
			cells_dict[chess_name] = cell
			
	# Ждем окончания кадра отрисовки интерфейса, чтобы узнать точные экранные координаты доски
	await get_tree().process_frame
	create_external_notation(ranks, files)
	print("--- GiChess: Внешняя разметка Lichess успешно создана! ---")

func create_external_notation(ranks: Array, files: Array) -> void:
	var board_size = board.size
	var board_pos = board.global_position
	
	var text_color = Color("161512") 
	
	# --- СЛЕВА: Вертикальный ряд ЦИФР ---
	var left_ranks = VBoxContainer.new()
	left_ranks.name = "LeftRanks"
	left_ranks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_ranks)
	
	left_ranks.global_position = Vector2(board_pos.x - 24, board_pos.y)
	# ИСПРАВЛЕНО: используем .size вместо .global_size
	left_ranks.size = Vector2(16, board_size.y)
	left_ranks.add_theme_constant_override("separation", 0)
	
	for i in range(8):
		var lbl = Label.new()
		lbl.text = ranks[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_vertical = SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", text_color)
		lbl.add_theme_font_size_override("font_size", 16)
		left_ranks.add_child(lbl)
		
	# --- СНИЗУ: Горизонтальный ряд БУКВ ---
	var bottom_files = HBoxContainer.new()
	bottom_files.name = "BottomFiles"
	bottom_files.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_files)
	
	bottom_files.global_position = Vector2(board_pos.x, board_pos.y + board_size.y + 6)
	# ИСПРАВЛЕНО: используем .size вместо .global_size
	bottom_files.size = Vector2(board_size.x, 16)
	bottom_files.add_theme_constant_override("separation", 0)
	
	for i in range(8):
		var lbl = Label.new()
		lbl.text = files[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", text_color)
		lbl.add_theme_font_size_override("font_size", 16)
		bottom_files.add_child(lbl)

# АВТО-ПЕРЕПРИВЯЗКА ПРИ РЕЗАЙЗЕ ОКНА
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if is_inside_tree() and board and cells_dict.size() > 0:
			await get_tree().process_frame
			var left_ranks = get_node_or_null("LeftRanks")
			var bottom_files = get_node_or_null("BottomFiles")
			if left_ranks and bottom_files:
				# ИСПРАВЛЕНО: везде заменили .global_size на .size
				left_ranks.global_position = Vector2(board.global_position.x - 24, board.global_position.y)
				left_ranks.size = Vector2(16, board.size.y)
				bottom_files.global_position = Vector2(board.global_position.x, board.global_position.y + board.size.y + 6)
				bottom_files.size = Vector2(board.size.x, 16)

func setup_initial_pieces() -> void:
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	for row in range(8):
		for col in range(8):
			var piece_char = initial_board[row][col]
			if piece_char == ".": continue
			var piece_color = "w" if piece_char == piece_char.to_upper() else "b"
			var piece_type = piece_char.to_upper()
			var chess_name = files[col] + ranks[row]
			if cells_dict.has(chess_name):
				cells_dict[chess_name].set_piece(piece_type, piece_color)

func _on_cell_clicked(_grid_pos: Vector2i, chess_coordinate: String) -> void:
	if game_over or is_ai_thinking: return
	var clicked_cell = cells_dict[chess_coordinate]
	if selected_cell == null:
		if clicked_cell.piece_data != null and clicked_cell.piece_data["color"] == current_turn:
			if GameManager.game_mode == GameManager.Mode.AI and current_turn == "b": return
			select_cell(clicked_cell)
	else:
		if selected_cell == clicked_cell:
			deselect_all()
			return
		if clicked_cell.piece_data != null and clicked_cell.piece_data["color"] == current_turn:
			deselect_all()
			select_cell(clicked_cell)
			return
		if is_move_completely_legal(selected_cell, clicked_cell):
			var uci_move = selected_cell.chess_coordinate + clicked_cell.chess_coordinate
			moves_history.append(uci_move)
			make_move(selected_cell, clicked_cell)

func select_cell(cell: ColorRect) -> void:
	selected_cell = cell
	selected_cell.highlight_selected()
	for chess_name in cells_dict:
		var target_cell = cells_dict[chess_name]
		if is_move_completely_legal(selected_cell, target_cell):
			target_cell.show_dot()

func deselect_all() -> void:
	if selected_cell != null:
		selected_cell.reset_highlight()
		selected_cell = null
	for chess_name in cells_dict:
		cells_dict[chess_name].hide_dot()

# Замени начало метода make_move() в main_board.gd:

func make_move(from_cell: ColorRect, to_cell: ColorRect) -> void:
	var moving_piece = from_cell.piece_data
	var start = from_cell.grid_position
	var target = to_cell.grid_position
	
	var is_capture: bool = to_cell.piece_data != null
	
	# === ЛОГИКА ВЗЯТИЯ НА ПРОХОДЕ (Удаление врага) ===
	if moving_piece["type"] == "P" and target == en_passant_target_square:
		# Находим вражескую пешку (она стоит на том же столбце, но на старой строке старта)
		var enemy_pawn_cell = get_cell_by_grid(target.x, start.y)
		enemy_pawn_cell.clear_piece()
		is_capture = true # Считаем это взятием для звукового эффекта!
	
	# Обнуляем мишень прохода по умолчанию для этого хода
	en_passant_target_square = Vector2i(-1, -1)
	
	# Если пешка прыгнула на 2 клетки — создаем мишень прохода позади неё
	if moving_piece["type"] == "P" and abs(target.y - start.y) == 2:
		var dir = -1 if moving_piece["color"] == "w" else 1
		en_passant_target_square = Vector2i(start.x, start.y + dir)

	# Логика рокировки ладьи (Остается без изменений!)
	if moving_piece["type"] == "K" and abs(target.x - start.x) == 2:
		if moving_piece["color"] == "w" and target == Vector2i(6, 7):
			get_cell_by_grid(5, 7).set_piece("R", "w")
			get_cell_by_grid(7, 7).clear_piece()
		elif moving_piece["color"] == "w" and target == Vector2i(2, 7):
			get_cell_by_grid(3, 7).set_piece("R", "w")
			get_cell_by_grid(0, 7).clear_piece()
		elif moving_piece["color"] == "b" and target == Vector2i(6, 0):
			get_cell_by_grid(5, 0).set_piece("R", "b")
			get_cell_by_grid(7, 0).clear_piece()
		elif moving_piece["color"] == "b" and target == Vector2i(2, 0):
			get_cell_by_grid(3, 0).set_piece("R", "b")
			get_cell_by_grid(0, 0).clear_piece()

	# Физически перемещаем фигуру на доске
	to_cell.set_piece(moving_piece["type"], moving_piece["color"])
	from_cell.clear_piece()
	
		# === ОБНОВЛЕНИЕ СЧЕТЧИКА ДЛЯ ПРАВИЛА 50 ХОДОВ ===
	if moving_piece["type"] == "P" or is_capture:
		halfmove_clock = 0 # Сброс, если походила пешка или съели фигуру
	else:
		halfmove_clock += 1 # Увеличиваем счетчик при обычном ходе
	print("Полуходов без взятий и пешек: ", halfmove_clock)

	# === БЛОК ЗВУКА ПОД ТВОИ ФАЙЛЫ MOVE.MP3 И CAPTURE.MP3 ===
	if sound_player:
		var sound_path = "res://assets/sounds/capture.mp3" if is_capture else "res://assets/sounds/move.mp3"
		
		if ResourceLoader.exists(sound_path):
			sound_player.stream = load(sound_path)
			sound_player.play()
		else:
			print("Аудио-файл не найден по пути: ", sound_path)

	# Обновление флагов рокировки короля/ладьи
	if moving_piece["type"] == "K":
		if moving_piece["color"] == "w": white_king_moved = true
		else: black_king_moved = true
	elif moving_piece["type"] == "R":
		if moving_piece["color"] == "w":
			if start == Vector2i(0, 7): white_rook_a1_moved = true
			elif start == Vector2i(7, 7): white_rook_h1_moved = true
		else:
			if start == Vector2i(0, 0): black_rook_a8_moved = true
			elif start == Vector2i(7, 0): black_rook_h8_moved = true

	deselect_all()
	
	# Превращение пешки
	if moving_piece["type"] == "P" and (to_cell.grid_position.y == 0 or to_cell.grid_position.y == 7):
		promotion_pending_cell = to_cell
		if GameManager.game_mode == GameManager.Mode.AI and current_turn == "b":
			_on_promotion_selected("Q", "b")
		else:
			show_promotion_menu(moving_piece["color"])
		return
	
		# === ЗАПИСЬ СЛЕПКА ПОЗИЦИИ ДЛЯ ПРАВИЛА 3 ХОДОВ ===
	var current_snapshot = generate_position_snapshot()
	position_history.append(current_snapshot)
	
	complete_turn()

func complete_turn() -> void:
	current_turn = "b" if current_turn == "w" else "w"
	
	# 1. Проверяем классический Мат и Пат
	var has_moves = has_any_legal_moves(current_turn)
	var king_in_check = is_king_in_check(current_turn)
	
	if not has_moves:
		game_over = true
		if king_in_check:
			var winner_text = "Белые победили!" if current_turn == "b" else "Черные победили!"
			show_game_over_screen("МАТ", winner_text)
		else:
			show_game_over_screen("ПАТ", "Ничья")
		return
		
	# 2. Проверяем правило 50 ходов (50 ходов = 100 полуходов)
	if halfmove_clock >= 100:
		game_over = true
		show_game_over_screen("НИЧЬЯ", "Правило 50 ходов")
		return
	
		# 2. Проверяем правило 50 ходов... (этот блок у тебя уже есть)
	if halfmove_clock >= 100:
		game_over = true
		show_game_over_screen("НИЧЬЯ", "Правило 50 ходов")
		return
		
	# === НОВОЕ: ПРОВЕРКА ТРЕХКРАТНОГО ПОВТОРЕНИЯ ПОЗИЦИИ ===
	if position_history.size() > 0:
		var last_snapshot = position_history[position_history.size() - 1]
		var repetitions = position_history.count(last_snapshot)
		if repetitions >= 3:
			game_over = true
			show_game_over_screen("НИЧЬЯ", "3-кратное повторение позиции")
			return
	
	# 3. Проверяем недостаток материала для мата
	if is_insufficient_material():
		game_over = true
		show_game_over_screen("НИЧЬЯ", "Недостаточно материала для мата")
		return
		
	if king_in_check:
		print("Внимание: Королю объявлен ШАХ!")
		
	# Если игра продолжается и ход бота — запускаем Stockfish
	if GameManager.game_mode == GameManager.Mode.AI and current_turn == "b" and not game_over:
		get_ai_move()

func get_ai_move() -> void:
	is_ai_thinking = true
	var thread = Thread.new()
	thread.start(call_stockfish_process)

func call_stockfish_process() -> String:
	var path_to_exe = ProjectSettings.globalize_path("res://bin/stockfish.exe")
	if OS.get_name() == "macOS" or OS.get_name() == "Linux":
		path_to_exe = ProjectSettings.globalize_path("res://bin/stockfish")
	if not FileAccess.file_exists(path_to_exe):
		call_deferred("_on_ai_move_received", "")
		return ""
	var pipes = OS.execute_with_pipe(path_to_exe, [])
	if pipes.size() == 0:
		call_deferred("_on_ai_move_received", "")
		return ""
	var pipe_in = pipes["stdio"]
	
	pipe_in.store_line("setoption name UCI_LimitStrength value true")
	pipe_in.store_line("setoption name UCI_Elo value " + str(GameManager.selected_elo))
	
	var position_cmd = "position startpos"
	if moves_history.size() > 0:
		position_cmd += " moves " + " ".join(moves_history)
		# Внутри метода call_stockfish_process()
	
		# Внутри метода call_stockfish_process() в main_board.gd
	pipe_in.store_line(position_cmd)
	
	var wtime_ms = int(white_time_left * 1000)
	var btime_ms = int(black_time_left * 1000)
	
	# УМНОЕ УПРАВЛЕНИЕ ВРЕМЕНЕМ:
	# Если сделано меньше 12 полуходов (6 полных ходов обоих игроков) — это дебют.
	# В дебюте заставляем бота отвечать быстро (максимум 1.5 секунды), чтобы не зависал на e4 c5.
	if moves_history.size() < 12:
		var debut_time = 1500 # 1.5 секунды
		pipe_in.store_line("go wtime " + str(wtime_ms) + " btime " + str(btime_ms) + " movetime " + str(debut_time))
	else:
		# После дебюта снимаем ограничения! Бот сам решает, сколько думать, основываясь на времени на часах
		pipe_in.store_line("go wtime " + str(wtime_ms) + " btime " + str(btime_ms))
		
	pipe_in.flush()

	var best_move = ""
	while true:
		if pipe_in.get_error() != OK: break
		var line = pipe_in.get_line()
		if line.begins_with("bestmove"):
			var tokens = line.split(" ")
			if tokens.size() > 1: best_move = tokens[1]
			break
	pipe_in.store_line("quit")
	pipe_in.close()
	call_deferred("_on_ai_move_received", best_move)
	return best_move

func _on_ai_move_received(ai_move: String) -> void:
	is_ai_thinking = false
	if ai_move == "" or ai_move == "(none)": return
	var from_name = ai_move.substr(0, 2)
	var to_name = ai_move.substr(2, 2)
	if cells_dict.has(from_name) and cells_dict.has(to_name):
		var from_cell = cells_dict[from_name]
		var to_cell = cells_dict[to_name]
		moves_history.append(ai_move)
		make_move(from_cell, to_cell)

func has_any_legal_moves(color: String) -> bool:
	for from_name in cells_dict:
		var from_cell = cells_dict[from_name]
		if from_cell.piece_data != null and from_cell.piece_data["color"] == color:
			for to_name in cells_dict:
				if is_move_completely_legal(from_cell, cells_dict[to_name]): return true
	return false

func is_move_completely_legal(from_cell: ColorRect, to_cell: ColorRect) -> bool:
	var piece = from_cell.piece_data
	if piece == null: return false
	
	var start = from_cell.grid_position
	var target = to_cell.grid_position
	var diff_x = target.x - start.x
	var diff_y = target.y - start.y
	
	if to_cell.piece_data != null and to_cell.piece_data["color"] == piece["color"]:
		return false

	# ПРОВЕРКА РОКИРОВКИ (Здесь она абсолютно безопасна и не вызывает рекурсию!)
	if piece["type"] == "K" and diff_y == 0 and abs(diff_x) == 2:
		var is_white_start = (piece["color"] == "w" and start == Vector2i(4, 7))
		var is_black_start = (piece["color"] == "b" and start == Vector2i(4, 0))
		
		if is_white_start or is_black_start:
			if is_king_in_check(piece["color"]): return false
			var enemy = "b" if piece["color"] == "w" else "w"
			
			# --- Рокировка Белых ---
			if is_white_start and not white_king_moved:
				if target == Vector2i(6, 7) and not white_rook_h1_moved: # Короткая
					# Проверяем битые поля f1 и g1
					if is_square_attacked(Vector2i(5, 7), enemy) or is_square_attacked(Vector2i(6, 7), enemy): return false
					return get_cell_by_grid(5, 7).piece_data == null and get_cell_by_grid(6, 7).piece_data == null
				if target == Vector2i(2, 7) and not white_rook_a1_moved: # Длинная
					# Проверяем битые поля d1 и c1
					if is_square_attacked(Vector2i(3, 7), enemy) or is_square_attacked(Vector2i(2, 7), enemy): return false
					return get_cell_by_grid(1, 7).piece_data == null and get_cell_by_grid(2, 7).piece_data == null and get_cell_by_grid(3, 7).piece_data == null
					
			# --- Рокировка Черных ---
			if is_black_start and not black_king_moved:
				if target == Vector2i(6, 0) and not black_rook_h8_moved: # Короткая
					# Проверяем битые поля f8 и g8
					if is_square_attacked(Vector2i(5, 0), enemy) or is_square_attacked(Vector2i(6, 0), enemy): return false
					return get_cell_by_grid(5, 0).piece_data == null and get_cell_by_grid(6, 0).piece_data == null
				if target == Vector2i(2, 0) and not black_rook_a8_moved: # Длинная
					# Проверяем битые поля d8 и c8
					if is_square_attacked(Vector2i(3, 0), enemy) or is_square_attacked(Vector2i(2, 0), enemy): return false
					return get_cell_by_grid(1, 0).piece_data == null and get_cell_by_grid(2, 0).piece_data == null and get_cell_by_grid(3, 0).piece_data == null
		
		return false

	# СТАНДАРТНАЯ ПРОВЕРКА ДЛЯ ВСЕХ ОСТАЛЬНЫХ ХОДОВ
	if not is_move_base_legal(from_cell, to_cell): 
		return false
		
	var target_piece = to_cell.piece_data
	to_cell.piece_data = piece
	from_cell.piece_data = null
	
	var king_safe = not is_king_in_check(piece["color"])
	
	from_cell.piece_data = piece
	to_cell.piece_data = target_piece
	
	return king_safe

func is_king_in_check(color: String) -> bool:
	var king_pos = Vector2i(-1, -1)
	for name in cells_dict:
		var cell = cells_dict[name]
		if cell.piece_data != null and cell.piece_data["type"] == "K" and cell.piece_data["color"] == color:
			king_pos = cell.grid_position
			break
			
	if king_pos == Vector2i(-1, -1): return false
	
	var enemy = "b" if color == "w" else "w"
	for name in cells_dict:
		var cell = cells_dict[name]
		if cell.piece_data != null and cell.piece_data["color"] == enemy:
			# РАЗРЫВ РЕКУРСИИ: Если проверяем вражеского короля, смотрим только дистанцию шага
			if cell.piece_data["type"] == "K":
				var diff_x = abs(king_pos.x - cell.grid_position.x)
				var diff_y = abs(king_pos.y - cell.grid_position.y)
				if diff_x <= 1 and diff_y <= 1:
					return true # Короли встали в упор (нелегально по ФИДЕ)
			else:
				# Для всех остальных фигур безопасно проверяем базовую геометрию ходов
				if is_move_base_legal(cell, cells_dict[get_name_by_grid(king_pos.x, king_pos.y)]):
					return true
					
	return false

# Проверяет, атакована ли конкретная клетка вражескими фигурами
func is_square_attacked(square: Vector2i, by_color: String) -> bool:
	for name in cells_dict:
		var cell = cells_dict[name]
		if cell.piece_data != null and cell.piece_data["color"] == by_color:
			# Проверяем базовую геометрию хода врага до этой клетки
			# Для пешек проверяем только удар по диагонали
			if cell.piece_data["type"] == "P":
				var dir = -1 if by_color == "w" else 1
				var diff_x = square.x - cell.grid_position.x
				var diff_y = square.y - cell.grid_position.y
				if abs(diff_x) == 1 and diff_y == dir:
					return true
			else:
				if is_move_base_legal(cell, cells_dict[get_name_by_grid(square.x, square.y)]):
					return true
	return false

func is_move_base_legal(from_cell: ColorRect, to_cell: ColorRect) -> bool:
	var piece = from_cell.piece_data
	if piece == null: return false
	var start = from_cell.grid_position
	var target = to_cell.grid_position
	var diff_x = target.x - start.x
	var diff_y = target.y - start.y
	if to_cell.piece_data != null and to_cell.piece_data["color"] == piece["color"]: return false
	match piece["type"]:
		"P": # === ПЕШКА (С учетом Взятия на проходе) ===
			var dir = -1 if piece["color"] == "w" else 1
			if diff_x == 0 and diff_y == dir: return to_cell.piece_data == null
			if diff_x == 0 and diff_y == dir * 2 and start.y == (6 if piece["color"] == "w" else 1):
				return to_cell.piece_data == null and cells_dict[get_name_by_grid(start.x, start.y + dir)].piece_data == null
			
			# Обычное взятие
			if abs(diff_x) == 1 and diff_y == dir: 
				if to_cell.piece_data != null: return true
				# Добавляем легальность взятия на проходе
				if target == en_passant_target_square: return true
			return false
		"N": return (abs(diff_x) == 1 and abs(diff_y) == 2) or (abs(diff_x) == 2 and abs(diff_y) == 1)
		"R": return (diff_x == 0 or diff_y == 0) and is_path_clear(start, target)
		"B": return abs(diff_x) == abs(diff_y) and is_path_clear(start, target)
		"Q": return (diff_x == 0 or diff_y == 0 or abs(diff_x) == abs(diff_y)) and is_path_clear(start, target)
		# Замени ветки "P" и "K" внутри match piece["type"]: в методе is_move_base_legal()

		"P": # === ПЕШКА (С учетом Взятия на проходе) ===
			var dir = -1 if piece["color"] == "w" else 1
			if diff_x == 0 and diff_y == dir: return to_cell.piece_data == null
			if diff_x == 0 and diff_y == dir * 2 and start.y == (6 if piece["color"] == "w" else 1):
				return to_cell.piece_data == null and cells_dict[get_name_by_grid(start.x, start.y + dir)].piece_data == null
			
			# Обычное взятие
			if abs(diff_x) == 1 and diff_y == dir: 
				if to_cell.piece_data != null: return true
				# Добавляем легальность взятия на проходе
				if target == en_passant_target_square: return true
			return false
			
		"K": # === КОРОЛЬ (Безопасная базовая геометрия) ===
			# Для проверки шахов и обычных прострелов король ходит ТОЛЬКО на 1 клетку вокруг себя
					if abs(diff_x) <= 1 and abs(diff_y) <= 1:
						return true
	return false

func is_path_clear(start: Vector2i, target: Vector2i) -> bool:
	var step = Vector2i(sign(target.x - start.x), sign(target.y - start.y))
	var curr = start + step
	while curr != target:
		if cells_dict[get_name_by_grid(curr.x, curr.y)].piece_data != null: return false
		curr += step
	return true

func get_cell_by_grid(col: int, row: int) -> ColorRect:
	return cells_dict[get_name_by_grid(col, row)]

func get_name_by_grid(col: int, row: int) -> String:
	return ["a","b","c","d","e","f","g","h"][col] + ["8","7","6","5","4","3","2","1"][row]

func show_promotion_menu(piece_color: String) -> void:
	if promotion_ui != null: promotion_ui.queue_free()
	promotion_ui = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("262421")
	style.set_border_width_all(2)
	style.border_color = Color("b58863")
	style.set_corner_radius_all(8)
	promotion_ui.add_theme_stylebox_override("panel", style)
	
	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 15)
	promotion_ui.add_child(h_box)
	
	var choices = ["Q", "R", "B", "N"]
	for i in range(choices.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(80, 80)
		btn.flat = true
		var icon_path = "res://assets/pieces/" + piece_color + choices[i] + ".svg"
		if ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
			btn.expand_icon = true
			
		# ИСПРАВЛЕНО: Вместо лямбды func() используем bind(), чтобы передать параметры в функцию безопасным путем
		btn.pressed.connect(_on_promotion_button_pressed.bind(choices[i], piece_color))
		h_box.add_child(btn)
		
	add_child(promotion_ui)
	promotion_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

# Новый промежуточный метод, который ловит нажатие конкретной кнопки
func _on_promotion_button_pressed(chosen_type: String, piece_color: String) -> void:
	_on_promotion_selected(chosen_type, piece_color)

func _on_promotion_selected(chosen_type: String, piece_color: String) -> void:
	if promotion_pending_cell != null: 
		promotion_pending_cell.set_piece(chosen_type, piece_color)
	if promotion_ui != null: 
		promotion_ui.queue_free()
		promotion_ui = null
	promotion_pending_cell = null
	complete_turn()

func show_game_over_screen(title: String, result: String) -> void:
	var game_over_ui = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("262421")
	style.set_border_width_all(3)
	style.border_color = Color("b58863")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(25)
	game_over_ui.add_theme_stylebox_override("panel", style)
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15)
	game_over_ui.add_child(v_box)
	var lbl_title = Label.new()
	lbl_title.text = title
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 32)
	v_box.add_child(lbl_title)
	var lbl_result = Label.new()
	lbl_result.text = result
	lbl_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_result.add_theme_font_size_override("font_size", 20)
	v_box.add_child(lbl_result)
	var btn_menu = Button.new()
	btn_menu.text = "В главное меню"
	btn_menu.custom_minimum_size = Vector2(200, 50)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color("b58863")
	btn_style.set_corner_radius_all(6)
	btn_menu.add_theme_stylebox_override("normal", btn_style)
	btn_menu.pressed.connect(_on_back_to_menu_pressed)
	v_box.add_child(btn_menu)
	add_child(game_over_ui)
	game_over_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _on_back_to_menu_pressed() -> void:
	moves_history.clear()
	position_history.clear()
	
	# Удаляем внешнюю разметку перед выходом
	var left_ranks = get_node_or_null("LeftRanks")
	var bottom_files = get_node_or_null("BottomFiles")
	if left_ranks: left_ranks.queue_free()
	if bottom_files: bottom_files.queue_free()
	
	get_tree().change_scene_to_file("res://main_menu.tscn")

# Проверка ничьей по недостатку материала (ФИДЕ)
func is_insufficient_material() -> bool:
	
	var white_pieces = []
	var black_pieces = []
	
	# Собираем все живые фигуры с доски
	for name in cells_dict:
		var cell = cells_dict[name]
		if cell.piece_data != null:
			if cell.piece_data["color"] == "w":
				white_pieces.append(cell.piece_data["type"])
			else:
				black_pieces.append(cell.piece_data["type"])
				
	# Если у кого-то есть тяжелые фигуры (Ферзь, Ладья) или Пешки — мат возможен
	for p in white_pieces + black_pieces:
		if p == "Q" or p == "R" or p == "P":
			return false
			
	# Убираем королей из подсчета, так как они есть всегда
	white_pieces.erase("K")
	black_pieces.erase("K")
	
	var w_count = white_pieces.size()
	var b_count = black_pieces.size()
	
	# Вариант 1: Король против Короля (на доске 0 фигур, кроме королей)
	if w_count == 0 and b_count == 0:
		return true
		
	# Вариант 2: Король + Слон или Король + Конь против одинокого Короля
	if (w_count == 1 and b_count == 0) and (white_pieces[0] == "B" or white_pieces[0] == "N"):
		return true
	if (b_count == 1 and w_count == 0) and (black_pieces[0] == "B" or black_pieces[0] == "N"):
		return true
		
	# Вариант 3: Король + Слон против Короля + Слона (того же цвета полей)
	# Для простоты в Альфе 0.0.1 считаем двух слонов ничьей. Если нужно супер-точно по полям — допишем в 0.0.2!
	if w_count == 1 and b_count == 1 and white_pieces[0] == "B" and black_pieces[0] == "B":
		return true
		
	return false

# Создает уникальную текстовую строку текущего состояния доски
func generate_position_snapshot() -> String:
	var snapshot = ""
	
	# 1. Записываем положение всех фигур
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	for row in range(8):
		for col in range(8):
			var cell = cells_dict[files[col] + ranks[row]]
			if cell.piece_data != null:
				snapshot += cell.piece_data["color"] + cell.piece_data["type"]
			else:
				snapshot += "."
		snapshot += "/"
		
	# 2. Записываем очередь хода и статус рокировок
	snapshot += "|" + current_turn
	snapshot += "|W:" + str(white_king_moved) + str(white_rook_a1_moved) + str(white_rook_h1_moved)
	snapshot += "|B:" + str(black_king_moved) + str(black_rook_a8_moved) + str(black_rook_h8_moved)
	snapshot += "|EP:" + str(en_passant_target_square)
	
	return snapshot
