extends Node

signal state_changed(old_state, new_state)

enum SelectionState{
	GROSS,
	GLOMERULUS,
	PCT
}

var current_display_state: SelectionState = SelectionState.PCT

func set_display_state(state: SelectionState):
	var old_state = current_display_state
	current_display_state = state
	state_changed.emit(old_state, current_display_state)
