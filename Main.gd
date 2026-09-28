extends Control

# === ПЕРЕМЕННЫЕ ДЛЯ ПРЕМУВОВ (v0.0.4.0) ===
var premove_from_cell: ColorRect = null
var premove_to_cell: ColorRect = null
var has_premove: bool = false
const COLOR_PREMOVE_HIGHLIGHT = Color("4b648a", 0.6) # Мягкий синий цвет подсветки Lichess
var player_color: String = "w" # Цвет игрока-человека (всегда "w" для Белых)

var ai_thinking_label: Label

# === ПЕРЕМЕННЫЕ ДЛЯ DRAG-AND-DROP (v0.0.4.0) ===
var is_dragging: bool = false
var dragged_piece_icon: TextureRect = null
var drag_start_cell: ColorRect = null
var is_drag_move: bool = false

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
@onready var sound_game_signal: AudioStreamPlayer = null
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

# Хранение клеток последнего хода для v0.0.3.0
var last_source_cell: ColorRect = null
var last_target_cell: ColorRect = null
# Хранение клетки короля под шахом для v0.0.3.0
var checked_king_cell: ColorRect = null

# Временное хранение параметров последнего полухода для логгера
var last_move_meta: Dictionary = {}

# === ПЕРЕМЕННЫЕ ДЛЯ PGN-ЛОГА (v0.0.3.0) ===
var pgn_history: Array[String] = []       # Массив для хранения истории ходов

@onready var history_label: RichTextLabel = $CenterContainer/GameLayout/SidePanel/HistoryLabel

func _ready() -> void:
	# 1. СИНХРОНИЗАЦИЯ ЦВЕТА И ОЧЕРЕДИ (v0.1.1.0)
	player_color = GameManager.actual_player_color
	current_turn = "w" # Белые всегда ходят первыми по правилам FIDE
	
	# 2. ГЕНЕРАЦИЯ ДОСКИ И ФИГУР (Строго один раз!)
	generate_board()
	setup_initial_pieces()
	
	# 3. НАСТРОЙКА ИМЕН НА ПАНЕЛЯХ (v0.1.1.0: Адаптировано под цвет игрока)
	if GameManager.game_mode == GameManager.Mode.AI:
		if player_color == "w":
			white_name_label.text = "You (White)"
			black_name_label.text = "Stockfish (" + str(GameManager.selected_elo) + " ELO)"
		else:
			white_name_label.text = "Stockfish (" + str(GameManager.selected_elo) + " ELO)"
			black_name_label.text = "You (Black)"
	else:
		# Для локальной игры оставляем стандарт
		white_name_label.text = "Player 1 (White)"
		black_name_label.text = "Player 2 (Black)"
		
	# 4. НАСТРОЙКА ТАЙМЕРОВ
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
	
	# 5. АВТО-ПОДКЛЮЧЕНИЕ СИГНАЛА КНОПКИ PGN
	if has_node("CenterContainer/GameLayout/SidePanel/CopyPNGButton"):
		$CenterContainer/GameLayout/SidePanel/CopyPNGButton.pressed.connect(_on_copy_pgn_button_pressed)
		print("--- GiChess: Сигнал кнопки копирования успешно привязан! ---")
	
	# 6. ИНИЦИАЛИЗАЦИЯ И ЗАПУСК ЗВУКА СТАРТА
	sound_game_signal = AudioStreamPlayer.new()
	sound_game_signal.stream = load("res://assets/sounds/game_signal.mp3") 
	add_child(sound_game_signal)
	
	if is_instance_valid(sound_game_signal):
		sound_game_signal.play()
	
		# 7. СОЗДАНИЕ ИНДИКАТОРА РАЗМЫШЛЕНИЙ ИИ (v0.1.1.0 - с динамической позицией)
	ai_thinking_label = Label.new()
	ai_thinking_label.text = "• Stockfish is thinking..."
	ai_thinking_label.visible = false 
	ai_thinking_label.add_theme_color_override("font_color", Color(0.0, 0.26, 0.73))
	
	# Ссылаемся на SidePanel по одному из твоих путей сцены
	var side_panel_node: VBoxContainer = null
	if has_node("CenterContainer/GameLayout/SidePanel"):
		side_panel_node = $CenterContainer/GameLayout/SidePanel
	elif has_node("SidePanel"):
		side_panel_node = $SidePanel
		
	if side_panel_node:
		side_panel_node.add_child(ai_thinking_label)
		
		# Задаем индекс положения индикатора на панели (v0.1.1.0)
		# 3 — если игрок за Черных (ИИ вверху), 4 — если игрок за Белых (ИИ внизу)
		var target_index: int = 4 if player_color == "b" else 3
		
		# Защита: проверяем, что в контейнере достаточно элементов, чтобы не выйти за границы
		if side_panel_node.get_child_count() > target_index:
			side_panel_node.move_child(ai_thinking_label, target_index)
		print("--- GiChess: Индикатор добавлен в SidePanel на индекс: ", target_index, " ---")
	else:
		add_child(ai_thinking_label) 
		print("--- GiChess ВНИМАНИЕ: SidePanel не найдена, индикатор добавлен в корень ---")

	# 8. ТРИГГЕР ПЕРВОГО ХОДА ИИ (v0.1.1.0)
	# Если игра против бота И игрок выбрал Черных — ИИ делает стартовый ход за Белых
	if GameManager.game_mode == GameManager.Mode.AI and player_color == "b":
		print("--- GiChess: Игрок за Черных. СТОКФИШ ДЕЛАЕТ ПЕРВЫЙ ХОД ЗА БЕЛЫХ ---")
		is_ai_thinking = true
		
		# ИСПРАВЛЕНО (v0.1.1.0): Используем правильный метод Godot 4 для добавления задачи в пул
		WorkerThreadPool.add_task(call_stockfish_process)
	
		# 9. КНОПКА ПЕРЕВОРОТА ДОСКИ ДЛЯ ЛОКАЛЬНОЙ ИГРЫ (v0.1.2.0)
	# Показываем кнопку только в локальном режиме, в режиме ИИ она не нужна
	if GameManager.game_mode == GameManager.Mode.LOCAL:
		var flip_button = Button.new()
		flip_button.text = "Flip Board"
		flip_button.name = "FlipBoardButton"
		
		if has_node("CenterContainer/GameLayout/SidePanel"):
			side_panel_node = $CenterContainer/GameLayout/SidePanel
		elif has_node("SidePanel"):
			side_panel_node = $SidePanel
			
		if side_panel_node:
			side_panel_node.add_child(flip_button)
			# Подключаем нажатие кнопки к новой функции
			flip_button.pressed.connect(_on_flip_board_pressed)
			print("--- GiChess: Кнопка 'Flip Board' успешно добавлена в SidePanel! ---")

func _on_resign_pressed() -> void:
	game_over = true
	show_game_over_screen("DEFEAT", "You resigned")

func _on_timer_tick() -> void:
	if game_over: return
	
	if current_turn == "w":
		white_time_left -= 1.0
		if white_time_left <= 0:
			game_over = true
			show_game_over_screen("TIME IS UP", "Black Wins!")
	else:
		black_time_left -= 1.0
		if black_time_left <= 0:
			game_over = true
			show_game_over_screen("TIME IS UP", "White Wins!")
			
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
	
	# Флаг переворота: доска переворачивается, если реальный цвет игрока — Черные ("b")
	var is_flipped: bool = (GameManager.actual_player_color == "b")
	
	for row in range(8):
		for col in range(8):
			# Безопасный математический переворот индексов для отрисовки сетки GridContainer
			var render_row = (7 - row) if is_flipped else row
			var render_col = (7 - col) if is_flipped else col
			
			var cell = cell_scene.instantiate()
			
			# Цвет клетки зависит от физического положения (row + col),
			# чтобы левый нижний угол для белых/черных всегда оставался темным по правилам FIDE
			var current_color = light_color if (row + col) % 2 == 0 else dark_color
			
			# Шахматное имя (например, "a1") и логическая позиция привязываются строго к рендер-индексам
			var chess_name = files[render_col] + ranks[render_row]
			var grid_pos = Vector2i(render_col, render_row)
			
			cell.setup(grid_pos, chess_name, current_color)
			cell.name = chess_name
			cell.cell_clicked.connect(_on_cell_clicked)
			
			board.add_child(cell)
			cells_dict[chess_name] = cell
			
	# Ждем окончания кадра отрисовки интерфейса, чтобы узнать точные экранные координаты доски
	await get_tree().process_frame
	
	# Разворачиваем буквенные и цифры разметки, чтобы они совпали с перевернутой доской
	var display_ranks = ranks.duplicate()
	var display_files = files.duplicate()
	if is_flipped:
		display_ranks.reverse()
		display_files.reverse()
		
	create_external_notation(display_ranks, display_files)
	print("--- GiChess: Доска успешно создана! [Переворот для Черных: ", is_flipped, "] ---")


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
			if piece_char == ".": 
				continue
				
			var piece_color = "w" if piece_char == piece_char.to_upper() else "b"
			var piece_type = piece_char.to_upper()
			
			# Фигуры всегда считываются из стандартного массива по индексам [row][col] 
			# и железно привязываются к своим законным именам (например, e1, d8).
			var chess_name = files[col] + ranks[row]
			
			# Благодаря cells_dict фигура встанет на клетку с этим именем, 
			# где бы эта клетка физически ни находилась на экране после переворота!
			if cells_dict.has(chess_name):
				cells_dict[chess_name].set_piece(piece_type, piece_color)

func _on_cell_clicked(_grid_pos: Vector2i, chess_coordinate: String) -> void:
	if game_over: return
	var clicked_cell = cells_dict[chess_coordinate]
	
	# А) НАШ ХОД (или любой ход в ЛОКАЛЬНОЙ игре)
	if current_turn == player_color or GameManager.game_mode == GameManager.Mode.LOCAL:
		if is_ai_thinking: return # Защита от кликов, пока ИИ думает над своим ходом
		
		if selected_cell == null:
			if clicked_cell.piece_data != null and clicked_cell.piece_data["color"] == current_turn:
				select_cell(clicked_cell)
				start_drag(clicked_cell)
		else:
			if selected_cell == clicked_cell:
				deselect_all()
				return
			if clicked_cell.piece_data != null and clicked_cell.piece_data["color"] == current_turn:
				deselect_all()
				select_cell(clicked_cell)
				start_drag(clicked_cell)
				return
			if is_move_completely_legal(selected_cell, clicked_cell):
				var uci_move = selected_cell.chess_coordinate + clicked_cell.chess_coordinate
				moves_history.append(uci_move)
				make_move(selected_cell, clicked_cell)
				
		# Б) ХОД ИИ STOCKFISH (Планирование премува кликами в режиме AI)
	else:
		if GameManager.game_mode == GameManager.Mode.AI:
			if selected_cell == null:
				if clicked_cell.piece_data != null and clicked_cell.piece_data["color"] == player_color:
					select_cell(clicked_cell)
					start_drag(clicked_cell)
			else:
				if selected_cell == clicked_cell:
					deselect_all()
					return
				
				# ХИТРОСТЬ v0.0.4.0: Если кликнули на свою фигуру, проверяем — умеет ли выбранная фигура туда ходить геометрически?
				if clicked_cell.piece_data != null and clicked_cell.piece_data["color"] == player_color:
					if is_move_base_legal(selected_cell, clicked_cell):
						# Если базовая геометрия позволяет (например, конь прыгает буквой Г на свою пешку) — ЗАПИСЫВАЕМ ПРЕМУВ!
						set_premove(selected_cell, clicked_cell)
						deselect_all()
						return
					else:
						# Если геометрия не позволяет — значит игрок просто хочет перевыбрать фигуру
						deselect_all()
						select_cell(clicked_cell)
						start_drag(clicked_cell)
						return
				
				# Если кликнули на пустую клетку или вражескую фигуру
				if selected_cell != clicked_cell:
					set_premove(selected_cell, clicked_cell)
				deselect_all()

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
	# Защита v0.1.1.0: Если фигура почему-то не найдена на стартовой клетке, прерываем логику во избежание краша
	if moving_piece == null:
		print("--- GiChess ОШИБКА: Попытка сделать ход пустой фигурой со стартовой клетки! ---")
		return
		
	# === ЛОГИКА ВЗЯТИЯ НА ПРОХОДЕ (Удаление врага) ===
	if moving_piece["type"] == "P" and target == en_passant_target_square:
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

		# === АНИМАЦИЯ ПЕРЕМЕЩЕНИЯ ФИГУРЫ (v0.0.3.0 / Исправление раздвоения v0.0.4.0) ===
	var piece_texture = from_cell.get_piece_texture()
	
	# СЛУЧАЙ 1: Ход через Drag-and-Drop — переставляем мгновенно и ЧИСТИМ старую клетку!
	if is_drag_move:
		to_cell.set_piece(moving_piece["type"], moving_piece["color"])
		from_cell.clear_piece()
		print("--- GiChess: Ход выполнен через Drag-and-Drop без раздвоения ---")
		
	# СЛУЧАЙ 2: Обычный клик или ход ИИ — работает старый добрый плавный Твин
	elif piece_texture:
		# 1. Создаем временную иконку на доске для плавного полета
		var temp_icon = TextureRect.new()
		temp_icon.texture = piece_texture
		temp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		temp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		temp_icon.size = from_cell.size
		temp_icon.global_position = from_cell.global_position
		add_child(temp_icon)
		
		from_cell.set_piece_icon_visible(false)
		from_cell.clear_piece()
		from_cell.set_piece_icon_visible(true)
		
		to_cell.set_piece_icon_visible(false)
		
		# 2. Настраиваем и запускаем Твин
		var tween = create_tween()
		tween.tween_property(temp_icon, "global_position", to_cell.global_position, 0.18)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)
			
		await tween.finished
		
		# 3. Фигура долетела
		to_cell.set_piece_icon_visible(true)
		to_cell.set_piece(moving_piece["type"], moving_piece["color"])
		temp_icon.queue_free()
	else:
		to_cell.set_piece(moving_piece["type"], moving_piece["color"])
		from_cell.clear_piece()

	# === ОБНОВЛЕНИЕ СЧЕТЧИКА ДЛЯ ПРАВИЛА 50 ХОДОВ ===
	if moving_piece["type"] == "P" or is_capture:
		halfmove_clock = 0 
	else:
		halfmove_clock += 1 
	print("Полуходов без взятий и пешек: ", halfmove_clock)

		# === ЗВУК ИГРАЕТ В МОМЕНТ ПРИЗЕМЛЕНИЯ ИЛИ МГНОВЕННО ПРИ ПРЕМУВЕ (v0.0.4.0) ===
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

	# === СБРОС ВЫДЕЛЕНИЯ И ВКЛЮЧЕНИЕ ПОДСВЕТКИ ХОДА ===
	deselect_all()
	update_move_highlight(from_cell, to_cell)
	
	# Превращение пешки
	if moving_piece["type"] == "P" and (to_cell.grid_position.y == 0 or to_cell.grid_position.y == 7):
		promotion_pending_cell = to_cell
		if GameManager.game_mode == GameManager.Mode.AI and current_turn == "b":
			_on_promotion_selected("Q", "b")
		else:
			show_promotion_menu(moving_piece["color"])
		return
	
	# === ЗАПОМИНАЕМ ХОД ДЛЯ PGN-ЛОГА (v0.0.3.0) ===
	last_move_meta = {
		"piece": moving_piece.duplicate(),
		"start": start,
		"target": target,
		"is_capture": is_capture
	}

	# === ЗАПИСЬ СЛЕПКА ПОЗИЦИИ ДЛЯ ПРАВИЛА 3 ХОДОВ ===
	var current_snapshot = generate_position_snapshot()
	position_history.append(current_snapshot)
	
	complete_turn()
## Дополнительная функция для менеджмента подсветки
func update_move_highlight(from_cell: ColorRect, to_cell: ColorRect) -> void:
	# 1. Сбрасываем старую подсветку, если клетки существуют
	if is_instance_valid(last_source_cell):
		last_source_cell.reset_highlight()
	if is_instance_valid(last_target_cell):
		last_target_cell.reset_highlight()
	
	# 2. Запоминаем текущие клетки хода
	last_source_cell = from_cell
	last_target_cell = to_cell
	
	# 3. Включаем новую подсветку
	last_source_cell.highlight_last_move()
	last_target_cell.highlight_last_move()

func complete_turn() -> void:
	# === ВЫЧИСЛЕНИЕ СТАТУСА ШАХА И МАТА ДЛЯ PGN-ЛОГА (v0.0.3.0) ===
	# Так как текущий игрок ТОЛЬКО ЧТО сделал ход, мы проверяем, 
	# объявил ли этот ход ШАХ или МАТ вражескому королю (оппоненту).
	var opponent_color = "b" if current_turn == "w" else "w"
	var opponent_king_in_check = is_king_in_check(opponent_color)
	var opponent_has_moves = has_any_legal_moves(opponent_color)
	var is_mate_announced = opponent_king_in_check and not opponent_has_moves

	# Генерация нотации и запись хода в массив истории
	if not last_move_meta.is_empty():
		var move_str = generate_move_notation(
			last_move_meta["piece"], 
			last_move_meta["start"], 
			last_move_meta["target"], 
			last_move_meta["is_capture"],
			opponent_king_in_check,
			is_mate_announced
		)
		pgn_history.append(move_str)
		update_history_ui()
		last_move_meta.clear() # Очищаем временный контейнер полухода

	# === ОФИЦИАЛЬНАЯ СМЕНА ОЧЕРЕДИ ХОДА ===
	current_turn = opponent_color
	
	# 1. Проверяем классический Мат и Пат (уже для нового игрока)
	var has_moves = opponent_has_moves
	var king_in_check = opponent_king_in_check
	
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
		
	# === ПРОВЕРКА ТРЕХКРАТНОГО ПОВТОРЕНИЯ ПОЗИЦИИ ===
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
		
		# === ОБНОВЛЕНИЕ ПОДСВЕТКИ ШАХА (Исправлено в v0.0.5.0 для взятий) ===
	# Перепроверяем шах заново: теперь, когда фигура точно приземлилась, данные на доске стабильны
	king_in_check = is_king_in_check(current_turn)
	
	if king_in_check:
		print("Внимание: Королю объявлен ШАХ!")
		# Ищем короля, которому объявили шах, и красим в красный
		for chess_name in cells_dict:
			var cell = cells_dict[chess_name]
			if cell.piece_data and cell.piece_data["type"] == "K" and cell.piece_data["color"] == current_turn:
				checked_king_cell = cell
				checked_king_cell.highlight_check()
				break
	else:
		# Если шаха НЕТ, принудительно убираем красный цвет с прошлого короля
		if is_instance_valid(checked_king_cell):
			checked_king_cell.reset_highlight()
			
			# Защита: если этот король только что ушел из-под шаха (последний ход),
			# возвращаем его клетке правильный желтый цвет последнего хода!
			if checked_king_cell == last_source_cell or checked_king_cell == last_target_cell:
				checked_king_cell.highlight_last_move()
				
			checked_king_cell = null
			
			# Защита: если этот король только что ушел из-под шаха (последний ход),
			# возвращаем его клетке правильный желтый цвет последнего хода!
			if checked_king_cell == last_source_cell or checked_king_cell == last_target_cell:
				checked_king_cell.highlight_last_move()
				
			checked_king_cell = null
		
			# === ИСПРАВЛЕНИЕ v0.1.1.0: АВТО-ХОД ИИ ПОД ЛЮБОЙ ЦВЕТ СТОРОНЫ ===
	# Запускаем Stockfish только если наступил НЕ ход игрока (current_turn != player_color)
	if GameManager.game_mode == GameManager.Mode.AI and current_turn != player_color and not game_over:
		print("--- GiChess: Ход перешел к ИИ. Запуск Stockfish за сторону: ", current_turn, " ---")
		get_ai_move()

			# === ОБНОВЛЕНИЕ ТОЧЕК ХОДА ПРИ DRAG-AND-DROP ВО ВРЕМЯ ХОДА ИИ (v0.0.4.0) ===
	# Если в момент хода ИИ игрок держит фигуру в руках — заново рисуем для неё серые точки ходов!
	if is_dragging and is_instance_valid(drag_start_cell):
		select_cell(drag_start_cell)
		
			# === АВТО-ИСПОЛНЕНИЕ ПРЕМУВА С СОЧНОЙ ПАУЗОЙ (v0.0.4.0) ===
	if current_turn == player_color and has_premove and not game_over:
		var p_from = premove_from_cell
		var p_to = premove_to_cell
		
		# Мгновенно очищаем буфер и синюю подсветку премува перед ожиданием
		cancel_premove()
		
		# Делаем микро-паузу в 0.12 секунды, чтобы игрок увидел ход ИИ и услышал первый щелчок!
		await get_tree().create_timer(0.10).timeout
		
		# Защита: проверяем, не завершилась ли игра или не удалилась ли сцена за время паузы
		if game_over or not is_instance_valid(self) or not is_instance_valid(p_from) or not is_instance_valid(p_to):
			return
		
		# Теперь проверяем легальность нашего хода в наступившей позиции
		if is_move_completely_legal(p_from, p_to):
			print("⚡ GiChess: Премув легален! Авто-исполнение после микро-паузы.")
			var uci_move = p_from.chess_coordinate + p_to.chess_coordinate
			moves_history.append(uci_move)
			
			# Запускаем ход без Твин-анимации, так как задержку мы уже выдержали искусственно!
			is_drag_move = true
			make_move(p_from, p_to)
			is_drag_move = false
		else:
			print("❌ GiChess: Премув стал нелегальным и был автоматически отменен.")

func get_ai_move() -> void:
	is_ai_thinking = true
	var thread = Thread.new()
	thread.start(call_stockfish_process)

func call_stockfish_process() -> String:
	# БЕЗОПАСНОСТЬ 1: Проверяем, жива ли еще сцена доски, пока создавался поток
	if not is_instance_valid(self): return ""
	
	# ВКЛЮЧАЕМ ИНДИКАТОР: Stockfish начинает думать (v0.1.1.0)
	if is_instance_valid(ai_thinking_label):
		ai_thinking_label.call_deferred("set_visible", true)
	
	var path_to_exe = ProjectSettings.globalize_path("res://bin/stockfish.exe")
	if OS.get_name() == "macOS" or OS.get_name() == "Linux":
		path_to_exe = ProjectSettings.globalize_path("res://bin/stockfish")
		
	if not FileAccess.file_exists(path_to_exe):
		if is_instance_valid(self):
			# ВЫКЛЮЧАЕМ ИНДИКАТОР при ошибке
			if is_instance_valid(ai_thinking_label):
				ai_thinking_label.call_deferred("set_visible", false)
			call_deferred("_on_ai_move_received", "")
		return ""
		
	var pipes = OS.execute_with_pipe(path_to_exe, [])
	
	# БЕЗОПАСНОСТЬ 2: Защита от краша "Index out of bounds (size() = 0)". 
	# Если пайпы пустые или в них нет stdio — не трогаем их и выходим!
	if pipes.is_empty() or not pipes.has("stdio"):
		print("--- GiChess ОШИБКА: Каналы связи со Stockfish не были открыты ОС ---")
		if is_instance_valid(self):
			# ВЫКЛЮЧАЕМ ИНДИКАТОР при ошибке
			if is_instance_valid(ai_thinking_label):
				ai_thinking_label.call_deferred("set_visible", false)
			call_deferred("_on_ai_move_received", "")
		return ""
		
	var pipe_in = pipes["stdio"]
	
	pipe_in.store_line("setoption name UCI_LimitStrength value true")
	pipe_in.store_line("setoption name UCI_Elo value " + str(GameManager.selected_elo))
	
	var position_cmd = "position startpos"
	if moves_history.size() > 0:
		position_cmd += " moves " + " ".join(moves_history)
	
	pipe_in.store_line(position_cmd)
	
	var wtime_ms = int(white_time_left * 1000)
	var btime_ms = int(black_time_left * 1000)
	
	if moves_history.size() < 12:
		var debut_time = 1500
		pipe_in.store_line("go wtime " + str(wtime_ms) + " btime " + str(btime_ms) + " movetime " + str(debut_time))
	else:
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
	
	# ВЫКЛЮЧАЕМ ИНДИКАТОР: Stockfish закончил думать (v0.1.1.0)
	if is_instance_valid(ai_thinking_label):
		ai_thinking_label.call_deferred("set_visible", false)
	
	# БЕЗОПАСНОСТЬ 3: Передаем ход в GUI, только если игрок еще не закрыл доску и не вышел в меню
	if is_instance_valid(self):
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
	# Единый сигнал завершения матча (v0.1.1.0)
	if is_instance_valid(sound_game_signal):
		sound_game_signal.play()
	# === АВТОМАТИЧЕСКИЙ ПЕРЕВОД ДЛЯ МЕЖДУНАРОДНОГО РЕЛИЗА (v0.0.5.0) ===
	var eng_title = title
	if title == "МАТ": eng_title = "CHECKMATE"
	elif title == "ПАТ": eng_title = "STALEMATE"
	elif title == "НИЧЬЯ": eng_title = "DRAW"
	
	var eng_result = result
	if result == "Белые победили!": eng_result = "White Wins!"
	elif result == "Черные победили!": eng_result = "Black Wins!"
	elif result == "Ничья": eng_result = "Draw"
	elif result.contains("Правило 50 ходов"): eng_result = "Draw (50-move rule)"
	elif result.contains("3-кратное повторение"): eng_result = "Draw (3fold repetition)"
	elif result.contains("Недостаточно материала"): eng_result = "Draw (Insufficient material)"

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
	lbl_title.text = eng_title
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 32)
	v_box.add_child(lbl_title)
	
	var lbl_result = Label.new()
	lbl_result.text = eng_result
	lbl_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_result.add_theme_font_size_override("font_size", 20)
	v_box.add_child(lbl_result)
	
	# === КНОПКА: В ГЛАВНОЕ МЕНЮ (МЕЖДУНАРОДНАЯ) ===
	var btn_menu = Button.new()
	btn_menu.text = "Main Menu"
	btn_menu.custom_minimum_size = Vector2(200, 50)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color("b58863")
	btn_style.set_corner_radius_all(6)
	btn_menu.add_theme_stylebox_override("normal", btn_style)
	btn_menu.pressed.connect(_on_back_to_menu_pressed)
	v_box.add_child(btn_menu)
	
	# === КНОПКА: АНАЛИЗИРОВАТЬ ПАРТИЮ (МЕЖДУНАРОДНАЯ) ===
	if moves_history.size() > 0:
		var btn_analyze = Button.new()
		btn_analyze.text = "Analyze Game"
		btn_analyze.custom_minimum_size = Vector2(200, 50)
		
		var btn_analyze_style = StyleBoxFlat.new()
		btn_analyze_style.bg_color = Color("4b648a") # Наш фирменный синий для отличия
		btn_analyze_style.set_corner_radius_all(6)
		btn_analyze.add_theme_stylebox_override("normal", btn_analyze_style)
		
		btn_analyze.pressed.connect(_on_analyze_pressed)
		v_box.add_child(btn_analyze)
	
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

func _on_analyze_pressed() -> void:
	# Копируем историю текущей партии в GameManager, чтобы сцена анализа её подхватила
	GameManager.last_moves_history = moves_history.duplicate()
	GameManager.last_pgn_history = pgn_history.duplicate()
	
	# Меняем сцену на комнату анализа
	get_tree().change_scene_to_file("res://analysis_room.tscn")

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

## Проверяет и подсвечивает короля, если ему объявлен шах
func update_check_highlight() -> void:
	# 1. Сначала всегда сбрасываем прошлую подсветку шаха, если она была
	if is_instance_valid(checked_king_cell):
		checked_king_cell.reset_highlight()
		# Важный нюанс: если клетка короля была частью последнего хода, возвращаем ей желтый цвет!
		if checked_king_cell == last_source_cell or checked_king_cell == last_target_cell:
			checked_king_cell.highlight_last_move()
		checked_king_cell = null
		
	# 2. Проверяем, есть ли шах текущему игроку (или вообще на доске)
	# Предполагаем, что у тебя в коде есть переменная current_turn ("w" или "b")
	if is_king_in_check(current_turn):
		# Ищем клетку, где физически стоит этот король
		for chess_name in cells_dict:
			var cell = cells_dict[chess_name]
			if cell.piece_data and cell.piece_data["type"] == "K" and cell.piece_data["color"] == "w" if current_turn == "w" else cell.piece_data["color"] == "b":
				checked_king_cell = cell
				checked_king_cell.highlight_check()
				break

## Генерирует эталонную шахматную нотацию (например: e4, Nf3+, O-O, Bxf7#)
func generate_move_notation(moving_piece: Dictionary, start: Vector2i, target: Vector2i, is_capture: bool, is_check: bool, is_mate: bool) -> String:
	# 1. Обработка рокировки (Строго через английскую букву O)
	if moving_piece["type"] == "K" and abs(target.x - start.x) == 2:
		var castle_str = "O-O" if target.x == 6 else "O-O-O"
		if is_mate: return castle_str + "#"
		if is_check: return castle_str + "+"
		return castle_str
			
	# 2. Буквенное обозначение фигуры
	var piece_letter = ""
	match moving_piece["type"]:
		"N": piece_letter = "N"
		"B": piece_letter = "B"
		"R": piece_letter = "R"
		"Q": piece_letter = "Q"
		"K": piece_letter = "K"
		"P": piece_letter = ""
		
	# 3. Координаты поля
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	var target_coord = files[target.x] + ranks[target.y]
	
	# 4. Обработка взятия
	var capture_sign = ""
	if is_capture:
		capture_sign = "x"
		if moving_piece["type"] == "P":
			piece_letter = files[start.x] # пешка при взятии указывает свою вертикаль (exd5)
			
	var base_notation = piece_letter + capture_sign + target_coord
	
	# 5. Приоритет суффиксов
	if is_mate:
		return base_notation + "#"
	elif is_check:
		return base_notation + "+"
		
	return base_notation

## Обновляет RichTextLabel на боковой панели с поддержкой скролла и кастомным цветом текста
func update_history_ui() -> void:
	if not is_instance_valid(history_label):
		return
		
	# Принудительно включаем поддержку BBCode, чтобы работали теги цвета
	history_label.bbcode_enabled = true
		
	var text = ""
	var move_num = 1
	
	# Проходим по истории ходов парами (Ход белых + Ход черных)
	for i in range(0, pgn_history.size(), 2):
		var white_move = pgn_history[i]
		var black_move = ""
		
		if i + 1 < pgn_history.size():
			black_move = pgn_history[i + 1]
			
		# Форматируем ходы вертикальным списком
		text += str(move_num) + ". " + white_move + " " + black_move + "\n"
		move_num += 1
		
	# Оборачиваем весь текст в BBCode-тег цвета #161512 для идеального контраста
	history_label.text = "[color=#161512]" + text + "[/color]"

## Вызывается при нажатии на кнопку "Копировать PGN"
func _on_copy_pgn_button_pressed() -> void:
	print("--- Кнопка нажата! Начинаю сборку PGN ---") # Если эта строка появится в консоли, значит клик сработал!
	
	if pgn_history.is_empty():
		print("История ходов пуста, копировать нечего.")
		return
		
	var pgn_export_text = ""
	var move_num = 1
	
	for i in range(0, pgn_history.size(), 2):
		var white_move = pgn_history[i]
		var black_move = ""
		
		if i + 1 < pgn_history.size():
			black_move = pgn_history[i + 1]
			
		if black_move != "":
			pgn_export_text += str(move_num) + ". " + white_move + " " + black_move + " "
		else:
			pgn_export_text += str(move_num) + ". " + white_move + " "
			
		move_num += 1
		
	var final_pgn = pgn_export_text.strip_edges()
	
	# Копируем в буфер обмена операционной системы
	DisplayServer.clipboard_set(final_pgn)
	
	print("ЖЕЛЕЗОБЕТОННО СКОПИРОВАНО В БУФЕР: ", final_pgn)

# === СИСТЕМА ПЕРЕМЕЩЕНИЯ ФИГУР (v0.0.4.0) ===

func _process(_delta: float) -> void:
	# Если фигура зажата — плавно двигаем временную иконку за курсором
	if is_dragging and dragged_piece_icon and is_instance_valid(dragged_piece_icon):
		dragged_piece_icon.global_position = get_global_mouse_position() - dragged_piece_icon.size / 2

func _input(event: InputEvent) -> void:
	if game_over: return
	
	# ОТПУСКАНИЕ МЫШКИ (Drop)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_dragging:
			end_drag()

func start_drag(cell: ColorRect) -> void:
	is_dragging = true
	drag_start_cell = cell
	
	dragged_piece_icon = TextureRect.new()
	dragged_piece_icon.texture = cell.get_piece_texture()
	dragged_piece_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dragged_piece_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dragged_piece_icon.size = cell.size
	dragged_piece_icon.z_index = 100
	add_child(dragged_piece_icon)
	
	cell.set_piece_icon_visible(false)

func end_drag() -> void:
	is_dragging = false
	var target_cell = get_cell_under_mouse()
	
	if is_instance_valid(drag_start_cell):
		drag_start_cell.set_piece_icon_visible(true)
		
	if dragged_piece_icon and is_instance_valid(dragged_piece_icon):
		dragged_piece_icon.queue_free()
		dragged_piece_icon = null
	
	if target_cell and target_cell != drag_start_cell:
		# УМНОЕ УСЛОВИЕ (v0.0.4.0): Ход засчитывается, если сейчас очередь игрока-человека 
		# ИЛИ если включен режим локальной игры на одном устройстве (тогда ходить можно за оба цвета!)
		if current_turn == player_color or GameManager.game_mode == GameManager.Mode.LOCAL:
			if is_move_completely_legal(drag_start_cell, target_cell):
				var uci_move = drag_start_cell.chess_coordinate + target_cell.chess_coordinate
				moves_history.append(uci_move)
				cancel_premove()
				is_drag_move = true
				make_move(drag_start_cell, target_cell)
				is_drag_move = false
			else:
				deselect_all()
				
		# СЛУЧАЙ Б: СЕЙЧАС ХОД ИИ STOCKFISH (Запись Премува!)
		else:
			if GameManager.game_mode == GameManager.Mode.AI:
				if drag_start_cell != target_cell:
					set_premove(drag_start_cell, target_cell)
			deselect_all()
			
	drag_start_cell = null

# Сканируем, над какой клеткой находится мышь
func get_cell_under_mouse() -> ColorRect:
	for chess_name in cells_dict:
		var cell = cells_dict[chess_name]
		if is_instance_valid(cell) and cell.get_global_rect().has_point(get_global_mouse_position()):
			return cell
	return null

# === СИСТЕМА УПРАВЛЕНИЯ ПРЕМУВАМИ (v0.0.4.0) ===

func set_premove(from_cell: ColorRect, to_cell: ColorRect) -> void:
	cancel_premove() # Сбрасываем предыдущий премув
	
	premove_from_cell = from_cell
	premove_to_cell = to_cell
	has_premove = true
	
	# Используем дефер, чтобы покрасить клетки строго ПОСЛЕ завершения всех системных событий драга
	call_deferred("_apply_premove_colors")

func _apply_premove_colors() -> void:
	if has_premove and is_instance_valid(premove_from_cell) and is_instance_valid(premove_to_cell):
		premove_from_cell.color = COLOR_PREMOVE_HIGHLIGHT
		premove_to_cell.color = COLOR_PREMOVE_HIGHLIGHT
		print("--- GiChess: Премув зафиксирован! Старт и финиш принудительно синие ---")

func cancel_premove() -> void:
	if has_premove:
		if is_instance_valid(premove_from_cell): premove_from_cell.reset_highlight()
		if is_instance_valid(premove_to_cell): premove_to_cell.reset_highlight()
		
		premove_from_cell = null
		premove_to_cell = null
		has_premove = false

func _on_flip_board_pressed() -> void:
	if game_over: return
	
	# Меняем логический цвет отображения на противоположный
	if GameManager.actual_player_color == "w":
		GameManager.actual_player_color = "b"
	else:
		GameManager.actual_player_color = "w"
		
	# Синхронизируем локальную переменную цвета
	player_color = GameManager.actual_player_color
	
	# Шахматная хитрость: перед перегенерацией сетки нам нужно сохранить текущую позицию фигур!
	# Создаем временную карту текущего расположения фигур на доске
	var current_position_map = {}
	for chess_name in cells_dict:
		var cell = cells_dict[chess_name]
		if cell.piece_data != null:
			current_position_map[chess_name] = cell.piece_data.duplicate()
			
	print("--- GiChess: Переворот доски... Сохранено фигур для переноса: ", current_position_map.size(), " ---")
	
	# Полностью пересоздаем клетки и внешнюю разметку нотации с новым направлением
	await generate_board()
	
	# Расставляем фигуры обратно на их законные места, но уже в новые физические координаты сетки
	for chess_name in current_position_map:
		var p_data = current_position_map[chess_name]
		if cells_dict.has(chess_name):
			cells_dict[chess_name].set_piece(p_data["type"], p_data["color"])
			
	print("--- GiChess: Доска успешно перевернута в локальном режиме! ---")
