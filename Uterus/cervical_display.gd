extends TextureRect
@onready var cervical_viewport: SubViewport = $CervicalViewport
@onready var cervical_camera: Camera3D = $CervicalViewport/CervicalCamera
var fetus_controller: Node
var uterus_controller: Node
var original_camera_position: Vector3

func _ready():
	# Check if the viewport exists
	if cervical_viewport == null:
		print("ERROR: CervicalViewport not found!")
		return
	
	# Get reference to controllers
	fetus_controller = get_node("../../fetus_controller")
	if fetus_controller == null:
		print("ERROR: Could not find fetus_controller!")
	
	uterus_controller = get_node("../../UterusController")
	if uterus_controller == null:
		print("ERROR: Could not find UterusController!")
	else:
		# Connect to uterus controller signals
		uterus_controller.state_changed_to_pregnant.connect(_on_pregnant_state)
		uterus_controller.state_changed_to_nonpregnant.connect(_on_nonpregnant_state)
	
	# Store original camera position
	if cervical_camera:
		original_camera_position = cervical_camera.position
	
	# Set viewport properties for maximum quality
	cervical_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cervical_viewport.scaling_3d_mode = SubViewport.SCALING_3D_MODE_BILINEAR
	cervical_viewport.fsr_sharpness = 0.8  # If using FSR
	
	# Set viewport to fixed high resolution (1920x1080) regardless of display size
	# This gives maximum quality and then scales down
	cervical_viewport.size = Vector2i(1920, 1080)
	
	# Configure additional viewport settings
	cervical_viewport.snap_2d_transforms_to_pixel = false
	cervical_viewport.snap_2d_vertices_to_pixel = false
	
	# Set texture filter to improve scaling quality
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	
	# Wait for viewport to initialize
	await get_tree().process_frame
	await get_tree().process_frame  # Sometimes need extra frame
	
	# Set the viewport texture to this TextureRect
	texture = cervical_viewport.get_texture()
	
	# Ensure proper scaling
	expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Set initial state (starts non-pregnant, so hide display)
	_on_nonpregnant_state()

func _on_pregnant_state():
	# Show cervical display when pregnant
	visible = true
	print("CervicalDisplay: Showing cervical display")

func _on_nonpregnant_state():
	# Hide cervical display when not pregnant
	visible = false
	print("CervicalDisplay: Hiding cervical display")

func _process(delta):
	# Only process when visible (pregnant state)
	if not visible:
		return
	
	# Continuously update the texture in case it gets lost
	if cervical_viewport and texture != cervical_viewport.get_texture():
		texture = cervical_viewport.get_texture()
	
	# Make camera bob with contractions
	if fetus_controller and cervical_camera:
		var contraction_intensity = fetus_controller.get_contraction_intensity()
		var bob_amount = 0.02  # Much more subtle bobbing motion
		#var side_bob_amount = 0.005  # Even more subtle side-to-side motion
		
		# Apply vertical and slight horizontal bobbing motion
		var new_position = original_camera_position
		new_position.y += contraction_intensity * bob_amount
		#new_position.x += contraction_intensity * side_bob_amount  # Simple side bob
		cervical_camera.position = new_position
