extends Node

signal state_changed(new_state)

enum SelectionState{
	PCT
}

var current_display_state: SelectionState = SelectionState.PCT

func set_display_state(state: SelectionState):
	var old_state = current_display_state
	current_display_state = state
	state_changed.emit(current_display_state)
