extends Node

@onready var kidney = get_node("/root/Main/Kidney")
@onready var compartment_node = get_parent().get_parent()  # SoluteDisplay -> Compartment (BloodVessel or PCTCell)

##Labels - Column1 and Column2 under parent (SoluteDisplay)
@onready var sodium_label = get_parent().get_node("Column1/VBoxContainer/Electrolytes/SodiumLabel")
@onready var potassium_label = get_parent().get_node("Column1/VBoxContainer/Electrolytes/PotassiumLabel")
@onready var chloride_label = get_parent().get_node("Column1/VBoxContainer/Electrolytes/ChlorideLabel")
@onready var glucose_label = get_parent().get_node("Column1/VBoxContainer/LargeComponents/GlucoseLabel")
@onready var amino_acid_label = get_parent().get_node("Column1/VBoxContainer/LargeComponents/AminoAcidLabel")

@onready var water_label = get_parent().get_node("Column1/VBoxContainer/AcidBase/WaterLabel")
@onready var carbon_dioxide_label = get_parent().get_node("Column1/VBoxContainer/AcidBase/CarbonDioxideLabel")
@onready var carbonic_acid_label = get_parent().get_node("Column1/VBoxContainer/AcidBase/CarbonicAcidLabel")

@onready var proton_label = get_parent().get_node("Column1/VBoxContainer/AcidBase2/ProtonLabel")
@onready var bicarbonate_label = get_parent().get_node("Column1/VBoxContainer/AcidBase2/BicarbonateLabel")


@onready var membrane_potential_label = get_parent().get_node("Column2/VBoxContainer/Electrochemical/VoltageLabel")

# Display mode toggle
var show_moles: bool = false
const AVOGADRO: float = 6.022e23


func _ready():
	kidney.state_changed.connect(_on_state_changed)
	compartment_node.concentrations_updated.connect(_update_display)

	var state = kidney.current_display_state
	if state == kidney.SelectionState.PCT:
		_update_display()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if kidney.current_display_state == kidney.SelectionState.PCT:
			show_moles = !show_moles
			_update_display()

func _format_value(actual_count: float) -> String:
	if show_moles:
		var moles = actual_count / AVOGADRO
		return str(moles) + " mol"
	else:
		return str(int(actual_count))

func _update_display():
	if show_moles:
		sodium_label.text = "Sodium: " + _format_value(compartment_node.actual_sodium)
		potassium_label.text = "Potassium: " + _format_value(compartment_node.actual_potassium)
		chloride_label.text = "Chloride: " + _format_value(compartment_node.actual_chloride)
		glucose_label.text = "Glucose: " + _format_value(compartment_node.actual_glucose)
		amino_acid_label.text = "Amino Acids: " + _format_value(compartment_node.actual_amino_acids)

		water_label.text = "H20: " + _format_value(compartment_node.actual_water)
		carbon_dioxide_label.text = "CO2: " + _format_value(compartment_node.actual_co2)
		carbonic_acid_label.text = "Carbonic Acid: " + _format_value(compartment_node.actual_carbonic_acid)

		proton_label.text = "H+: " + _format_value(compartment_node.actual_protons)
		bicarbonate_label.text = "Bicarbonate: " + _format_value(compartment_node.actual_bicarbonate)
	else:
		sodium_label.text = "Sodium: " + str(compartment_node.sodium)
		potassium_label.text = "Potassium: " + str(compartment_node.potassium)
		chloride_label.text = "Chloride: " + str(compartment_node.chloride)
		glucose_label.text = "Glucose: " + str(compartment_node.glucose)
		amino_acid_label.text = "Amino Acids: " + str(compartment_node.amino_acids)

		water_label.text = "H20: " + str(compartment_node.water)
		carbon_dioxide_label.text = "CO2: " + str(compartment_node.co2)
		carbonic_acid_label.text = "Carbonic Acid: " + str(compartment_node.carbonic_acid)

		proton_label.text = "H+: " + str(compartment_node.protons)
		bicarbonate_label.text = "Bicarbonate: " + str(compartment_node.bicarbonate)

	if compartment_node.electrochemical_field and membrane_potential_label:
		# Show dynamic membrane potential (not just GHK equilibrium)
		var potential = compartment_node.electrochemical_field.membrane_potential
		membrane_potential_label.text = "Membrane Potential: %.1f mV" % potential

func _on_state_changed(state):
	if state == kidney.SelectionState.PCT:
		_update_display()
