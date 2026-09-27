# cell.gd
extends ColorRect

signal cell_clicked(grid_pos: Vector2i, chess_coordinate: String)

var grid_position: Vector2i
var chess_coordinate: String
var piece_data = null 
var original_color: Color 
var is_dot_visible: bool = false

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

func highlight_selected() -> void:
	if original_color == Color("f0d9b5"):
		color = Color("f7e781")
	else:
		color = Color("d8b859")

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
