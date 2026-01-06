extends Node

@onready var kidney = get_node("/root/Main/Kidney")
@onready var info_panel = get_parent()
@onready var title_label = info_panel.get_node("ChannelTitle")
@onready var selection_manager = get_parent().get_parent().get_parent().get_node("Nephron/NephronSelectionManager")

var channel_data: Dictionary = {}

func _ready():
	kidney.connect("state_changed", _on_kidney_state_changed)
	selection_manager.channel_selected.connect(_on_channel_selected)
	selection_manager.channel_deselected.connect(_on_channel_deselected)
	_load_data_for_state(kidney.current_display_state)
	info_panel.visible = false

func _on_kidney_state_changed(new_state):
	_load_data_for_state(new_state)

func _load_data_for_state(state):
	match state:
		kidney.SelectionState.PCT:
			_load_pct_data()

func _load_pct_data():
	var file = FileAccess.open("res://Kidney/Data/pct_channels.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			channel_data = json.data
			# print("Loaded PCT channel data")
		else:
			push_error("Failed to parse pct_channels.json")
	else:
		push_error("Failed to open pct_channels.json")

func _on_channel_selected(channel):
	info_panel.visible = true
	title_label.text = channel.channel_name

func _on_channel_deselected():
	info_panel.visible = false
	title_label.text = ""
