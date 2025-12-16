extends Node

#Signals
signal display_state_changed(new_state: DisplayState, old_state: DisplayState)

#State Machine
enum DisplayState{
	DEFAULT
}

var current_state: DisplayState = DisplayState.DEFAULT

func _ready():
	set_display_state(current_state)
	
#APIs
func set_display_state(state: DisplayState):
	var old_state = current_state
	current_state = state
	
	match state:
		DisplayState.DEFAULT:
			display_state_changed.emit(current_state, old_state)
			
func get_current_display_state() -> DisplayState:
	return current_state
