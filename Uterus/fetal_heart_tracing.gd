extends Control
@export var trace_speed: float = 50.0
@export var trace_width: float = 400.0
@export var trace_height: float = 200.0
# Visual settings
@export var contraction_intensity: float = 60.0  # Visual height only
@export var fhr_y_offset: float = -150.0
@export var fhr_scale: float = 1.0
@export var fhr_display_min: float = 130.0
@export var fhr_display_max: float = 170.0
var current_x: float = 0.0
var contraction_line: Line2D
var fhr_line: Line2D
var fetus_controller: Node
var uterus_controller: Node

func _ready():
	# Create lines
	contraction_line = Line2D.new()
	add_child(contraction_line)
	contraction_line.width = 2.0
	contraction_line.default_color = Color.BLUE
	
	fhr_line = Line2D.new()
	add_child(fhr_line)
	fhr_line.width = 2.0
	fhr_line.default_color = Color.RED
	
	# Get reference to controllers
	fetus_controller = get_node("../fetus_controller")
	uterus_controller = get_node("../UterusController")
	
	# Connect to uterus controller signals
	if uterus_controller:
		uterus_controller.state_changed_to_pregnant.connect(_on_pregnant_state)
		uterus_controller.state_changed_to_nonpregnant.connect(_on_nonpregnant_state)
	
	# Set initial state (starts non-pregnant, so hide traces)
	_on_nonpregnant_state()
	
	current_x = 0.0

func _on_pregnant_state():
	# Show traces when pregnant
	contraction_line.visible = true
	fhr_line.visible = true
	print("UI: Showing cervical traces")

func _on_nonpregnant_state():
	# Hide traces when not pregnant
	contraction_line.visible = false
	fhr_line.visible = false
	print("UI: Hiding cervical traces")

func _process(delta):
	# Only process traces when they're visible (pregnant state)
	if not contraction_line.visible:
		return
	
	current_x += trace_speed * delta
	
	# Reset both traces when reaching the end
	if current_x >= trace_width:
		current_x = 0.0
		contraction_line.clear_points()
		fhr_line.clear_points()
	
	# Add points to both lines
	var contraction_y = get_contraction_y()
	var fhr_y = get_fhr_y()
	
	contraction_line.add_point(Vector2(current_x, contraction_y))
	fhr_line.add_point(Vector2(current_x, fhr_y))

func get_contraction_y() -> float:
	var baseline_y = trace_height / 2
	
	# Get contraction intensity from fetus controller
	var intensity = fetus_controller.get_contraction_intensity()
	var contraction_offset = intensity * contraction_intensity
	
	return baseline_y - contraction_offset

func get_fhr_y() -> float:
	var current_bpm = fetus_controller.get_current_heart_rate()
	current_bpm = clamp(current_bpm, fhr_display_min, fhr_display_max)
	
	var display_baseline = (fhr_display_min + fhr_display_max) / 2.0
	var baseline_y = trace_height / 2 + fhr_y_offset
	var bpm_offset = (current_bpm - display_baseline) * fhr_scale
	
	return baseline_y - bpm_offset
