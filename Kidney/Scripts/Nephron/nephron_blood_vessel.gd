extends MeshInstance3D

signal concentrations_updated

@onready var electrochemical_field = $ElectrochemicalField
@onready var kidney = get_parent().get_parent().get_parent()
@onready var solute_display = $SoluteDisplay

# Compartment ion/solute counts
var sodium: int = 0
var potassium: int = 0
var chloride: int = 0
var amino_acids: int = 0
var glucose: int = 0
var water: int = 0
var bicarbonate: int = 0
var protons: int = 0
var co2: int = 0
var carbonic_acid: int = 0

var actual_sodium: float = 0
var actual_potassium: float = 0
var actual_chloride: float = 0
var actual_amino_acids: float = 0
var actual_glucose: float = 0
var actual_water: float = 0
var actual_bicarbonate: float = 0
var actual_protons: float = 0
var actual_co2: float = 0
var actual_carbonic_acid: float = 0

var volume: float = 5e-12

@export var debug_mode: bool = false:
	set(value):
		debug_mode = value
		if is_node_ready():
			_initialize_concentrations()

@export var debug_scale_factor: float = 1.32e-5

func _ready():
	kidney.state_changed.connect(_on_kidney_state_changed)
	
	# Set electrochemical field volume
	if electrochemical_field:
		electrochemical_field.volume = volume

	CompartmentRegistry.register_scoped("kidney.pct", "blood", self)

	_initialize_concentrations()

func _initialize_concentrations():
	# Physiologically accurate blood plasma concentrations (extracellular fluid)
	set_concentration("sodium", 140.0)     # 140 mM - plasma Na+
	set_concentration("potassium", 5.0)    # 5 mM - plasma K+
	set_concentration("chloride", 110.0)   # 110 mM - plasma Cl-
	set_concentration("glucose", 5.0)      # 5 mM - plasma glucose
	set_concentration("bicarbonate", 24.0) # 24 mM - plasma HCO3-
	set_concentration("protons", 0.00004)  # 40 nM (pH 7.4, slightly more basic than cell)
	set_concentration("amino_acids", 2.5)  # 2.5 mM - plasma amino acids

	# Water in blood plasma (~93% water by volume)
	set_concentration("water", 51000.0)    # 51 M - plasma water

	# CO2 in blood (arterial PCO2 = 40 mmHg)
	set_concentration("co2", 1.2)          # 1.2 mM - dissolved CO2

	# Carbonic Acid (very low, transient)
	set_concentration("carbonic_acid", 0.0003)  # 0.3 μM

	concentrations_updated.emit()

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
		"co2", "carbon_dioxide":
			actual_co2 = actual_count
			co2 = display_count
		"carbonic_acid", "h2co3":
			actual_carbonic_acid = actual_count
			carbonic_acid = display_count

func _on_kidney_state_changed(_old_state, new_state):
	if new_state == kidney.SelectionState.PCT:
		await get_tree().create_timer(0.4).timeout
		solute_display.visible = true
	else:
		solute_display.visible = false
