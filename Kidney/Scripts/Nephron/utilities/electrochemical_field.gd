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

# Compartment volume (in liters) - set by parent
var volume: float = 0.0

# Reference to parent compartment that stores ion concentrations
var parent_compartment = null

func _ready():
	parent_compartment = get_parent()

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

	# Convert particle count to concentration (mM)
	# particle_count is in actual particles, need to convert to mM
	# mM = (particles / Avogadro) / volume_L * 1000
	var moles = particle_count / 6.022e23
	var concentration_mM = (moles / volume) * 1000.0

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
