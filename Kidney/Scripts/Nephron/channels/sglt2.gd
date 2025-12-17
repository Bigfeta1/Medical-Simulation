extends IonChannel

# SGLT2 cotransporter states
enum TransporterState {
	EMPTY,              # No substrates bound, ready to bind Na+ or Glucose
	NA_BOUND,           # Na+ bound, waiting for glucose
	GLUCOSE_BOUND,      # Glucose bound, waiting for Na+
	BOTH_BOUND,         # Both substrates bound, calculating thermodynamic favorability
	TRANSLOCATING,      # Conformational change moving substrates across membrane
	RELEASING           # Releasing substrates to cell side
}

var current_state: TransporterState = TransporterState.EMPTY
var state_timer: float = 0.0
var cycling: bool = false

# Michaelis-Menten constants for substrate binding
const KM_NA = 20.0      # mM - half-maximal Na+ binding concentration for SGLT2
const KM_GLUCOSE = 2.0  # mM - half-maximal glucose binding concentration

# Binding rate constants (tuned for ~5-10% chance per frame at physiological concentrations)
const NA_BINDING_RATE = 12.0
const GLUCOSE_BINDING_RATE = 15.0

# State durations for deterministic steps
const STATE_DURATIONS = {
	TransporterState.TRANSLOCATING: 0.005,  # 5ms - conformational change
	TransporterState.RELEASING: 0.003       # 3ms - substrate release
}

# Transport count per activation (representing multiple transporters)
# Real PCT cell has ~500 SGLT2, each cycling at ~150 s^-1
# Each simulation cycle should represent: 500 transporters × 1 ion each = 500 ions
# But we batch them: 500 × 100 = 50,000 for performance (still 20x less than before)
var transport_count = 5e4  # Reduced from 1e6 for realistic timescales

# ============================================================================
# THERMODYNAMIC CONSTANTS (Publication-Grade Biophysics)
# ============================================================================

# Physical constants
const R = 8.314          # J/(mol·K) - Universal gas constant
const T = 310.0          # K - Body temperature (37°C)
const F = 96485.0        # C/mol - Faraday constant
const Z_NA = 1.0         # Na+ charge
const Z_GLUCOSE = 0.0    # Glucose is uncharged

# Transition state theory parameters
const K0 = 150.0             # s^-1 - Symmetric basal rate constant (same for forward and backward for detailed balance)
const ACTIVATION_BARRIER = 15.0  # kJ/mol - Energy barrier for conformational change (tuned for rapid activation with pre-loaded gradients)
const MAX_RATE = 500.0       # s^-1 - Physical cap on transport rate (prevents numerical blowup under extreme gradients)

# Stoichiometry
const NA_STOICHIOMETRY = 1    # 1 Na+ per transport cycle
const GLUCOSE_STOICHIOMETRY = 1  # 1 Glucose per transport cycle

# Compartment references (cached)
var lumen = null
var cell = null

# Substrate binding flags
var na_bound: int = 0
var glucose_bound: int = 0

# Concentration floor to prevent log(0) singularities
const CONCENTRATION_EPSILON = 1e-9  # mM

func _ready():
	super._ready()

	# Cache compartment references
	lumen = CompartmentRegistry.get_compartment("kidney.pct.lumen")
	cell = CompartmentRegistry.get_compartment("kidney.pct.cell")

	if not lumen or not cell:
		push_error("SGLT2: Could not find compartments")

# ============================================================================
# THERMODYNAMIC FREE ENERGY CALCULATION
# ============================================================================

func _calculate_free_energy_change() -> float:
	"""
	Calculate ΔG for Na+/Glucose cotransport from lumen → cell

	ΔG_total = ΔG_Na + ΔG_glucose

	Where for each species:
	ΔG_i = n_i * RT * ln([i]_in / [i]_out) + n_i * z_i * F * ΔV

	Convention:
	- "out" = lumen (source)
	- "in" = cell (destination)
	- ΔV = V_cell - V_lumen (transmembrane potential, apical membrane)

	Negative ΔG → thermodynamically favorable (spontaneous forward transport)
	Positive ΔG → thermodynamically unfavorable (would require energy input)

	Returns: ΔG in kJ/mol
	"""

	# Get electrochemical fields for voltage calculation
	var lumen_field = lumen.get_node_or_null("ElectrochemicalField")
	var cell_field = cell.get_node_or_null("ElectrochemicalField")

	if not lumen_field or not cell_field:
		push_warning("SGLT2: Cannot calculate ΔG without electrochemical fields")
		return 0.0

	# Calculate transmembrane potential (V_cell - V_lumen)
	# Use dynamic membrane_potential from current integration
	# Assume lumen is grounded at 0 mV (reference), so ΔV = V_cell - 0 = V_cell
	var delta_v = cell_field.membrane_potential  # mV (V_cell - V_lumen, lumen ≈ 0 mV)
	delta_v = delta_v / 1000.0  # Convert mV → V

	# Get concentrations in mM with floor to prevent log(0)
	var na_lumen = max(lumen_field.get_ion_concentration("na"), CONCENTRATION_EPSILON)
	var na_cell = max(cell_field.get_ion_concentration("na"), CONCENTRATION_EPSILON)
	var glucose_lumen = max(lumen_field.get_ion_concentration("glucose"), CONCENTRATION_EPSILON)
	var glucose_cell = max(cell_field.get_ion_concentration("glucose"), CONCENTRATION_EPSILON)

	# ΔG for Na+ transport (lumen → cell)
	# ΔG_Na = RT ln([Na+]_cell / [Na+]_lumen) + zF(V_cell - V_lumen)
	var concentration_term_na = R * T * log(na_cell / na_lumen)  # J/mol
	var electrical_term_na = Z_NA * F * delta_v  # J/mol
	var delta_g_na = (concentration_term_na + electrical_term_na) / 1000.0  # kJ/mol

	# ΔG for Glucose transport (lumen → cell)
	# ΔG_glucose = RT ln([Glucose]_cell / [Glucose]_lumen)
	# No electrical term (glucose is uncharged)
	var delta_g_glucose = (R * T * log(glucose_cell / glucose_lumen)) / 1000.0  # kJ/mol

	# Total free energy change (accounting for stoichiometry)
	var delta_g_total = (NA_STOICHIOMETRY * delta_g_na) + (GLUCOSE_STOICHIOMETRY * delta_g_glucose)

	return delta_g_total  # kJ/mol

# ============================================================================
# TRANSITION STATE THEORY - THERMODYNAMICALLY CONSISTENT RATES
# ============================================================================

func _calculate_forward_rate() -> float:
	"""
	Calculate forward transport rate using transition state theory with symmetric barrier splitting

	k_forward = k0 * exp(-(ΔG‡ + ΔG/2) / RT)

	This ensures thermodynamic consistency:
	k_forward / k_backward = exp(-ΔG / RT)

	When ΔG < 0 (favorable gradients): rate increases exponentially
	When ΔG > 0 (unfavorable gradients): rate decreases exponentially

	Returns: rate in s^-1 (probability per second)
	"""

	var delta_g = _calculate_free_energy_change()  # kJ/mol
	var RT_kJ = (R * T) / 1000.0  # kJ/mol (≈ 2.58 kJ/mol at 37°C)

	# Symmetric splitting: forward barrier includes +ΔG/2
	var effective_barrier = ACTIVATION_BARRIER + (0.5 * delta_g)

	# DEBUG
	if Engine.get_process_frames() % 180 == 0:
		pass
		# print("[SGLT2 RATE DEBUG] RT_kJ = %.3f | ΔG = %.2f | Barrier before clamp = %.2f" % [RT_kJ, delta_g, effective_barrier])

	# Clamp barrier to prevent numerical overflow (both high and low extremes)
	# Note: This breaks strict detailed balance when ΔG is extreme, trading thermodynamic
	# purity for numerical stability. We compensate by also capping the final rate.
	effective_barrier = clamp(effective_barrier, 5.0, 200.0)

	# Transition state theory rate equation with symmetric prefactor
	var exponent = -effective_barrier / RT_kJ
	var rate = K0 * exp(exponent)

	# DEBUG
	if Engine.get_process_frames() % 180 == 0:
		pass
		# print("[SGLT2 RATE DEBUG] Barrier after clamp = %.2f | Exponent = %.2f | Rate = %.4f s⁻¹" % [effective_barrier, exponent, rate])

	# Cap at physiologically plausible max rate
	# This is the primary safety mechanism - ensures rates stay reasonable
	return min(rate, MAX_RATE)

func _calculate_backward_rate() -> float:
	"""
	Calculate backward transport rate (cell → lumen reversal)

	k_backward = k0 * exp(-(ΔG‡ - ΔG/2) / RT)

	Thermodynamic consistency proof:
	k_forward / k_backward = exp(-(ΔG‡ + ΔG/2 - ΔG‡ + ΔG/2) / RT)
	                       = exp(-ΔG / RT)  ✓

	At equilibrium (ΔG = 0): forward = backward
	When ΔG << 0: forward >> backward (strongly favored direction)

	Note: Barrier clamping in extreme regimes distorts this ratio slightly,
	trading strict detailed balance for numerical stability.
	"""

	var delta_g = _calculate_free_energy_change()  # kJ/mol
	var RT_kJ = (R * T) / 1000.0  # kJ/mol

	# Symmetric splitting: backward barrier includes -ΔG/2
	var effective_barrier = ACTIVATION_BARRIER - (0.5 * delta_g)

	# Clamp barrier (same range as forward for symmetry)
	effective_barrier = clamp(effective_barrier, 5.0, 200.0)

	# Transition state theory rate equation with symmetric prefactor
	var rate = K0 * exp(-effective_barrier / RT_kJ)

	# Cap at max rate
	return min(rate, MAX_RATE)

# ============================================================================
# AUTOMATIC THERMODYNAMIC ACTIVATION
# ============================================================================

func _attempt_thermodynamic_activation(delta):
	"""
	Probabilistically activate transport based on thermodynamic driving force

	Uses transition state theory:
	- Forward rate increases when ΔG < 0 (favorable gradients)
	- Backward rate increases when ΔG > 0 (unfavorable gradients)

	The transporter "chooses" direction based on which rate wins the stochastic race.
	This is true biophysical behavior - no hardcoded directionality.
	"""

	if cycling:
		return  # Already in transport cycle

	# Calculate thermodynamics
	if Engine.get_process_frames() % 60 == 0:
		pass
		# print("[SGLT2 DEBUG] About to calculate ΔG...")

	var delta_g = _calculate_free_energy_change()

	if Engine.get_process_frames() % 60 == 0:
		pass
		# print("[SGLT2 DEBUG] ΔG calculated: %.2f kJ/mol, now calculating rates..." % delta_g)

	var forward_rate = _calculate_forward_rate()   # s^-1 (lumen → cell)
	var backward_rate = _calculate_backward_rate()  # s^-1 (cell → lumen)

	# Debug output (every 120 frames = ~2 seconds for less spam)
	if Engine.get_process_frames() % 120 == 0:
		var lumen_field = lumen.get_node_or_null("ElectrochemicalField")
		var cell_field = cell.get_node_or_null("ElectrochemicalField")
		var na_lumen = lumen_field.get_ion_concentration("na") if lumen_field else 0
		var na_cell = cell_field.get_ion_concentration("na") if cell_field else 0
		# 		print("[SGLT2 COUPLING] [Na+]_lumen=%.2f mM, [Na+]_cell=%.2f mM | ΔG=%.2f kJ/mol | k_fwd=%.3f s⁻¹ (~%.1f%% chance/frame)" % [na_lumen, na_cell, delta_g, forward_rate, forward_rate * delta * 100])

	# Stochastic competition: each direction attempts activation per frame
	var forward_probability = forward_rate * delta
	var backward_probability = backward_rate * delta

	# Forward transport attempt (lumen → cell)
	if randf() < forward_probability:
		_start_forward_transport()
		return

	# Backward transport attempt (cell → lumen)
	# Note: Under normal physiology, this is extremely rare (ΔG << 0 makes backward rate tiny)
	if randf() < backward_probability:
		_start_backward_transport()
		return

func _start_forward_transport():
	"""
	Initiate forward transport cycle (lumen → cell)
	This is the normal physiological direction driven by Na+ gradient
	"""

	cycling = true
	current_state = TransporterState.TRANSLOCATING
	state_timer = 0.0

	var delta_g = _calculate_free_energy_change()
	# 	print("[SGLT2] BOTH_BOUND → TRANSLOCATING (FORWARD): ΔG = %.2f kJ/mol (thermodynamically favorable)" % delta_g)

func _start_backward_transport():
	"""
	Initiate backward transport cycle (cell → lumen)
	This would only occur if gradients reverse (e.g., Na-K-ATPase failure)

	Requires releasing substrates back to lumen instead of cell
	"""

	# Release substrates back to lumen (reverse the binding)
	if na_bound > 0:
		lumen.sodium += na_bound
		lumen.actual_sodium += na_bound
		lumen.concentrations_updated.emit()

	if glucose_bound > 0:
		lumen.glucose += glucose_bound
		lumen.actual_glucose += glucose_bound
		lumen.concentrations_updated.emit()

	var delta_g = _calculate_free_energy_change()
	# 	print("[SGLT2] BOTH_BOUND → EMPTY (BACKWARD): ΔG = %.2f kJ/mol (reverse transport, gradients collapsed!)" % delta_g)

	# Reset to empty state
	na_bound = 0
	glucose_bound = 0
	current_state = TransporterState.EMPTY
	cycling = false

func _process(delta):
	super._process(delta)  # Preserve shader updates

	match current_state:
		TransporterState.EMPTY:
			# Attempt to bind either Na+ or Glucose independently
			_attempt_na_binding_probabilistic(delta)
			_attempt_glucose_binding_probabilistic(delta)

		TransporterState.NA_BOUND:
			# Na+ bound, try to bind glucose
			_attempt_glucose_binding_probabilistic(delta)

		TransporterState.GLUCOSE_BOUND:
			# Glucose bound, try to bind Na+
			_attempt_na_binding_probabilistic(delta)

		TransporterState.BOTH_BOUND:
			# Automatic activation based on thermodynamic favorability
			_attempt_thermodynamic_activation(delta)

		_:
			# Deterministic timed states
			if cycling:
				state_timer += delta
				var current_duration = STATE_DURATIONS.get(current_state, 0.0)
				if state_timer >= current_duration:
					_advance_state()
					state_timer = 0.0

func _attempt_na_binding_probabilistic(delta):
	# Skip if Na+ already bound
	if current_state == TransporterState.NA_BOUND or current_state == TransporterState.BOTH_BOUND:
		return

	var na_to_bind = 1 * transport_count

	if lumen.sodium < na_to_bind:
		return  # Not enough substrate

	# Calculate lumen Na+ concentration in mM
	var na_concentration_mM = (lumen.actual_sodium / (lumen.volume * 6.022e23)) * 1e3

	# Michaelis-Menten binding probability
	var fractional_saturation = na_concentration_mM / (KM_NA + na_concentration_mM)

	# Probability of binding this frame
	var binding_probability = fractional_saturation * NA_BINDING_RATE * delta

	# Stochastic binding event
	if randf() < binding_probability:
		# Bind Na+ - REMOVE from lumen (sequestered on transporter)
		lumen.sodium -= na_to_bind
		lumen.actual_sodium -= na_to_bind
		na_bound = na_to_bind
		lumen.concentrations_updated.emit()

		# Update state based on whether glucose is already bound
		if current_state == TransporterState.GLUCOSE_BOUND:
			current_state = TransporterState.BOTH_BOUND
			# 			print("[SGLT2] GLUCOSE_BOUND → BOTH_BOUND: Bound %d Na+ ([Na+]=%0.2f mM, saturation=%0.1f%%)" % [na_to_bind, na_concentration_mM, fractional_saturation * 100])
		else:
			current_state = TransporterState.NA_BOUND
			# 			print("[SGLT2] EMPTY → NA_BOUND: Bound %d Na+ ([Na+]=%0.2f mM, saturation=%0.1f%%)" % [na_to_bind, na_concentration_mM, fractional_saturation * 100])

func _attempt_glucose_binding_probabilistic(delta):
	# Skip if glucose already bound
	if current_state == TransporterState.GLUCOSE_BOUND or current_state == TransporterState.BOTH_BOUND:
		return

	var glucose_to_bind = 1 * transport_count

	if lumen.glucose < glucose_to_bind:
		return  # Not enough substrate

	# Calculate lumen glucose concentration in mM
	var glucose_concentration_mM = (lumen.actual_glucose / (lumen.volume * 6.022e23)) * 1e3

	# Michaelis-Menten binding probability
	var fractional_saturation = glucose_concentration_mM / (KM_GLUCOSE + glucose_concentration_mM)

	# Probability of binding this frame
	var binding_probability = fractional_saturation * GLUCOSE_BINDING_RATE * delta

	# Stochastic binding event
	if randf() < binding_probability:
		# Bind glucose - REMOVE from lumen (sequestered on transporter)
		lumen.glucose -= glucose_to_bind
		lumen.actual_glucose -= glucose_to_bind
		glucose_bound = glucose_to_bind
		lumen.concentrations_updated.emit()

		# Update state based on whether Na+ is already bound
		if current_state == TransporterState.NA_BOUND:
			current_state = TransporterState.BOTH_BOUND
			# 			print("[SGLT2] NA_BOUND → BOTH_BOUND: Bound %d Glucose ([Glucose]=%0.2f mM, saturation=%0.1f%%)" % [glucose_to_bind, glucose_concentration_mM, fractional_saturation * 100])
		else:
			current_state = TransporterState.GLUCOSE_BOUND
			# 			print("[SGLT2] EMPTY → GLUCOSE_BOUND: Bound %d Glucose ([Glucose]=%0.2f mM, saturation=%0.1f%%)" % [glucose_to_bind, glucose_concentration_mM, fractional_saturation * 100])

func activate():
	super.activate()  # Pulse animation

	if cycling:
		# 		print("[SGLT2] Cannot activate: Already cycling (current state: %s)" % TransporterState.keys()[current_state])
		return

	# Can only activate if BOTH substrates are bound
	if current_state != TransporterState.BOTH_BOUND or na_bound == 0 or glucose_bound == 0:
		push_warning("[SGLT2] Cannot activate: Both Na+ and Glucose must be bound (current state: %s)" % TransporterState.keys()[current_state])
		return

	# Start conformational change cycle
	cycling = true
	current_state = TransporterState.TRANSLOCATING
	state_timer = 0.0
	# 	print("[SGLT2] BOTH_BOUND → TRANSLOCATING: Starting conformational change")

func _advance_state():
	match current_state:
		TransporterState.TRANSLOCATING:
			# Conformational change complete, now release substrates to cell
			current_state = TransporterState.RELEASING
			state_timer = 0.0
			# 			print("[SGLT2] TRANSLOCATING → RELEASING: Conformational change complete (5ms)")

		TransporterState.RELEASING:
			# Release both substrates to cell
			_release_substrates()

			# Report inward Na+ current to electrochemical field
			# SGLT2 moves Na+ from lumen → cell (inward = depolarizing)
			# Current convention: positive = depolarizing (inward positive charge)
			if cell and cell.electrochemical_field and na_bound > 0:
				var translocation_time = STATE_DURATIONS.get(TransporterState.TRANSLOCATING, 0.005)  # 5ms
				var na_flux_per_second = na_bound / translocation_time  # Na+ ions/second
				cell.electrochemical_field.add_transporter_current("sglt2", na_flux_per_second, +1.0)

			current_state = TransporterState.EMPTY
			cycling = false
			var released_na = na_bound
			var released_glucose = glucose_bound
			na_bound = 0
			glucose_bound = 0
			state_timer = 0.0

func _release_substrates():
	# Release Na+ to cell
	if na_bound > 0:
		cell.sodium += na_bound
		cell.actual_sodium += na_bound
		cell.concentrations_updated.emit()

	# Release glucose to cell
	if glucose_bound > 0:
		cell.glucose += glucose_bound
		cell.actual_glucose += glucose_bound
		cell.concentrations_updated.emit()
