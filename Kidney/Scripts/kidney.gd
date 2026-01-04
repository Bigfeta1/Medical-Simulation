extends Node

signal state_changed(old_state, new_state)

enum SelectionState{
	STANDBY,
	GLOMERULUS,
	PCT
}

var current_display_state: SelectionState = SelectionState.STANDBY

func set_display_state(state: SelectionState):
	var old_state = current_display_state
	current_display_state = state
	state_changed.emit(old_state, current_display_state)
