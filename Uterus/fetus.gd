extends Node

var current_fetal_heart_rate = 0.0
var base_fetal_heart_rate = 150.0

# Heart rate variability settings
@export var min_heart_rate: float = 110.0
@export var max_heart_rate: float = 160.0
@export var variability_amount: float = 15.0
@export var change_rate: float = 8.0

# Contraction settings
@export var contraction_interval: float = 5.0
@export var contraction_duration: float = 1.5

# Early deceleration settings (toggleable with E key)
@export var early_deceleration: bool = false
@export var deceleration_amount: float = 20.0

# Uterus scaling settings
@export var uterus_controller_path: NodePath = "../UterusController"  # Path to UterusController
@export var scale_intensity: float = 0.02  # Subtle scaling (2% by default)
@export var tube_movement_intensity: float = 0.1  # How much tubes move toward center during contractions
@export var ovary_movement_intensity: float = 0.08  # How much ovaries move toward center during contractions
@export var ligament_movement_intensity: float = 0.06  # How much ligaments move toward center during contractions

var uterus_controller: Node3D  # Reference to the UterusController
var uterus_node: Node3D  # Reference to the "uterus" child model
var fallopian_tube_r: Node3D  # Right fallopian tube
var fallopian_tube_l: Node3D  # Left fallopian tube
var l_ovary: Node3D  # Left ovary
var r_ovary: Node3D  # Right ovary
var ovarian_ligament_curve: Node3D  # First ovarian ligament
var ovarian_ligament_curve_001: Node3D  # Second ovarian ligament
var original_scale: Vector3  # Store the original scale
var original_tube_r_pos: Vector3  # Store original right tube position
var original_tube_l_pos: Vector3  # Store original left tube position
var original_l_ovary_pos: Vector3  # Store original left ovary position
var original_r_ovary_pos: Vector3  # Store original right ovary position
var original_ligament_curve_pos: Vector3  # Store original ligament curve position
var original_ligament_curve_001_pos: Vector3  # Store original ligament curve 001 position

var time_elapsed: float = 0.0

func _ready():
	current_fetal_heart_rate = base_fetal_heart_rate
	
	# Get reference to the UterusController
	if not uterus_controller_path.is_empty():
		uterus_controller = get_node(uterus_controller_path)
	else:
		# Fallback: look for it as a sibling node
		print("No path set, looking for 'UterusController' as sibling...")
		uterus_controller = get_parent().get_node("UterusController")
	
	if uterus_controller == null:
		print("ERROR: Could not find UterusController node!")
	else:
		# Try to cache nodes if currently pregnant
		cache_uterus_nodes()

func cache_uterus_nodes():
	# Only cache nodes if we have a pregnant uterus
	if not uterus_controller or not uterus_controller.is_pregnant():
		clear_node_references()
		return
	
	var current_uterus = uterus_controller.current_uterus_instance
	if current_uterus == null:
		print("ERROR: No current uterus instance!")
		return
	
	# Find all the reproductive organs using recursive search
	uterus_node = find_node_by_name(current_uterus, "uterus")
	fallopian_tube_r = find_node_by_name(current_uterus, "fallopian_tube_r")
	fallopian_tube_l = find_node_by_name(current_uterus, "fallopian_tube_l")
	l_ovary = find_node_by_name(current_uterus, "l_ovary")
	r_ovary = find_node_by_name(current_uterus, "r_ovary")
	ovarian_ligament_curve = find_node_by_name(current_uterus, "ovarian_ligament_curve")
	ovarian_ligament_curve_001 = find_node_by_name(current_uterus, "ovarian_ligament_curve_001")
	
	# Store original positions and scales
	store_original_transforms()

func find_node_by_name(parent: Node, node_name: String) -> Node3D:
	if parent.name == node_name:
		return parent as Node3D
	
	for child in parent.get_children():
		var result = find_node_by_name(child, node_name)
		if result:
			return result
	
	return null

func store_original_transforms():
	if uterus_node:
		original_scale = uterus_node.scale
	else:
		print("WARNING: Could not find 'uterus' node!")
		
	if fallopian_tube_r:
		original_tube_r_pos = fallopian_tube_r.position
	else:
		print("WARNING: Could not find 'fallopian_tube_r' node!")
		
	if fallopian_tube_l:
		original_tube_l_pos = fallopian_tube_l.position
	else:
		print("WARNING: Could not find 'fallopian_tube_l' node!")
		
	if l_ovary:
		original_l_ovary_pos = l_ovary.position
	else:
		print("WARNING: Could not find 'l_ovary' node!")
		
	if r_ovary:
		original_r_ovary_pos = r_ovary.position
	else:
		print("WARNING: Could not find 'r_ovary' node!")
		
	if ovarian_ligament_curve:
		original_ligament_curve_pos = ovarian_ligament_curve.position
	else:
		print("WARNING: Could not find 'ovarian_ligament_curve' node!")
		
	if ovarian_ligament_curve_001:
		original_ligament_curve_001_pos = ovarian_ligament_curve_001.position
	else:
		print("WARNING: Could not find 'ovarian_ligament_curve_001' node!")

func clear_node_references():
	uterus_node = null
	fallopian_tube_r = null
	fallopian_tube_l = null
	l_ovary = null
	r_ovary = null
	ovarian_ligament_curve = null
	ovarian_ligament_curve_001 = null

func _process(delta):
	# Only process fetal/contraction logic when pregnant
	if not uterus_controller or not uterus_controller.is_pregnant():
		# Clear references when not pregnant and stop all processing
		clear_node_references()
		return
	
	time_elapsed += delta
	handle_input()
	
	# If we don't have node references, try to cache them
	if uterus_node == null:
		cache_uterus_nodes()
	
	# Apply uterus scaling and tube movement during contractions
	update_contraction_effects()

func handle_input():
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_E):
		if Input.is_key_pressed(KEY_E) and not Input.is_action_just_pressed("ui_accept"):
			if not get_meta("e_pressed", false):
				early_deceleration = not early_deceleration
				print("Early deceleration: ", "ON" if early_deceleration else "OFF")
				set_meta("e_pressed", true)
		else:
			set_meta("e_pressed", false)
	else:
		set_meta("e_pressed", false)

func update_contraction_effects():
	# Only run if we're in pregnant mode - no contractions for non-pregnant uterus
	if not uterus_controller or not uterus_controller.is_pregnant():
		return
	
	var contraction_intensity = get_contraction_intensity()
	
	# Update uterus scaling
	if uterus_node:
		# Calculate a subtle scale modification (multiply with original scale)
		var scale_mod = 1.0 - (contraction_intensity * scale_intensity)
		
		# Apply scaling as a multiplier on the original scale
		uterus_node.scale = original_scale * scale_mod
	
	# Update fallopian tube positions (move toward center during contractions)
	if fallopian_tube_r:
		# Move right tube slightly toward center (negative X direction)
		var movement_amount = contraction_intensity * tube_movement_intensity
		var new_pos = original_tube_r_pos
		new_pos.x -= movement_amount  # Move toward center
		fallopian_tube_r.position = new_pos
		
	if fallopian_tube_l:
		# Move left tube slightly toward center (positive X direction)  
		var movement_amount = contraction_intensity * tube_movement_intensity
		var new_pos = original_tube_l_pos
		new_pos.x += movement_amount  # Move toward center
		fallopian_tube_l.position = new_pos
	
	# Update ovary positions (move toward center during contractions)
	if r_ovary:
		# Move right ovary toward center (negative X direction)
		var movement_amount = contraction_intensity * ovary_movement_intensity
		var new_pos = original_r_ovary_pos
		new_pos.x -= movement_amount  # Move toward center
		r_ovary.position = new_pos
		
	if l_ovary:
		# Move left ovary toward center (positive X direction)
		var movement_amount = contraction_intensity * ovary_movement_intensity
		var new_pos = original_l_ovary_pos
		new_pos.x += movement_amount  # Move toward center
		l_ovary.position = new_pos
	
	# Update ovarian ligament positions (move toward center during contractions)
	if ovarian_ligament_curve:
		# Move ligament toward center
		var movement_amount = contraction_intensity * ligament_movement_intensity
		var new_pos = original_ligament_curve_pos
		# Assuming this ligament is on the right side
		new_pos.x -= movement_amount  # Move toward center
		ovarian_ligament_curve.position = new_pos
		
	if ovarian_ligament_curve_001:
		# Move ligament toward center  
		var movement_amount = contraction_intensity * ligament_movement_intensity
		var new_pos = original_ligament_curve_001_pos
		# Assuming this ligament is on the left side
		new_pos.x += movement_amount  # Move toward center
		ovarian_ligament_curve_001.position = new_pos

func get_contraction_intensity() -> float:
	# No contractions when not pregnant
	if not uterus_controller or not uterus_controller.is_pregnant():
		return 0.0
		
	var time_in_cycle = fmod(time_elapsed, contraction_interval)
	
	if time_in_cycle <= contraction_duration:
		var progress = time_in_cycle / contraction_duration
		return sin(progress * PI)
	else:
		return 0.0

func is_contracting() -> bool:
	# No contractions when not pregnant
	if not uterus_controller or not uterus_controller.is_pregnant():
		return false
		
	var time_in_cycle = fmod(time_elapsed, contraction_interval)
	return time_in_cycle <= contraction_duration

func get_current_heart_rate() -> float:
	# Only return heart rate if we're in pregnant mode
	if not uterus_controller or not uterus_controller.is_pregnant():
		return 0.0
	
	# Reduced baseline variations to make early decelerations more noticeable
	var slow_variation = sin(time_elapsed * 1.2) * 2.0      # Reduced from 6.0
	var quick_variation = sin(time_elapsed * 8.0) * 1.5     # Reduced from 4.0
	var rapid_beats = sin(time_elapsed * 15.0) * 0.8        # Reduced from 2.0
	var random_noise = (randf() - 0.5) * variability_amount * 0.15  # Reduced from 0.4
	
	var instant_rate = base_fetal_heart_rate + slow_variation + quick_variation + rapid_beats + random_noise
	
	# Only apply deceleration if early_deceleration is enabled
	if early_deceleration:
		var deceleration_factor = get_contraction_intensity()
		instant_rate -= deceleration_factor * deceleration_amount
	
	return clamp(instant_rate, min_heart_rate, max_heart_rate)
