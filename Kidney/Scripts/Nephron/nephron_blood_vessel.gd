extends MeshInstance3D

signal concentrations_updated

@onready var electrochemical_field = $ElectrochemicalField

var compartment: PCTBloodCompartment

# Compartment variables (delegated to compartment instance)
var sodium: int = 0
var potassium: int = 0
var chloride: int = 0
var amino_acids: int = 0
var glucose: int = 0
var water: int = 0
var bicarbonate: int = 0
var protons: int = 0

var actual_sodium: float = 0
var actual_potassium: float = 0
var actual_chloride: float = 0
var actual_amino_acids: float = 0
var actual_glucose: float = 0
var actual_water: float = 0
var actual_bicarbonate: float = 0
var actual_protons: float = 0

var volume: float = 5e-12

func _ready():
	# Create compartment instance
	compartment = PCTBloodCompartment.new()
	add_child(compartment)

	# Connect compartment signal to relay it
	compartment.concentrations_updated.connect(_on_compartment_updated)

	# Set electrochemical field volume
	if electrochemical_field:
		electrochemical_field.volume = volume

func _on_compartment_updated():
	# Copy values from compartment for display access
	sodium = compartment.sodium
	potassium = compartment.potassium
	chloride = compartment.chloride
	amino_acids = compartment.amino_acids
	glucose = compartment.glucose
	water = compartment.water
	bicarbonate = compartment.bicarbonate
	protons = compartment.protons

	actual_sodium = compartment.actual_sodium
	actual_potassium = compartment.actual_potassium
	actual_chloride = compartment.actual_chloride
	actual_amino_acids = compartment.actual_amino_acids
	actual_glucose = compartment.actual_glucose
	actual_water = compartment.actual_water
	actual_bicarbonate = compartment.actual_bicarbonate
	actual_protons = compartment.actual_protons

	concentrations_updated.emit()
