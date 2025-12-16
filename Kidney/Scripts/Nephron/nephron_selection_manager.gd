extends Node

signal channel_selected(channel)
signal channel_deselected()

var registered_objects: Array = []
var selected_object = null

func register(object):
	registered_objects.append(object)

func select(object):
	if selected_object:
		selected_object.deselect()

	selected_object = object
	selected_object.select()
	channel_selected.emit(object)

func deselect():
	if selected_object:
		selected_object.deselect()
		selected_object = null
		channel_deselected.emit()
