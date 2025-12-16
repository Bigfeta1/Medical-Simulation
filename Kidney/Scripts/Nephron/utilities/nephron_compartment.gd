extends Node
class_name NephronCompartment

## Component for tracking ion/solute particles in nephron compartments
## Can be attached to any node type (AnimatedSprite3D, MeshInstance3D, etc.)
## Provides electrochemical field calculations

signal concentrations_updated

var electrochemical_field: ElectrochemicalField

#region ION/SOLUTE COUNTS
# Display values (scaled in debug mode for human readability)
var sodium: int = 0
var potassium: int = 0
var chloride: int = 0
var amino_acids: int = 0
var glucose: int = 0
var water: int = 0
var carbon_dioxide: int = 0
var carbonic_acid: int = 0
var bicarbonate: int = 0
var protons: int = 0

# Actual particle counts (always realistic, never scaled)
var actual_sodium: float = 0
var actual_potassium: float = 0
var actual_chloride: float = 0
var actual_amino_acids: float = 0
var actual_glucose: float = 0
var actual_water: float = 0
var actual_carbon_dioxide: float = 0
var actual_carbonic_acid: float = 0
var actual_bicarbonate: float = 0
var actual_protons: float = 0
#endregion

# Compartment volume (liters) - override in child classes
@export var volume: float = 1e-12

# Debug mode: scale down particle counts for easier tracking
@export var debug_mode: bool = false:
	set(value):
		debug_mode = value
		if is_node_ready():
			_initialize_concentrations()

@export var debug_scale_factor: float = 1.32e-5  # Scale factor to make smallest value = 1

func _ready():
	# Find ElectrochemicalField child if it exists
	for child in get_parent().get_children():
		if child is ElectrochemicalField:
			electrochemical_field = child
			break

	_initialize_concentrations()
	if electrochemical_field:
		electrochemical_field.volume = volume

## Override this in child classes to set compartment-specific concentrations
func _initialize_concentrations():
	pass

## Helper function to set concentration from mM value
## Automatically calculates actual particle count and scaled display value
func set_concentration(ion_name: String, concentration_mM: float):
	var actual_count = concentration_mM * 1e-3 * volume * 6.022e23
	var scale = debug_scale_factor if debug_mode else 1.0
	var display_count = int(actual_count * scale)

	match ion_name.to_lower():
		"sodium", "na":
			actual_sodium = actual_count
			sodium = display_count
		"potassium", "k":
			actual_potassium = actual_count
			potassium = display_count
		"chloride", "cl":
			actual_chloride = actual_count
			chloride = display_count
		"glucose":
			actual_glucose = actual_count
			glucose = display_count
		"bicarbonate", "hco3":
			actual_bicarbonate = actual_count
			bicarbonate = display_count
		"protons", "h":
			actual_protons = actual_count
			protons = display_count
		"amino_acids":
			actual_amino_acids = actual_count
			amino_acids = display_count
		"water", "h2o":
			actual_water = actual_count
			water = display_count
		"carbon_dioxide", "co2":
			actual_carbon_dioxide = actual_count
			carbon_dioxide = display_count
		"carbonic_acid", "h2co3":
			actual_carbonic_acid = actual_count
			carbonic_acid = display_count

## Get concentration in mM from actual particle count
func get_concentration(ion_name: String) -> float:
	if electrochemical_field:
		return electrochemical_field.get_ion_concentration(ion_name)
	return 0.0
