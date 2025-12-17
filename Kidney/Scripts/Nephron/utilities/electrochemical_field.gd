extends Node3D
class_name ElectrochemicalField

## Calculates electrochemical properties from ion distributions
## This is an emergent property calculator - it derives values from particle counts,
## not the other way around

# Physical constants
const FARADAY_CONSTANT = 96485.0  # C/mol
const GAS_CONSTANT = 8.314  # J/(mol·K)
const TEMPERATURE = 310.15  # Body temperature (37°C) in Kelvin
const ELEMENTARY_CHARGE = 1.602e-19  # Coulombs

# Membrane electrical properties
const MEMBRANE_CAPACITANCE = 1e-8  # F (10 nF = 10^-8 F)
# C_m = 1 µF/cm² × membrane area
# We're simulating ~50,000 transporters = significant membrane area
# For whole PCT cell: ~1000 µm² → 1 nF
# Scaled up 10× to 10 nF for numerical stability at 60 FPS
# tau = R_m × C_m should be ~10-100 ms for stable integration

# Compartment volume (in liters) - set by parent
var volume: float = 0.0

# Reference to parent compartment that stores ion concentrations
var parent_compartment = null

# Dynamic membrane potential (mV)
var membrane_potential: float = -70.0  # Initialize to typical resting potential

# Current tracking (Amperes)
var total_current: float = 0.0
var transporter_currents: Dictionary = {}  # {"sglt2": I_sglt2, "pump": I_pump, ...}

func _ready():
	parent_compartment = get_parent()
	# Initialize membrane potential to GHK resting value
	if parent_compartment and parent_compartment.has_method("get"):
		# Wait one frame for compartments to initialize
		await get_tree().process_frame
		membrane_potential = calculate_resting_potential()

func _process(delta):
	# Calculate GHK resting potential (equilibrium target)
	var ghk_potential = calculate_resting_potential()

	# Safety check for invalid GHK
	if is_nan(ghk_potential) or is_inf(ghk_potential):
		ghk_potential = -70.0  # Default fallback

	# Safety check for invalid membrane potential
	if is_nan(membrane_potential) or is_inf(membrane_potential):
		membrane_potential = ghk_potential

	# Very weak passive leak current prevents unbounded voltage drift
	# This represents tiny K+/Cl-/Na+ leak through lipid bilayer (not channels)
	# The Na-K-ATPase must actively maintain gradients against SGLT2 influx
	# Use extremely high R_m = 100 GΩ (extremely weak leak) so voltage can drift significantly
	var membrane_resistance = 1e11  # Ohms (100 GΩ - 100x weaker than before)
	var voltage_diff_mv = membrane_potential - ghk_potential  # mV
	var voltage_diff_volts = voltage_diff_mv / 1000.0  # Convert mV to V
	var relaxation_current = -voltage_diff_volts / membrane_resistance  # Amperes (Ohm's law)

	# Total current = transporter currents + very weak relaxation to GHK
	var net_current = total_current + relaxation_current
	var delta_v_mv = 0.0

	# Integrate membrane current to update voltage dynamically
	# dV/dt = I_total / C_m
	if net_current != 0.0 and not is_nan(net_current) and not is_inf(net_current):
		var dv_dt = net_current / MEMBRANE_CAPACITANCE  # V/s
		var delta_v_volts = dv_dt * delta  # V
		delta_v_mv = delta_v_volts * 1000.0  # mV
		membrane_potential += delta_v_mv

	# Clamp final voltage to physiological range (-200 to +100 mV) as safety
	membrane_potential = clamp(membrane_potential, -200.0, 100.0)

	# Periodic voltage summary (every 3 seconds) - only for cell compartment
	if Engine.get_process_frames() % 180 == 0 and parent_compartment and parent_compartment.name == "PCTCell":
		print("[Cell Voltage] V_m = %.3f mV | GHK = %.3f mV | Drift = %.3f mV" % [membrane_potential, ghk_potential, membrane_potential - ghk_potential])

	# Reset current accumulator each frame
	total_current = 0.0
	transporter_currents.clear()

## Register current from an active transporter
## transporter_name: identifier (e.g., "sglt2", "na_k_pump")
## ion_flux: net charge movement (particles/second)
## charge_per_ion: elementary charges (+1 for Na+, -1 for Cl-, etc.)
## positive current = inward positive / outward negative (depolarizing)
## negative current = outward positive / inward negative (hyperpolarizing)
func add_transporter_current(transporter_name: String, ion_flux: float, charge_per_ion: float):
	# Convert ion flux to current
	# I = (ions/s) × (charge/ion) × (elementary_charge)
	var current_amperes = ion_flux * charge_per_ion * ELEMENTARY_CHARGE

	transporter_currents[transporter_name] = current_amperes
	total_current += current_amperes

## Calculate total charge in compartment (in Coulombs)
## Uses actual particle counts (not debug-scaled values)
func calculate_total_charge() -> float:
	if not parent_compartment:
		return 0.0

	var total_charge = 0.0

	# Use actual_ variables if available, otherwise fall back to regular variables
	var na = parent_compartment.get("actual_sodium") if parent_compartment.get("actual_sodium") != null else parent_compartment.sodium
	var k = parent_compartment.get("actual_potassium") if parent_compartment.get("actual_potassium") != null else parent_compartment.potassium
	var h = parent_compartment.get("actual_protons") if parent_compartment.get("actual_protons") != null else parent_compartment.protons
	var cl = parent_compartment.get("actual_chloride") if parent_compartment.get("actual_chloride") != null else parent_compartment.chloride
	var hco3 = parent_compartment.get("actual_bicarbonate") if parent_compartment.get("actual_bicarbonate") != null else parent_compartment.bicarbonate

	# Positive charges
	total_charge += na * 1.0      # Na+ = +1
	total_charge += k * 1.0       # K+ = +1
	total_charge += h * 1.0       # H+ = +1

	# Negative charges
	total_charge += cl * -1.0     # Cl- = -1
	total_charge += hco3 * -1.0   # HCO3- = -1

	# Neutral species (glucose, amino acids, water) contribute nothing

	return total_charge

## Calculate membrane potential between this compartment and another
## Uses Goldman-Hodgkin-Katz equation with ion concentrations and permeabilities
## this compartment = intracellular, other_field = extracellular
func calculate_potential_difference(other_field: ElectrochemicalField) -> float:
	if not parent_compartment or volume == 0.0:
		return 0.0
	if not other_field or not other_field.parent_compartment or other_field.volume == 0.0:
		return 0.0

	# Get intracellular concentrations (this compartment)
	var k_in = get_ion_concentration("k")
	var na_in = get_ion_concentration("na")
	var cl_in = get_ion_concentration("cl")

	# Get extracellular concentrations (other compartment)
	var k_out = other_field.get_ion_concentration("k")
	var na_out = other_field.get_ion_concentration("na")
	var cl_out = other_field.get_ion_concentration("cl")

	if k_in <= 0 or na_in <= 0 or cl_in <= 0:
		return 0.0
	if k_out <= 0 or na_out <= 0 or cl_out <= 0:
		return 0.0

	# Relative membrane permeabilities at rest
	# P_K : P_Na : P_Cl ≈ 1.0 : 0.04 : 0.45
	var p_k = 1.0
	var p_na = 0.04
	var p_cl = 0.45

	# Goldman-Hodgkin-Katz equation:
	# V_m = (RT/F) * ln((P_K*[K+]out + P_Na*[Na+]out + P_Cl*[Cl-]in) / (P_K*[K+]in + P_Na*[Na+]in + P_Cl*[Cl-]out))
	# Note: Cl- is inverted (in/out swapped) because it's an anion

	var numerator = (p_k * k_out) + (p_na * na_out) + (p_cl * cl_in)
	var denominator = (p_k * k_in) + (p_na * na_in) + (p_cl * cl_out)

	if denominator <= 0:
		return 0.0

	# At 37°C: (RT/F) ≈ 26.7 mV, convert to log10: 26.7 * ln(10) ≈ 61.5 mV
	var potential_mv = 61.5 * log(numerator / denominator) / log(10)

	return potential_mv

## Calculate concentration of a specific ion (mM = mmol/L)
## Uses actual particle counts (not debug-scaled values)
func get_ion_concentration(ion_name: String) -> float:
	if not parent_compartment or volume == 0.0:
		return 0.0

	var particle_count = 0.0
	match ion_name.to_lower():
		"sodium", "na":
			particle_count = parent_compartment.actual_sodium
		"potassium", "k":
			particle_count = parent_compartment.actual_potassium
		"chloride", "cl":
			particle_count = parent_compartment.actual_chloride
		"glucose":
			particle_count = parent_compartment.actual_glucose
		"protons", "h":
			particle_count = parent_compartment.actual_protons
		"bicarbonate", "hco3":
			particle_count = parent_compartment.actual_bicarbonate
		"amino_acids":
			particle_count = parent_compartment.actual_amino_acids
		"water", "h2o":
			particle_count = parent_compartment.actual_water

	# Safety check for invalid particle counts
	if particle_count < 0 or is_nan(particle_count) or is_inf(particle_count):
		return 0.0

	# Convert particle count to concentration (mM)
	# particle_count is in actual particles, need to convert to mM
	# mM = (particles / Avogadro) / volume_L * 1000
	var moles = particle_count / 6.022e23
	var concentration_mM = (moles / volume) * 1000.0

	# Safety check for invalid concentration
	if is_nan(concentration_mM) or is_inf(concentration_mM):
		return 0.0

	return concentration_mM

## Calculate osmolality (mOsm/kg) from total particle count
func calculate_osmolality() -> float:
	if not parent_compartment or volume == 0.0:
		return 0.0

	var total_particles = 0
	total_particles += parent_compartment.sodium
	total_particles += parent_compartment.potassium
	total_particles += parent_compartment.chloride
	total_particles += parent_compartment.glucose
	total_particles += parent_compartment.protons
	total_particles += parent_compartment.bicarbonate
	total_particles += parent_compartment.amino_acids
	# Water molecules don't contribute significantly to osmolality in this context

	return total_particles / volume

## Calculate resting membrane potential (mV) using Goldman-Hodgkin-Katz equation
## Accounts for K+, Na+, and Cl- permeabilities
## Realistic PCT cells have ~-70 mV resting potential
## Pass external_compartment to use actual extracellular values instead of defaults
func calculate_resting_potential(external_compartment = null) -> float:
	if not parent_compartment or volume == 0.0:
		return 0.0

	# Get intracellular concentrations (mM)
	var k_in = get_ion_concentration("k")    # ~140 mM
	var na_in = get_ion_concentration("na")  # ~12 mM
	var cl_in = get_ion_concentration("cl")  # ~7 mM

	# Get extracellular concentrations - use actual blood compartment if available
	var k_out = 5.0      # mM (default)
	var na_out = 140.0   # mM (default)
	var cl_out = 110.0   # mM (default)

	if external_compartment and external_compartment.electrochemical_field:
		k_out = external_compartment.electrochemical_field.get_ion_concentration("k")
		na_out = external_compartment.electrochemical_field.get_ion_concentration("na")
		cl_out = external_compartment.electrochemical_field.get_ion_concentration("cl")

	if k_in <= 0 or na_in <= 0 or cl_in <= 0:
		return 0.0

	# Relative membrane permeabilities at rest
	# P_K : P_Na : P_Cl ≈ 1.0 : 0.04 : 0.45
	var p_k = 1.0
	var p_na = 0.04
	var p_cl = 0.45

	# Goldman-Hodgkin-Katz equation:
	# V_m = (RT/F) * ln((P_K*[K+]out + P_Na*[Na+]out + P_Cl*[Cl-]in) / (P_K*[K+]in + P_Na*[Na+]in + P_Cl*[Cl-]out))
	# Note: Cl- is inverted (in/out swapped) because it's an anion

	var numerator = (p_k * k_out) + (p_na * na_out) + (p_cl * cl_in)
	var denominator = (p_k * k_in) + (p_na * na_in) + (p_cl * cl_out)

	if denominator <= 0:
		return 0.0

	# At 37°C: (RT/F) ≈ 26.7 mV, convert to log10: 26.7 * ln(10) ≈ 61.5 mV
	var potential_mv = 61.5 * log(numerator / denominator) / log(10)

	return potential_mv

## Get electric field strength at a point (for future particle physics)
func get_field_strength_at_point(_point: Vector3) -> Vector3:
	# Placeholder for spatial field calculations
	# Would calculate E-field vector based on charge distribution
	return Vector3.ZERO
