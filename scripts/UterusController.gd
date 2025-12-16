extends Node3D

# Signals for state changes
signal state_changed_to_pregnant()
signal state_changed_to_nonpregnant()

# Scene resources: 3D OBJECT REFERENCES
@export var non_pregnant_uterus_scene: PackedScene
@export var pregnant_uterus_scene: PackedScene

# State machine
enum States {NONPREGNANT, PREGNANT}               # Create All States
var state_count: int = 2                          # Total number of states
var current_state: States = States.NONPREGNANT    # Set Initial State to NONPREGNANT
var current_uterus_instance: Node3D               # Initialize placeholder for 3D object of State

func _ready():
	# Load default scenes if not assigned
	if not non_pregnant_uterus_scene:
		non_pregnant_uterus_scene = preload("res://Uterus/NonpregnantUterus.glb")
	if not pregnant_uterus_scene:
		pregnant_uterus_scene = preload("res://Uterus/PregnantUterus.glb")
	
	# Initialize with first state
	enter_state(current_state)

# ENTER STATE
func enter_state(state: States):
	match state:
		# If Nonpregnant, load nonpregnant uterus & emit signal
		States.NONPREGNANT:                              
			load_uterus_scene(non_pregnant_uterus_scene)
			state_changed_to_nonpregnant.emit()
		
		# If Pregnant, load pregnant uterus & emit signal
		States.PREGNANT:
			load_uterus_scene(pregnant_uterus_scene)
			state_changed_to_pregnant.emit()

# LOAD UTERUS SCENE: Shared scene loading logic
func load_uterus_scene(scene: PackedScene):
	
	# Clean up current instance
	if current_uterus_instance:
		current_uterus_instance.queue_free()
		current_uterus_instance = null
	
	# Create and configure new instance
	current_uterus_instance = scene.instantiate()
	current_uterus_instance.rotation_degrees.z = 180.0
	current_uterus_instance.position.y = 0.726
	add_child(current_uterus_instance)

# Input handling
func _input(event):
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.keycode == KEY_P and event.pressed):
		toggle_state()

func toggle_state():
	# Increment state and loop around
	current_state += 1
	if current_state >= state_count:
		current_state = 0
	enter_state(current_state)

# Getter functions
func is_pregnant() -> bool:
	return current_state == States.PREGNANT

func get_current_state() -> States:
	return current_state
