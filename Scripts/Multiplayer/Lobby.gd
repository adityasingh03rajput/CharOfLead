extends CanvasLayer

signal host_requested
signal join_requested(ip: String)

var _ip_input: LineEdit
var _status_label: Label

func _ready() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.05, 0.1, 1.0)
	panel.set_anchors_preset(PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CharOfLead - Multiplayer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	var btn_host := Button.new()
	btn_host.text = "Host Game"
	btn_host.add_theme_font_size_override("font_size", 24)
	btn_host.pressed.connect(func(): host_requested.emit())
	vbox.add_child(btn_host)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	_ip_input = LineEdit.new()
	_ip_input.text = "127.0.0.1"
	_ip_input.custom_minimum_size = Vector2(200, 0)
	_ip_input.add_theme_font_size_override("font_size", 24)
	hbox.add_child(_ip_input)

	var btn_join := Button.new()
	btn_join.text = "Join Game"
	btn_join.add_theme_font_size_override("font_size", 24)
	btn_join.pressed.connect(func(): join_requested.emit(_ip_input.text))
	hbox.add_child(btn_join)

	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer3)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 0))
	vbox.add_child(_status_label)

func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text
