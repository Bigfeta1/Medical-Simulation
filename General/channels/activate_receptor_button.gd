extends Button

## Button that activates the currently selected receptor/channel
## Uses organ-specific state machines to navigate to the appropriate receptor node

@export var state_machine: Node  # Assign organ-specific state machine for pathfinding
@export var selection_manager: Node  # Reference to the organ's selection manager

var current_selected_channel = null

func _ready():
	pressed.connect(_on_pressed)

	if selection_manager:
		selection_manager.channel_selected.connect(_on_channel_selected)
		selection_manager.channel_deselected.connect(_on_channel_deselected)

func _on_channel_selected(channel):
	current_selected_channel = channel
	disabled = false

func _on_channel_deselected():
	current_selected_channel = null
	disabled = true

func _on_pressed():
	if not current_selected_channel:
		push_warning("ActivateReceptorButton: No channel selected")
		return

	if not current_selected_channel.has_method("activate"):
		push_warning("ActivateReceptorButton: Selected channel '%s' has no activate() method" % current_selected_channel.name)
		return

	current_selected_channel.activate()
