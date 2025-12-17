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
@onready var proton_label = get_parent().get_node("Column1/VBoxContainer/AcidBase2/ProtonLabel")

@onready var membrane_potential_label = get_parent().get_node("Column2/VBoxContainer/Electrochemical/VoltageLabel")

func _ready():
	kidney.state_changed.connect(_on_state_changed)
	compartment_node.concentrations_updated.connect(_update_display)

	var state = kidney.current_display_state
	if state == kidney.SelectionState.PCT:
		_update_display()

func _update_display():
	sodium_label.text = "Sodium: " + str(compartment_node.sodium)
	potassium_label.text = "Potassium: " + str(compartment_node.potassium)
	chloride_label.text = "Chloride: " + str(compartment_node.chloride)
	glucose_label.text = "Glucose: " + str(compartment_node.glucose)
	amino_acid_label.text = "Amino Acids: " + str(compartment_node.amino_acids)

	water_label.text = "H20: " + str(compartment_node.water)
	carbon_dioxide_label.text = "CO2: " + str(compartment_node.water)
	proton_label.text = "H+: " + str(compartment_node.protons)

	if compartment_node.electrochemical_field and membrane_potential_label:
		# Show dynamic membrane potential (not just GHK equilibrium)
		var potential = compartment_node.electrochemical_field.membrane_potential
		membrane_potential_label.text = "Membrane Potential: %.1f mV" % potential

func _on_state_changed(state):
	if state == kidney.SelectionState.PCT:
		_update_display()
