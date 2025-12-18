extends AnimatedSprite3D

signal concentrations_updated

@onready var front = $PCTCellFront
@onready var carbonic_anhydrase = $CarbonicAnhydrase
@onready var electrochemical_field = $ElectrochemicalField

@onready var kidney = get_parent().get_parent().get_parent()
@onready var solute_display = $SoluteDisplay



var compartment: PCTCellCompartment

var atp: int = 0 #power
var na_k_pump_activity = 1.0

var apical_transporters = []
var basolateral_transporters = []

# Compartment ion/solute counts
var sodium: int = 0
var potassium: int = 0
var chloride: int = 0
var amino_acids: int = 0
var glucose: int = 0
var co2: int = 0
var water: int = 0
var carbonic_acid: int = 0
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
var actual_co2: float = 0
var actual_carbonic_acid: float = 0

var volume: float = 2e-12
@export var debug_mode: bool = false:
	set(value):
		debug_mode = value
		if is_node_ready():
			_initialize_concentrations()
@export var debug_scale_factor: float = 1.32e-5

func _ready():
	kidney.state_changed.connect(_on_kidney_state_changed)
	
	# Set volume FIRST before anything else that might trigger calculations
	if electrochemical_field:
		electrochemical_field.volume = volume

	CompartmentRegistry.register_scoped("kidney.pct", "cell", self)

	play()
	front.play()
	carbonic_anhydrase.play()
	
	_initialize_concentrations()

func _initialize_concentrations():
	# Pre-loaded steady-state concentrations (as if pump has been running)
	set_concentration("sodium", 12.0)      # Low - pumped out by Na-K-ATPase
	set_concentration("potassium", 140.0)  # High - pumped in by Na-K-ATPase
	set_concentration("chloride", 7.0)     # Low - to maintain -70 mV
	set_concentration("glucose", 5.0)
	set_concentration("bicarbonate", 24.0)
	set_concentration("protons", 0.000063) # 63 nM (pH 7.2)
	set_concentration("amino_acids", 2.0)

	# Water and CO2 for metabolic H+ production
	# Water: ~55 M (55,000 mM) - cytoplasm is ~70% water by mass
	# Intracellular water molarity ≈ (density 1g/mL × 0.7) / 18 g/mol ≈ 38.9 M ≈ 39,000 mM
	set_concentration("water", 39000.0)    # 39 M - intracellular water

	# CO2: Steady-state intracellular ~1.2 mM (equilibrium with metabolism + diffusion)
	# PCO2 ≈ 40 mmHg → dissolved CO2 ≈ 1.2 mM (Henry's law)
	set_concentration("co2", 1.2)          # 1.2 mM - dissolved CO2

	# Carbonic Acid (H2CO3): Equilibrium value at steady-state pH 7.2
	# H2CO3 ⇌ H+ + HCO3- (pKa = 3.6, extremely fast dissociation)
	# At equilibrium: [H2CO3] = [H+][HCO3-] / Keq
	# [H2CO3] = (0.000063 mM × 24 mM) / 0.251 mM ≈ 0.006 mM
	set_concentration("carbonic_acid", 0.006)  # 6 μM - equilibrium concentration

	var scale = debug_scale_factor if debug_mode else 1.0
	atp = int(5e-3 * volume * 6.022e23 * scale)

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

func _process(delta):
	front.frame = frame
	_equilibrate_carbonic_acid(delta)

# ============================================================================
# CARBONIC ACID DISSOCIATION EQUILIBRIUM
# ============================================================================

func _equilibrate_carbonic_acid(delta):
	"""
	H2CO3 ⇌ H+ + HCO3-

	Very fast dissociation reaction (pKa = 3.6)
	At physiological pH 7.2, equilibrium is ~99.99% dissociated

	Keq = [H+][HCO3-] / [H2CO3] = 10^-pKa = 10^-3.6 ≈ 2.5 × 10^-4 M

	This is instantaneous chemistry - no enzyme needed for this step
	(Carbonic anhydrase catalyzes the formation of H2CO3 from CO2, not its dissociation)
	"""

	# Physical constants
	const PKA = 3.6  # H2CO3 ⇌ H+ + HCO3-
	const KEQ = 2.51e-4  # M (10^-3.6)

	# Rate constants for dissociation (very fast, but finite)
	# Forward: H2CO3 → H+ + HCO3- (dissociation, very fast)
	const K_FORWARD = 1e5  # s^-1 (100,000 per second, essentially instantaneous)

	# Backward: H+ + HCO3- → H2CO3 (association, controlled by Keq)
	# k_backward = k_forward / Keq (detailed balance)
	const K_BACKWARD = K_FORWARD / (KEQ * 1000.0)  # Convert Keq from M to mM

	# Forward reaction: H2CO3 → H+ + HCO3- (only if H2CO3 exists)
	var forward_molecules = 0.0
	if actual_carbonic_acid > 0:
		var h2co3_mM = (actual_carbonic_acid / (volume * 6.022e23)) * 1e3
		var forward_rate = K_FORWARD * h2co3_mM * delta  # mM change
		forward_molecules = forward_rate * 1e-3 * volume * 6.022e23
		# Limit to available H2CO3 (can't dissociate more than exists)
		forward_molecules = min(forward_molecules, actual_carbonic_acid)

	# Backward reaction: H+ + HCO3- → H2CO3 (only if both exist)
	var backward_molecules = 0.0
	if actual_protons > 0 and actual_bicarbonate > 0:
		var h_mM = (actual_protons / (volume * 6.022e23)) * 1e3
		var hco3_mM = (actual_bicarbonate / (volume * 6.022e23)) * 1e3
		var backward_rate = K_BACKWARD * h_mM * hco3_mM * delta  # mM change (second order)
		backward_molecules = backward_rate * 1e-3 * volume * 6.022e23
		# Limit to available substrates
		backward_molecules = min(backward_molecules, actual_protons, actual_bicarbonate)

	# Net change
	var net_dissociation_molecules = forward_molecules - backward_molecules

	# Update pools
	# H2CO3 decreases by forward, increases by backward
	actual_carbonic_acid -= forward_molecules
	actual_carbonic_acid += backward_molecules

	# H+ and HCO3- increase by forward, decrease by backward
	actual_protons += forward_molecules
	actual_protons -= backward_molecules

	actual_bicarbonate += forward_molecules
	actual_bicarbonate -= backward_molecules

	# Update display values
	var scale = debug_scale_factor if debug_mode else 1.0
	carbonic_acid = int(actual_carbonic_acid * scale)
	protons = int(actual_protons * scale)
	bicarbonate = int(actual_bicarbonate * scale)

	# Emit update signal if significant change
	if abs(net_dissociation_molecules) > 1.0:
		concentrations_updated.emit()

func _on_kidney_state_changed(_old_state, new_state):
	if new_state == kidney.SelectionState.PCT:
		await get_tree().create_timer(0.4).timeout
		solute_display.visible = true
	else:
		solute_display.visible = false
