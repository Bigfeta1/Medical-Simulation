extends AnimatedSprite3D
class_name IonChannel

enum EpithelialPolarity {
	NOT_APPLICABLE,        # Non-epithelial cells
	APICAL,                # Luminal membrane
	BASOLATERAL,           # Blood-facing membrane
	MISPOLARIZED           # Pathologic: polarity disruption (ATN)
}

@export var channel_name: String = ""
@export var epithelial_polarity: EpithelialPolarity = EpithelialPolarity.NOT_APPLICABLE
@export var outline_width: float = 5.0
@export var outline_color: Color = Color.HOT_PINK

var outline_material: ShaderMaterial
var selection_manager
var is_selected: bool = false

func _ready():
	selection_manager = get_node("/root/Main/Kidney/Nephron/NephronSelectionManager")
	selection_manager.register(self)

	outline_material = ShaderMaterial.new()
	outline_material.shader = load("res://outline_shader_3d.gdshader")
	outline_material.set_shader_parameter("width", outline_width)
	outline_material.set_shader_parameter("outline_color", outline_color)

	play()

func _process(_delta):
	if is_selected:
		var current_texture = sprite_frames.get_frame_texture(animation, frame)
		outline_material.set_shader_parameter("sprite_texture", current_texture)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera = get_viewport().get_camera_3d()
		if camera:
			var from = camera.project_ray_origin(event.position)
			var to = from + camera.project_ray_normal(event.position) * 1000.0

			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(from, to)
			var result = space_state.intersect_ray(query)

			if result and result.collider.get_parent() == self:
				if is_selected:
					selection_manager.deselect()
				else:
					selection_manager.select(self)
				get_viewport().set_input_as_handled()

func select():
	is_selected = true
	material_override = outline_material

func deselect():
	is_selected = false
	material_override = null
