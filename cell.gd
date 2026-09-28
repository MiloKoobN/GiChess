# cell.gd
extends ColorRect

signal cell_clicked(grid_pos: Vector2i, chess_coordinate: String)

var grid_position: Vector2i
var chess_coordinate: String
var piece_data = null 
var original_color: Color 
var is_dot_visible: bool = false

# Цвета для подсветки последнего хода (в стиле Lichess)
const LIGHT_MOVE_COLOR = Color("cdd26a") # Для светлых клеток ("f0d9b5")
const DARK_MOVE_COLOR = Color("aaa23a")  # Для темных клеток ("b58863")
const CHECK_COLOR = Color("d35f5f") 

@onready var piece_icon: TextureRect = $PieceIcon

func setup(pos: Vector2i, coord: String, default_color: Color) -> void:
	grid_position = pos
	chess_coordinate = coord
	color = default_color
	original_color = default_color
	is_dot_visible = false
	
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

func set_piece(type: String, piece_color: String) -> void:
	piece_data = {"type": type, "color": piece_color}
	var path = "res://assets/pieces/" + piece_color + type + ".svg"
	if ResourceLoader.exists(path):
		piece_icon.texture = load(path)

func clear_piece() -> void:
	piece_data = null
	piece_icon.texture = null

## Включает подсветку выделенной клетки (когда игрок кликнул по фигуре)
func highlight_selected() -> void:
	if original_color == Color("f0d9b5"):
		color = Color("f7e781")
	else:
		color = Color("d8b859")

## Включает подсветку последнего сделанного хода (своего или Stockfish)
func highlight_last_move() -> void:
	if original_color == Color("f0d9b5"):
		color = LIGHT_MOVE_COLOR
	else:
		color = DARK_MOVE_COLOR

## Полностью сбрасывает цвет клетки к исходному и убирает точку
func reset_highlight() -> void:
	color = original_color
	hide_dot()

func show_dot() -> void:
	is_dot_visible = true
	queue_redraw()

func hide_dot() -> void:
	is_dot_visible = false
	queue_redraw()

func _draw() -> void:
	if is_dot_visible:
		var center = size / 2
		var dot_color = Color(0, 0, 0, 0.35) 
		if piece_data == null:
			draw_circle(center, 14.0, dot_color)
		else:
			var radius = (size.x / 2) - 5
			draw_arc(center, radius, 0, 360, 64, dot_color, 7.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(grid_position, chess_coordinate)

## Возвращает текущую текстуру фигуры (нужно для анимации)
func get_piece_texture() -> Texture2D:
	return piece_icon.texture

## Управляет видимостью оригинальной иконки на время полета
func set_piece_icon_visible(is_visible: bool) -> void:
	piece_icon.visible = is_visible

func highlight_check() -> void:
	color = CHECK_COLOR

# === ОТОБРАЖЕНИЕ МАРКЕРОВ КАЧЕСТВА ХОДА (v0.0.5.0) ===
var analysis_icon_text: String = ""
var analysis_icon_color: Color = Color(0, 0, 0, 0)

func set_analysis_marker(text_sign: String, marker_color: Color) -> void:
	clear_analysis_marker()
	
	# 1. Создаем круглую подложку через Panel
	var marker = Panel.new()
	marker.name = "AnalysisMarkerNode"
	
	var style = StyleBoxFlat.new()
	style.bg_color = marker_color
	style.set_corner_radius_all(12) # Идеальный круг при размере 24x24
	style.set_border_width_all(1)
	style.border_color = Color("161512", 0.7) # Контрастная темная обводка
	marker.add_theme_stylebox_override("panel", style)
	
	marker.custom_minimum_size = Vector2(24, 24)
	marker.size = Vector2(24, 24)
	marker.position = Vector2(size.x - 26, 2) # Позиция в правом верхнем углу клетки
	
	# 2. УМНОЕ РЕШЕНИЕ: Создаем CenterContainer для железного центрирования текста
	var center_container = CenterContainer.new()
	center_container.size = Vector2(24, 24) # Занимает ровно весь кружок
	marker.add_child(center_container)
	
	# 3. Создаем сам текст знака
	var lbl = Label.new()
	lbl.text = text_sign
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Настройки шрифта
	lbl.add_theme_color_override("font_color", Color.WHITE)
	# Микро-коррекция размера: 12 для одиночных (!, ?), 10 для двойных (!!, ??)
	lbl.add_theme_font_size_override("font_size", 12 if text_sign.length() == 1 else 10)
	
	# Защита от съезжания: сбрасываем любые дефолтные отступы темы, которые могут двигать шрифт
	lbl.add_theme_constant_override("line_spacing", 0)
	
	# Собираем ноды: Label складываем в центр, а маркер — наверх клетки
	center_container.add_child(lbl)
	add_child(marker)
	
	# Выталкиваем на самый передний слой поверх фигуры (PieceIcon)
	move_child(marker, get_child_count() - 1)

func clear_analysis_marker() -> void:
	# Надежная очистка: вычищаем абсолютно все маркеры, 
	# которые были созданы динамически, без ожидания конца кадра!
	for child in get_children():
		if child.name == "AnalysisMarkerNode" or child.name.begins_with("@AnalysisMarkerNode"):
			remove_child(child) # Мгновенно убираем из дерева сцены
			child.free()        # Аппаратно стираем из памяти прямо сейчас
