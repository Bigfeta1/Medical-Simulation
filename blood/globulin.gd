extends MeshInstance3D

enum GLOBULIN_TYPE {
	alpha,
	beta,
	gamma,
	delta,
	standby
}

@export var current_globulin_type: GLOBULIN_TYPE = GLOBULIN_TYPE.standby

var alpha_icon = "res://blood/assets/images/hemoglobin/alpha_chain.png"
var beta_icon = "res://blood/assets/images/hemoglobin/beta_chain.png"


enum GLOBULIN_STATE {
	taut,
	relaxed,
	middle
}

var current_globulin_state: GLOBULIN_STATE = GLOBULIN_STATE.middle

var parent = get_parent()

@export var defective = false

var iron_bound = true
var o2_bound = true

var co2_bound = false
var protons = 1


func _ready():
	if current_globulin_type == GLOBULIN_TYPE.alpha:
		material_override.albedo_texture = load(alpha_icon)
	elif current_globulin_type == GLOBULIN_TYPE.beta:
		material_override.albedo_texture = load(beta_icon)

	if defective:
		material_override.albedo_color = Color(0.3, 0.3, 0.3)
