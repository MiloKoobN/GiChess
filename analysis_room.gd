extends Control

# Переменные для живого анализа (v0.1.1.0)
var is_ai_thinking: bool = false
var ai_thinking_label: Label = null

# Базовые пути доски, которые точно есть в сцене
@onready var board: GridContainer = $CenterContainer/GameLayout/AspectRatioContainer/BoardWrapper/Board

var is_ui_log_updating: bool = false # Защита от слишком частых обновлений текста

# Динамические ноды, создаваемые из кода для безопасности путей
var history_label: RichTextLabel = null
var eval_bar: ProgressBar = null
var eval_display_label: Label = null
var eval_center_line: ColorRect = null
var arrow_overlay: Control = null

# Кнопки навигации для авто-блокировки
var btn_back: Button = null
var btn_forward: Button = null

# Переменные для двухфазного анализа (v0.0.5.0)
var analyzed_scores: Array = []
var analysis_move_labels: Array = []
var best_moves_history: Array[String] = []
var current_analysis_step: int = 0 
var current_best_move_arrow: Dictionary = {}

# Твин для плавной шкалы преимущества
var bar_tween: Tween = null

# Локальные копии истории, переданные из игры
var moves_history: Array[String] = []
var pgn_history: Array[String] = []

@export var cell_scene: PackedScene = preload("res://cell.tscn")
@export var light_color: Color = Color("f0d9b5")
@export var dark_color: Color = Color("b58863")

var cells_dict = {}

# Стартовая расстановка фигур для воссоздания позиции
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

func _ready() -> void:
	# 1. ЗАГРУЗКА ИСТОРИИ ИЗ МАТЧА
	moves_history = GameManager.last_moves_history
	pgn_history = GameManager.last_pgn_history
	
	# 2. БАЗОВАЯ ИНИЦИАЛИЗАЦИЯ ИНТЕРФЕЙСА
	setup_evaluation_bar()
	setup_navigation_buttons()
	generate_board()
	
	start_analysis()
	
	# === ХАК v0.1.2.0: АБСОЛЮТНОЕ ОГРАНИЧЕНИЕ КНОПКИ FLIP BOARD ===
	# Защита: если старая кнопка где-то зависла, удаляем её перед созданием
	var old_btn = find_child("FlipBoardButton", true, false)
	if old_btn: 
		old_btn.free()

	var flip_button = Button.new()
	flip_button.text = "Flip Board"
	flip_button.name = "FlipBoardButton"
	
	# Задаем компактный аккуратный шрифт и строгий нейтральный цвет
	flip_button.add_theme_font_size_override("font_size", 12) 
	flip_button.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	flip_button.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.1))
	
	# Отключаем автоматическое расширение Grid/VBox контейнеров
	flip_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	flip_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	# НАМЕРТВО ФИКСИРУЕМ МАКСИМАЛЬНЫЙ РАЗМЕР В ПИКСЕЛЯХ
	flip_button.custom_minimum_size = Vector2(90, 24)
	flip_button.size = Vector2(90, 24)
	
		# Добавляем её напрямую в GameLayout
	if has_node("CenterContainer/GameLayout"):
		$CenterContainer/GameLayout.add_child(flip_button)
		
		# Ждём один кадр, чтобы контейнер отдал управление, и кнопка начала слушаться координат!
		await get_tree().process_frame
		
		flip_button.global_position = $CenterContainer/GameLayout.global_position + Vector2(1165, 100)
		flip_button.add_theme_color_override("font_color", Color("#eeeeee"))
		flip_button.add_theme_color_override("font_hover_color", Color("#ffffff"))   # Наведение: чуть потемнее
		flip_button.add_theme_color_override("font_pressed_color", Color("#bbbbbb")) # Нажатие: ярче / белый
	else:
		# Резервный вариант: вешаем просто в угол экрана, если нода Layout не найдена
		add_child(flip_button)
		flip_button.global_position = Vector2(20, 20)
		
	flip_button.pressed.connect(_on_analysis_flip_pressed)
	print("--- GiChess: Кнопка 'Flip Board' жестко зафиксирована в пикселях 90x24! ---")
	
	# 3. КНОПКА MAIN MENU — Сжимаем её до компактного стиля, чтобы не вылезала
	var mm_btn = find_child("MainMenuButton", true, false)
	if mm_btn and mm_btn is Button:
		mm_btn.add_theme_font_size_override("font_size", 12)
		mm_btn.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
		mm_btn.custom_minimum_size = Vector2(90, 24)
		mm_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		print("--- GiChess: Кнопка Main Menu успешно уменьшена! ---")
	
	# === ИНИЦИАЛИЗАЦИЯ ФИГУР И ДЕБЮТНОЙ СТРЕЛКИ ПРИ СТАРТЕ АНАЛИЗА (v0.1.1.0) ===
	if current_analysis_step == 0:
		setup_initial_pieces()
		print("--- GiChess: Стартовая позиция фигур успешно отрисована при входе в анализ! ---")
		
		# Даем интерфейсу один кадр, чтобы клетки cells_dict точно определили свои global_position на экране
		await get_tree().process_frame
		refresh_arrow_and_markers_only()
	else:
		if has_method("view_position_at_step"):
			view_position_at_step(current_analysis_step)
		await get_tree().process_frame
		refresh_arrow_and_markers_only()

# === ГЕНЕРАЦИЯ ИНТЕРФЕЙСА АНАЛИЗА ИЗ КОДА ===

func setup_evaluation_bar() -> void:
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "EvalHBox"
	main_hbox.add_theme_constant_override("separation", 8)
	main_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	
	var bar_wrapper = Control.new()
	bar_wrapper.name = "EvalBarWrapper"
	bar_wrapper.custom_minimum_size = Vector2(16, 0)
	bar_wrapper.size_flags_vertical = SIZE_EXPAND_FILL
	main_hbox.add_child(bar_wrapper)
	
	eval_bar = ProgressBar.new()
	eval_bar.name = "EvaluationBar"
	eval_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	eval_bar.min_value = 0
	eval_bar.max_value = 100
	eval_bar.value = 50
	eval_bar.show_percentage = false
	eval_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color("161512")
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color("ffffff")
	
	eval_bar.add_theme_stylebox_override("background", sb_bg)
	eval_bar.add_theme_stylebox_override("fill", sb_fg)
	bar_wrapper.add_child(eval_bar)
	
	eval_center_line = ColorRect.new()
	eval_center_line.name = "CenterLine"
	eval_center_line.color = Color("b58863", 0.8)
	eval_center_line.custom_minimum_size = Vector2(0, 2)
	bar_wrapper.add_child(eval_center_line)
	
	eval_display_label = Label.new()
	eval_display_label.name = "EvalDisplayLabel"
	eval_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eval_display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eval_display_label.custom_minimum_size = Vector2(45, 0)
	eval_display_label.size_flags_vertical = SIZE_EXPAND_FILL
	eval_display_label.add_theme_color_override("font_color", Color("161512"))
	eval_display_label.add_theme_font_size_override("font_size", 18)
	main_hbox.add_child(eval_display_label)
	
	bar_wrapper.item_rect_changed.connect(func():
		if is_instance_valid(bar_wrapper) and is_instance_valid(eval_center_line):
			eval_center_line.size = Vector2(bar_wrapper.size.x, 2)
			eval_center_line.position = Vector2(0, bar_wrapper.size.y / 2 - 1)
	)
	
	var layout = get_node_or_null("CenterContainer/GameLayout")
	if layout:
		layout.add_child(main_hbox)
		layout.move_child(main_hbox, 0)

func setup_navigation_buttons() -> void:
	var layout = get_node_or_null("CenterContainer/GameLayout")
	if not layout: return
		
	var side_panel = layout.get_node_or_null("SidePanel")
	if not side_panel:
		side_panel = VBoxContainer.new()
		side_panel.name = "SidePanel"
		side_panel.custom_minimum_size = Vector2(250, 0)
		side_panel.add_theme_constant_override("separation", 15)
		layout.add_child(side_panel)

	history_label = side_panel.get_node_or_null("HistoryLabel")
	if not history_label:
		history_label = RichTextLabel.new()
		history_label.name = "HistoryLabel"
		history_label.custom_minimum_size = Vector2(0, 300)
		history_label.size_flags_vertical = SIZE_EXPAND_FILL
		history_label.bbcode_enabled = true
		
		var p_style = StyleBoxFlat.new()
		p_style.bg_color = Color("161512")
		p_style.set_content_margin_all(10)
		history_label.add_theme_stylebox_override("normal", p_style)
		side_panel.add_child(history_label)

	var h_box = HBoxContainer.new()
	h_box.name = "NavButtonsContainer"
	h_box.add_theme_constant_override("separation", 20)
	h_box.alignment = BoxContainer.ALIGNMENT_CENTER
	side_panel.add_child(h_box)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color("b58863")
	btn_style.set_corner_radius_all(6)
	
	btn_back = Button.new()
	btn_back.text = "  <  "
	btn_back.custom_minimum_size = Vector2(90, 45)
	btn_back.pressed.connect(_on_back_pressed)
	btn_back.add_theme_stylebox_override("normal", btn_style)
	h_box.add_child(btn_back)
	
	btn_forward = Button.new()
	btn_forward.text = "  >  "
	btn_forward.custom_minimum_size = Vector2(90, 45)
	btn_forward.pressed.connect(_on_forward_pressed)
	btn_forward.add_theme_stylebox_override("normal", btn_style)
	h_box.add_child(btn_forward)
	
	var btn_menu = Button.new()
	btn_menu.text = "Main Menu"
	btn_menu.custom_minimum_size = Vector2(200, 45)
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	side_panel.add_child(btn_menu)
	
	update_button_states()

# Авто-блокировка (затемнение) кнопок на краях партии
func update_button_states() -> void:
	if is_instance_valid(btn_back):
		btn_back.disabled = (current_analysis_step == 0)
	if is_instance_valid(btn_forward):
		btn_forward.disabled = (current_analysis_step == moves_history.size())

# === ЛОГИКА ГЕНЕРАЦИИ ДОСКИ И ФИГУР ===

func generate_board() -> void:
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	
	cells_dict.clear()
	for child in board.get_children():
		child.queue_free()
	
	board.columns = 8
	
	var is_flipped: bool = (GameManager.actual_player_color == "b")
	
	for row in range(8):
		for col in range(8):
			var render_row = (7 - row) if is_flipped else row
			var render_col = (7 - col) if is_flipped else col
			
			var cell = cell_scene.instantiate()
			var current_color = light_color if (row + col) % 2 == 0 else dark_color
			
			var chess_name = files[render_col] + ranks[render_row]
			var grid_pos = Vector2i(render_col, render_row)
			
			cell.setup(grid_pos, chess_name, current_color)
			cell.name = chess_name
			board.add_child(cell)
			cells_dict[chess_name] = cell
			
	# Просто вызываем создание разметки. Она сама развернет массивы по флагу!
	create_external_notation()
	print("--- GiChess: Внешняя нотация успешно перерисована. Направление Flipped: ", is_flipped, " ---")

	var board_wrapper = board.get_parent()
	if board_wrapper:
		if board_wrapper.has_node("ArrowOverlay"):
			board_wrapper.get_node("ArrowOverlay").queue_free()
			
		arrow_overlay = Control.new()
		arrow_overlay.name = "ArrowOverlay"
		arrow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_wrapper.add_child(arrow_overlay)
		arrow_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		arrow_overlay.draw.connect(_on_arrow_overlay_draw)
		board_wrapper.move_child(arrow_overlay, board_wrapper.get_child_count() - 1)

func setup_initial_pieces() -> void:
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	for row in range(8):
		for col in range(8):
			var piece_char = initial_board[row][col]
			if piece_char == ".": continue
			var piece_color = "w" if piece_char == piece_char.to_upper() else "b"
			var piece_type = piece_char.to_upper()
			
			# Строгая привязка к логическому имени клетки
			var chess_name = files[col] + ranks[row]
			if cells_dict.has(chess_name):
				cells_dict[chess_name].set_piece(piece_type, piece_color)

# === ДВУХФАЗНЫЙ СУПЕР-АНАЛИЗАТОР (v0.0.5.0) ===

func start_analysis() -> void:
	if moves_history.is_empty(): return
	analyzed_scores.clear()
	analysis_move_labels.clear()
	best_moves_history.clear()
	
	# Заглушка под Ход 0
	analyzed_scores.append({"type": "cp", "value": 0})
	
	var analysis_thread = Thread.new()
	analysis_thread.start(run_hybrid_analysis)

func run_hybrid_analysis() -> void:
	var path_to_exe = ProjectSettings.globalize_path("res://bin/stockfish.exe")
	if OS.get_name() == "macOS" or OS.get_name() == "Linux": 
		path_to_exe = ProjectSettings.globalize_path("res://bin/stockfish")
	if not FileAccess.file_exists(path_to_exe): return
	
	var pipes = OS.execute_with_pipe(path_to_exe, [])
	if pipes.is_empty() or not pipes.has("stdio"): return
	var pipe_in = pipes["stdio"]
	
	best_moves_history.clear()
	analyzed_scores.clear()
	
	# Стартовая оценка ДО первого хода (0.0 пешек для Хода 0)
	analyzed_scores.append({"type": "cp", "value": 0})
	
	# Сначала берем лучший ход для САМОЙ ПЕРВОЙ стартовой позиции (для Хода 0)
	pipe_in.store_line("position startpos")
	pipe_in.store_line("go movetime 300")
	pipe_in.flush()
	while true:
		if pipe_in.get_error() != OK: break
		var line = pipe_in.get_line()
		if line.begins_with("bestmove"):
			var tokens = line.split(" ")
			if tokens.size() > 1: 
				best_moves_history.append(tokens[1]) # Сохраняем чистый UCI ход (например, "e2e4")
			break
	
	var current_moves = []
	
	# === ФАЗА 1: Экспресс-анализ (300 мс на ход) для мгновенного заполнения UI ===
	for i in range(moves_history.size()):
		current_moves.append(moves_history[i])
		pipe_in.store_line("position startpos moves " + " ".join(current_moves))
		pipe_in.store_line("go movetime 300")
		pipe_in.flush()
		
		var score_data = {"type": "cp", "value": 0}
		var found_bm = false
		while true:
			if pipe_in.get_error() != OK: break
			var line = pipe_in.get_line()
			if line.contains("score"):
				var tokens = line.split(" ")
				var score_idx = tokens.find("score")
				if score_idx != -1 and score_idx + 2 < tokens.size():
					var score_val = int(tokens[score_idx + 2])
					if i % 2 == 0: score_val = -score_val # Переворот глазами Белых
					score_data = {"type": tokens[score_idx + 1], "value": score_val}
			if line.begins_with("bestmove"):
				var tokens = line.split(" ")
				if tokens.size() > 1:
					best_moves_history.append(tokens[1])
					found_bm = true
				break
				
		if not found_bm: best_moves_history.append("")
		analyzed_scores.append(score_data)
		
		# Передаем промежуточный результат на экран
		call_deferred("update_analysis_bar", score_data, true)
		call_deferred("calculate_move_qualities")
	
	# === ФАЗА 2: ГЛУБОКИЙ ФОНОВЫЙ ДОАНАЛИЗ (depth 22) ===
	# Защита: проверяем, что в массивах есть что перезаписывать
	if analyzed_scores.size() > 1 and best_moves_history.size() > 1:
		current_moves.clear()
		for i in range(moves_history.size()):
			current_moves.append(moves_history[i])
			pipe_in.store_line("position startpos moves " + " ".join(current_moves))
			pipe_in.store_line("go depth 22") # Глубокий просчет!
			pipe_in.flush()
			
			var score_data = {"type": "cp", "value": 0}
			var found_bm = false
			while true:
				if pipe_in.get_error() != OK: break
				var line = pipe_in.get_line()
				if line.contains("score"):
					var tokens = line.split(" ")
					var score_idx = tokens.find("score")
					if score_idx != -1 and score_idx + 2 < tokens.size():
						var score_val = int(tokens[score_idx + 2])
						if i % 2 == 0: score_val = -score_val
						score_data = {"type": tokens[score_idx + 1], "value": score_val}
				if line.begins_with("bestmove"):
					var tokens = line.split(" ")
					if tokens.size() > 1:
						# БЕЗОПАСНАЯ ПЕРЕЗАПИСЬ: проверяем границы перед изменением
						if (i + 1) < best_moves_history.size():
							best_moves_history[i + 1] = tokens[1]
						found_bm = true
					break
					
			# БЕЗОПАСНАЯ ПЕРЕЗАПИСЬ ОЦЕНКИ
			if (i + 1) < analyzed_scores.size():
				analyzed_scores[i + 1] = score_data
			
			# Плавно обновляем интерфейс на лету под новые глубокие данные!
			call_deferred("update_ui_dynamically_during_bg_analysis", i + 1)
		
	pipe_in.store_line("quit")
	pipe_in.close()

func update_ui_dynamically_during_bg_analysis(step_updated: int) -> void:
	# 1. Пересчитываем текстовый PGN лог ходов справа
	calculate_move_qualities()
	
	# 2. ПРИНУДИТЕЛЬНАЯ ОЧИСТКА: стираем абсолютно все старые маркеры с доски,
	# чтобы старые оценки прошлого полухода не въедались в клетки!
	for name in cells_dict:
		cells_dict[name].clear_analysis_marker()
		
	# 3. Полностью обновляем шкалу преимущества ProgressBar под текущий шаг пользователя
	if is_instance_valid(eval_bar) and analyzed_scores.size() > current_analysis_step:
		update_analysis_bar(analyzed_scores[current_analysis_step], true)
		
	# 4. Заставляем доску принудительно перерисовать ТЕКУЩУЮ позицию пользователя.
	# Это сотрет любые застрявшие значки и нарисует свежие, если оценка текущего шага обновилась!
	view_position_at_step(current_analysis_step)

func update_analysis_bar(score: Dictionary, use_tween: bool = true) -> void:
	# === ИСПРАВЛЕНИЕ v0.1.2.0: ФИКСАЦИЯ И ШКАЛЫ И ЦИФР ДЛЯ ШАГА 0 ===
	if current_analysis_step == 0 or score.is_empty():
		# 1. Задаем процентное значение для шкалы (у тебя шкала от 0 до 100, 
		# так как ниже в коде pawns умножается на 8.0 и прибавляется к 50.0).
		# Для +0.3 пешки: 50.0 + (0.3 * 8.0) = 52.4%
		var target_percentage = 52.4
		
		if use_tween:
			if bar_tween: bar_tween.kill()
			bar_tween = create_tween()
			bar_tween.tween_property(eval_bar, "value", target_percentage, 0.25)\
				.set_trans(Tween.TRANS_QUAD)\
				.set_ease(Tween.EASE_OUT)
		else:
			if is_instance_valid(eval_bar):
				eval_bar.value = target_percentage
				
		# 2. ЖЕЛЕЗНЫЙ ВЫВОД ЦИФР: Записываем +0.3 в твой реальный узел текста!
		if is_instance_valid(eval_display_label):
			eval_display_label.text = "+0.3"
			
		return # Теперь выходим со спокойной душой, всё отрисовано!
	
	if not is_instance_valid(eval_bar) or not is_instance_valid(eval_display_label): return
	
	var display_text = "0.0"
	var percentage = 50.0
	
	if score["type"] == "mate":
		var mate_val = score["value"]
		if mate_val == 0:
			display_text = "#"
			percentage = 100.0 if current_analysis_step % 2 == 1 else 0.0
		else:
			display_text = "#" + ("+" if mate_val > 0 else "") + str(mate_val)
			percentage = 100.0 if mate_val > 0 else 0.0
	else:
		var pawns = float(score["value"]) / 100.0
		display_text = ("+" if pawns > 0 else "") + "%.1f" % pawns if abs(pawns) >= 0.05 else "0.0"
		percentage = clamp(50.0 + (pawns * 8.0), 5.0, 95.0)
	
	# ПЛАВНОЕ ПЕРЕТЕКАНИЕ ШКАЛЫ ПРЕИМУЩЕСТВА (v0.0.5.0)
	if use_tween:
		if bar_tween: bar_tween.kill() # Сбрасываем прошлый твин, если кликают слишком быстро
		bar_tween = create_tween()
		bar_tween.tween_property(eval_bar, "value", percentage, 0.25)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)
	else:
		eval_bar.value = percentage
		
	eval_display_label.text = display_text

# === СИСТЕМА НАВИГАЦИИ И КЛАССИФИКАЦИИ ХОДОВ ===

func _on_back_pressed() -> void:
	if current_analysis_step > 0:
		current_analysis_step -= 1
		view_position_at_step(current_analysis_step)
		# ИСПРАВЛЕНИЕ v0.1.2.0: Принудительно обновляем стрелки при каждом шаге
		refresh_arrow_and_markers_only()
		update_button_states()

func _on_forward_pressed() -> void:
	if current_analysis_step < moves_history.size():
		current_analysis_step += 1
		view_position_at_step(current_analysis_step)
		# ИСПРАВЛЕНИЕ v0.1.2.0: Принудительно обновляем стрелки при каждом шаге
		refresh_arrow_and_markers_only()
		update_button_states()

func view_position_at_step(step: int) -> void:
	# 1. ОБЯЗАТЕЛЬНАЯ ОЧИСТКА: стираем всё старое перед пересчетом
	for name in cells_dict:
		cells_dict[name].clear_piece()
		cells_dict[name].clear_analysis_marker()
		cells_dict[name].reset_highlight()
		
	setup_initial_pieces()
	
				# === ИСПРАВЛЕНИЕ v0.1.1.0: ФИКСАЦИЯ ТЕРМОМЕТРА НА ШАГЕ 0 ===
	if step == 0:
		if is_instance_valid(eval_bar):
			# Формируем фейковый дебютный словарь оценки для Стокфиша (+0.3 в пользу Белых)
			var debut_score = {"type": "cp", "value": 30}
			update_analysis_bar(debut_score, true)
			
		refresh_arrow_and_markers_only()
		return

	# 3. Накатываем ходы по истории (для всех остальных шагов партии)
	for i in range(step):
		var uci_move = moves_history[i]
		var from_coord = uci_move.substr(0, 2)
		var to_coord = uci_move.substr(2, 2)
		
		if cells_dict.has(from_coord) and cells_dict.has(to_coord):
			var from_cell = cells_dict[from_coord]
			var to_cell = cells_dict[to_coord]
			if from_cell.piece_data != null:
				var p_data = from_cell.piece_data.duplicate()
				if uci_move.length() == 5: 
					p_data["type"] = uci_move.substr(4, 1).to_upper()
				
				# Логика Рокировки
				if p_data["type"] == "K" and abs(to_cell.grid_position.x - from_cell.grid_position.x) == 2:
					if to_coord == "g1": cells_dict["f1"].set_piece("R", "w"); cells_dict["h1"].clear_piece()
					elif to_coord == "c1": cells_dict["d1"].set_piece("R", "w"); cells_dict["a1"].clear_piece()
					elif to_coord == "g8": cells_dict["f8"].set_piece("R", "b"); cells_dict["h8"].clear_piece()
					elif to_coord == "c8": cells_dict["d8"].set_piece("R", "b"); cells_dict["a8"].clear_piece()
					
				# Взятие на проходе
				if p_data["type"] == "P" and from_cell.grid_position.x != to_cell.grid_position.x and to_cell.piece_data == null:
					var enemy_rank = "5" if p_data["color"] == "w" else "4"
					var enemy_coord = to_coord.substr(0, 1) + enemy_rank
					if cells_dict.has(enemy_coord): 
						cells_dict[enemy_coord].clear_piece()
				
				to_cell.set_piece(p_data["type"], p_data["color"])
				from_cell.clear_piece()
				
	# Обновляем панель для обычных шагов
	if is_instance_valid(eval_bar) and analyzed_scores.size() > step:
		update_analysis_bar(analyzed_scores[step], true)
		
	refresh_arrow_and_markers_only()

# Вспомогательный метод перерисовки стрелок и нод при листании партий (v0.0.5.0)
func refresh_arrow_and_markers_only() -> void:
	var step = current_analysis_step
	
	# 1. Жестко выкашиваем абсолютно все маркеры и подсветки со всех клеток на доске
	for name in cells_dict:
		cells_dict[name].clear_analysis_marker()
		cells_dict[name].reset_highlight()
		
	# 2. Если мы просматриваем сделанный ход, вешаем значок качества на клетку-финиш
	if step > 0 and step <= moves_history.size():
		var last_uci_move = moves_history[step - 1]
		var to_coord = last_uci_move.substr(2, 2)
		var from_coord = last_uci_move.substr(0, 2)
		
		if cells_dict.has(from_coord) and cells_dict.has(to_coord):
			# Возвращаем клеткам мягкую желтую подсветку последнего хода
			cells_dict[from_coord].highlight_last_move()
			cells_dict[to_coord].highlight_last_move()
			
			var raw_label = analysis_move_labels[step - 1] if analysis_move_labels.size() > (step - 1) else ""
			var sign_text = ""
			var sign_color = Color(0, 0, 0, 0)
			
			if raw_label.contains("!!"): sign_text = "!!"; sign_color = Color("00e5ff")
			elif raw_label.contains("??"): sign_text = "??"; sign_color = Color("ff4a4a")
			elif raw_label.contains("?!"): sign_text = "?!"; sign_color = Color("4a90e2")
			elif raw_label.contains("?"): sign_text = "?"; sign_color = Color("ffcc00")
			elif raw_label.contains("x?"): sign_text = "x?"; sign_color = Color("ff9f1c")
			elif raw_label.contains("!"): sign_text = "!"; sign_color = Color("26cc53")
				
			if sign_text != "": 
				# Стираем старый маркер жестким free() и сразу рисуем новый уточненный значок
				cells_dict[to_coord].clear_analysis_marker()
				cells_dict[to_coord].set_analysis_marker(sign_text, sign_color)
			else:
				# Если у хода нет оценки (например, победный мат) — принудительно зачищаем клетку
				cells_dict[to_coord].clear_analysis_marker()
			
			# 3. Рассчитываем и перерисовываем зелёную стрелку лучшего хода Stockfish
	current_best_move_arrow.clear()
	
	# ХИТРОСТЬ v0.1.2.0: Если мы вернулись на самый стартовый ход (step == 0), 
	# мгновенно рисуем лучшую королевскую стрелку e2-e4 и ставим дебютный перевес Белых!
	if step == 0:
		if has_node("CenterContainer/GameLayout/SidePanel/EvaluationLabel"):
			$CenterContainer/GameLayout/SidePanel/EvaluationLabel.text = "Advantage: +0.3"
		elif has_node("EvaluationLabel"):
			$EvaluationLabel.text = "Advantage: +0.3"
			
		var b_from = "e2"
		var b_to = "e4"
		
		if cells_dict.has(b_from) and cells_dict.has(b_to):
			current_best_move_arrow["from_name"] = b_from
			current_best_move_arrow["to_name"] = b_to
			
			var cell_from = cells_dict[b_from]
			var cell_to = cells_dict[b_to]
			
			# Математический перевод координат клеток в локальное пространство холста
			var pos_start = (cell_from.global_position + cell_from.size / 2) - arrow_overlay.global_position
			var pos_target = (cell_to.global_position + cell_to.size / 2) - arrow_overlay.global_position
			pos_target = pos_target - (pos_target - pos_start).normalized() * 10.0
			
			current_best_move_arrow["from"] = pos_start
			current_best_move_arrow["to"] = pos_target
			
	# Если это обычный ход из истории, берем данные из массива лучших ходов матча
	elif step < best_moves_history.size() and is_instance_valid(arrow_overlay):
		var best_uci_data = best_moves_history[step]
		var best_uci = ""
		
		if typeof(best_uci_data) == TYPE_ARRAY and best_uci_data.size() > 1:
			best_uci = best_uci_data[1]
		elif typeof(best_uci_data) == TYPE_STRING:
			best_uci = best_uci_data
			
		if best_uci.length() >= 4:
			var b_from = best_uci.substr(0, 2)
			var b_to = best_uci.substr(2, 2)
			
			if cells_dict.has(b_from) and cells_dict.has(b_to):
				current_best_move_arrow["from_name"] = b_from
				current_best_move_arrow["to_name"] = b_to
				
				var cell_from = cells_dict[b_from]
				var cell_to = cells_dict[b_to]
				
				var pos_start = (cell_from.global_position + cell_from.size / 2) - arrow_overlay.global_position
				var pos_target = (cell_to.global_position + cell_to.size / 2) - arrow_overlay.global_position
				pos_target = pos_target - (pos_target - pos_start).normalized() * 10.0
				
				current_best_move_arrow["from"] = pos_start
				current_best_move_arrow["to"] = pos_target
				
	# Даем команду холсту обновиться и вызвать _on_arrow_overlay_draw()
	if is_instance_valid(arrow_overlay): 
		arrow_overlay.queue_redraw()

func _on_arrow_overlay_draw() -> void:
	if current_best_move_arrow.is_empty(): 
		return
		
	var from_pos: Vector2
	var to_pos: Vector2
	
	# v0.1.1.0: Динамически пересчитываем координаты на основе имен клеток, если доска перевернута
	var from_cell_name = current_best_move_arrow.get("from_name", "")
	var to_cell_name = current_best_move_arrow.get("to_name", "")
	
	if cells_dict.has(from_cell_name) and cells_dict.has(to_cell_name):
		var cell_from = cells_dict[from_cell_name]
		var cell_to = cells_dict[to_cell_name]
		
		# Используем твою надежную математику смещения относительно global_position холста
		from_pos = (cell_from.global_position + cell_from.size / 2) - arrow_overlay.global_position
		to_pos = (cell_to.global_position + cell_to.size / 2) - arrow_overlay.global_position
		to_pos = to_pos - (to_pos - from_pos).normalized() * 10.0
	else:
		# Резервный вариант, если имена еще не записаны в словарь
		from_pos = current_best_move_arrow.get("from", Vector2.ZERO)
		to_pos = current_best_move_arrow.get("to", Vector2.ZERO)

	if from_pos == Vector2.ZERO and to_pos == Vector2.ZERO:
		return

	# Твой оригинальный математический код отрисовки стрелки
	var arrow_color = Color("26cc53", 0.65) 
	var width = 6.0
	var arrow_length = 16.0
	var dir = (to_pos - from_pos).normalized()
	var line_end_pos = to_pos - dir * arrow_length
	
	arrow_overlay.draw_line(from_pos, line_end_pos, arrow_color, width, true)
	var ortho = Vector2(-dir.y, dir.x) * (arrow_length * 0.5)
	arrow_overlay.draw_primitive(
		[to_pos, to_pos - dir * arrow_length + ortho, to_pos - dir * arrow_length - ortho], 
		[arrow_color, arrow_color, arrow_color], 
		[]
	)

# === БЕЗОПАСНАЯ СИНХРОНИЗАЦИЯ ЛОГА ХОДОВ (v0.0.5.0) ===

# === СТАБИЛЬНЫЙ, НЕМИГАЮЩИЙ ВЫВОД ЛОГА ХОДОВ (v0.0.5.0) ===

func calculate_move_qualities() -> void:
	var temp_labels: Array = []
	
	for i in range(1, analyzed_scores.size()):
		var prev = analyzed_scores[i - 1]
		var curr = analyzed_scores[i]
		
		# ИСПРАВЛЕНИЕ: Не ставим знаки "!" или "?!" для самого первого полухода партии
		if i == 1:
			temp_labels.append("")
			continue
		
		if curr["type"] == "mate" and curr["value"] == 0:
			temp_labels.append("")
			continue
			
		var prev_pawns = float(prev["value"]) / 100.0 if prev["type"] == "cp" else (100.0 if prev["value"] > 0 else -100.0)
		var curr_pawns = float(curr["value"]) / 100.0 if curr["type"] == "cp" else (100.0 if curr["value"] > 0 else -100.0)
		
		var is_white_move = (i % 2 == 1)
		var delta = (curr_pawns - prev_pawns) if is_white_move else (prev_pawns - curr_pawns)
		var label = ""
		
		if delta <= -1.5:
			if (is_white_move and prev_pawns >= 3.0) or (not is_white_move and prev_pawns <= -3.0): 
				label = "[color=#ff9f1c] x?[/color]"
			else: 
				label = "[color=#ff4a4a] ??[/color]"
		elif delta <= -0.6: label = "[color=#ffcc00] ?[/color]"
		elif delta <= -0.3: label = "[color=#4a90e2] ?![/color]"
		elif delta >= 0.5: label = "[color=#00e5ff] !![/color]"
		elif delta >= 0.2: label = "[color=#26cc53] ![/color]"
			
		temp_labels.append(label)
	
	analysis_move_labels = temp_labels
	
	# ЗАЩИТА ОТ СПАМА ПОТОКОВ: разрешаем обновлять экран не чаще раза в 100 миллисекунд
	if not is_ui_log_updating:
		is_ui_log_updating = true
		call_deferred("apply_analysis_to_ui_log")

func apply_analysis_to_ui_log() -> void:
	if not is_instance_valid(history_label): 
		is_ui_log_updating = false
		return
		
	var bb_text = "[center][color=#999999]COMPUTER ANALYSIS[/color][/center]\n"
	bb_text += "[font_size=12][color=#666666]!! Brilliant   ! Excellent   ?! Inaccuracy   ? Mistake   ?? Blunder   x? Missed Win[/color][/font_size]\n"
	bb_text += "[color=#222222]----------------------------------------------------[/color]\n\n"
	
	var move_num = 1
	for i in range(moves_history.size()):
		if i % 2 == 0: 
			bb_text += "[color=#555555]" + str(move_num) + ".[/color] "
		
		var pgn_move = pgn_history[i] if pgn_history.size() > i else moves_history[i]
		var quality_suffix = analysis_move_labels[i] if analysis_move_labels.size() > i else ""
		
		bb_text += pgn_move + quality_suffix + "     "
		if i % 2 == 1:
			bb_text += "\n"
			move_num += 1
			
	# Прямая замена текста БЕЗ вызова .clear() убирает мерцание на 100%
	history_label.text = bb_text
	
	# Делаем микро-паузу перед тем, как разрешить следующий апдейт текста
	await get_tree().create_timer(0.1).timeout
	is_ui_log_updating = false

func create_external_notation() -> void:
	var files = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var ranks = ["8", "7", "6", "5", "4", "3", "2", "1"]
	
	# === ИСПРАВЛЕНИЕ v0.1.2.0: ДИНАМИЧЕСКИЙ ПЕРЕВОРОТ МАССИВОВ НОТАЦИИ ===
	if GameManager.actual_player_color == "b":
		files.reverse()
		ranks.reverse()
	
	# 1. Сначала ждем один кадр, чтобы Godot полностью просчитал размеры доски
	await get_tree().process_frame
	if not is_instance_valid(board): return
	
	var board_size = board.size
	var board_pos = board.global_position
	var text_color = Color("161512") # Фирменный благородный темный цвет
	
	# 2. ИСПРАВЛЕНИЕ НАЛОЖЕНИЯ: Жестко стираем старую разметку строго ПОСЛЕ await!
	# Ищем узлы напрямую через has_node и удаляем, чтобы они не двоились в памяти
	if has_node("LeftRanks"):
		get_node("LeftRanks").free() # Используем free() вместо queue_free() для мгновенного уничтожения без фантомов!
	if has_node("BottomFiles"):
		get_node("BottomFiles").free()
	
	# А) ГЕНЕРИРУЕМ ЦИФРЫ СЛЕВА ОТ ДОСКИ
	var left_ranks = VBoxContainer.new()
	left_ranks.name = "LeftRanks"
	left_ranks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_ranks)
	
	# Позиционируем контейнер цифр ровно слева от доски с отступом в 24 пикселя
	left_ranks.global_position = Vector2(board_pos.x - 24, board_pos.y)
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
		
	# Б) ГЕНЕРИРУЕМ БУКВЫ СНИЗУ ОТ ДОСКИ
	var bottom_files = HBoxContainer.new()
	bottom_files.name = "BottomFiles"
	bottom_files.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_files)
	
	# Позиционируем контейнер букв строго под доской с отступом в 6 пикселей
	bottom_files.global_position = Vector2(board_pos.x, board_pos.y + board_size.y + 6)
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

func _on_analysis_flip_pressed() -> void:
	# 1. МГНОВЕННАЯ ОЧИСТКА: Скрываем слой стрелок, чтобы старая отрисовка не зависала в воздухе
	if is_instance_valid(arrow_overlay):
		arrow_overlay.visible = false
		arrow_overlay.queue_redraw()
		
	# 2. Меняем флаг цвета в GameManager для переворота математики доски
	if GameManager.actual_player_color == "w":
		GameManager.actual_player_color = "b"
	else:
		GameManager.actual_player_color = "w"
	
	# 3. Сохраняем текущее состояние фигур на доске
	var current_position_map = {}
	for chess_name in cells_dict:
		var cell = cells_dict[chess_name]
		if cell.piece_data != null:
			current_position_map[chess_name] = cell.piece_data.duplicate()
			
	# 4. Пересоздаем сетку клеток под новым углом
	await generate_board()
	
	# 5. Расставляем фигуры обратно на свои шахматные координаты
	for chess_name in current_position_map:
		var p_data = current_position_map[chess_name]
		if cells_dict.has(chess_name):
			cells_dict[chess_name].set_piece(p_data["type"], p_data["color"])
			
	# 6. Ждем окончания кадра отрисовки интерфейса, чтобы клетки заняли новые физические места
	await get_tree().process_frame
	
	# 7. Возвращаем видимость слою стрелок и обновляем их по новым координатам
	if is_instance_valid(arrow_overlay):
		arrow_overlay.visible = true
		arrow_overlay.queue_redraw()
		
	print("--- GiChess: Доска анализа перевернута, фантомные стрелки уничтожены! ---")

func _force_set_debut_advantage() -> void:
	if current_analysis_step == 0:
		if has_node("CenterContainer/GameLayout/SidePanel/EvaluationLabel"):
			$CenterContainer/GameLayout/SidePanel/EvaluationLabel.text = "Advantage: +0.3"
		elif has_node("SidePanel/EvaluationLabel"):
			$SidePanel/EvaluationLabel.text = "Advantage: +0.3"
		elif has_node("EvaluationLabel"):
			$EvaluationLabel.text = "Advantage: +0.3"
