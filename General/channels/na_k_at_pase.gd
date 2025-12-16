extends IonChannel

# Na-K-ATPase pump cycle states (Post-Albers scheme)
enum PumpState {
	E1_EMPTY,          # E1 - Empty, ready to bind Na+
	E1_NA_BOUND,       # E1 + 3Na+ bound, waiting for ATP
	E1P_NA_BOUND,      # E1-P + 3Na+ phosphorylated
	E2P_EMPTY,         # E2-P - Na+ released, empty, ready to bind K+
	E2P_K_BOUND,       # E2-P + 2K+ bound
	E2_K_BOUND,        # E2 + 2K+ dephosphorylated
	E1_K_BOUND         # E1 + 2K+ ready to release K+
}

var current_state: PumpState = PumpState.E1_EMPTY
var state_timer: float = 0.0
var cycling: bool = false

# Pump cycle timing (total ~17ms per cycle)
const CYCLE_TIME = 0.017  # 17 milliseconds

# Michaelis-Menten constants for substrate binding
const KM_NA = 15.0   # mM - half-maximal Na+ binding concentration
const KM_K = 1.5     # mM - half-maximal K+ binding concentration

# Binding rate constants (tuned so binding occurs within ~2-3ms at physiological concentrations)
# Target: 3ms average binding time for Na+ at 12 mM (44% saturation)
# At 60 FPS: 3ms = ~0.18 frames (extremely fast, need MUCH lower rate)
# For binding to take 3-5 frames (50-80ms perceived as "a few moments"):
# probability_per_frame = 0.444 * rate * 0.0167
# For ~20-30% chance per frame: rate ≈ 30-40
# For ~5-10% chance per frame: rate ≈ 8-15
const NA_BINDING_RATE = 10.0    # ~5% chance per frame at physiological [Na+]
const K_BINDING_RATE = 20.0     # ~13% chance per frame at physiological [K+]

# State durations for deterministic steps
const STATE_DURATIONS = {
	PumpState.E1P_NA_BOUND: 0.002,    # 2ms - ATP phosphorylation + conformational change
	PumpState.E2P_EMPTY: 0.004,       # 4ms - Na+ release (conformational change allows time for K+ to find binding site)
	PumpState.E2P_K_BOUND: 0.002,     # 2ms - Dephosphorylation
	PumpState.E1_K_BOUND: 0.003       # 3ms - Conformational change to release K+
}

# Pump cycle count per activation (representing multiple pumps)
var pump_count = 1e6

# Compartment references (cached)
var cell = null
var blood = null

# Substrate availability flags
var na_bound: int = 0
var k_bound: int = 0
var atp_consumed: bool = false

func _ready():
	super._ready()

	# Cache compartment references
	cell = CompartmentRegistry.get_compartment("kidney.pct.cell")
	blood = CompartmentRegistry.get_compartment("kidney.pct.blood")

	if not cell or not blood:
		push_error("Na_K_ATPase: Could not find compartments")

func _process(delta):
	super._process(delta)  # Preserve shader updates

	match current_state:
		PumpState.E1_EMPTY:
			# Probabilistic Na+ binding
			_attempt_na_binding_probabilistic(delta)

		PumpState.E1_NA_BOUND:
			# Waiting for ATP activation (user triggers with activate())
			pass

		PumpState.E2P_EMPTY:
			# Probabilistic K+ binding
			_attempt_k_binding_probabilistic(delta)

		_:
			# Deterministic timed states
			if cycling:
				state_timer += delta
				var current_duration = STATE_DURATIONS.get(current_state, 0.0)
				if state_timer >= current_duration:
					_advance_state()
					state_timer = 0.0

func _attempt_na_binding_probabilistic(delta):
	# Probabilistic binding based on Na+ concentration (Michaelis-Menten kinetics)
	var na_to_bind = 3 * pump_count

	if cell.sodium < na_to_bind:
		return  # Not enough substrate

	# Calculate intracellular Na+ concentration in mM
	var na_concentration_mM = (cell.actual_sodium / (cell.volume * 6.022e23)) * 1e3

	# Michaelis-Menten binding probability
	# At Km concentration, 50% of maximal binding rate
	var fractional_saturation = na_concentration_mM / (KM_NA + na_concentration_mM)

	# Probability of binding this frame
	var binding_probability = fractional_saturation * NA_BINDING_RATE * delta

	# Stochastic binding event
	if randf() < binding_probability:
		# Bind Na+ - REMOVE from available pool (sequestered on pump)
		cell.sodium -= na_to_bind
		cell.actual_sodium -= na_to_bind
		na_bound = na_to_bind
		current_state = PumpState.E1_NA_BOUND
		cell.concentrations_updated.emit()
		print("[Na-K-ATPase] E1_EMPTY → E1_NA_BOUND: Bound %d Na+ ([Na+]=%0.2f mM, saturation=%0.1f%%)" % [na_to_bind, na_concentration_mM, fractional_saturation * 100])

func _attempt_k_binding_probabilistic(delta):
	# Probabilistic binding based on K+ concentration (Michaelis-Menten kinetics)
	var k_to_bind = 2 * pump_count

	if blood.potassium < k_to_bind:
		return  # Not enough substrate

	# Calculate extracellular K+ concentration in mM
	var k_concentration_mM = (blood.actual_potassium / (blood.volume * 6.022e23)) * 1e3

	# Michaelis-Menten binding probability
	var fractional_saturation = k_concentration_mM / (KM_K + k_concentration_mM)

	# Probability of binding this frame
	var binding_probability = fractional_saturation * K_BINDING_RATE * delta

	# Stochastic binding event
	if randf() < binding_probability:
		# Bind K+ - REMOVE from available pool (sequestered on pump)
		blood.potassium -= k_to_bind
		blood.actual_potassium -= k_to_bind
		k_bound = k_to_bind
		current_state = PumpState.E2P_K_BOUND
		state_timer = 0.0
		blood.concentrations_updated.emit()
		print("[Na-K-ATPase] E2P_EMPTY → E2P_K_BOUND: Bound %d K+ ([K+]=%0.2f mM, saturation=%0.1f%%)" % [k_to_bind, k_concentration_mM, fractional_saturation * 100])

func activate():
	super.activate()  # Pulse animation

	if cycling:
		print("[Na-K-ATPase] Cannot activate: Already cycling (current state: %s)" % PumpState.keys()[current_state])
		return  # Already cycling

	# Can only activate if Na+ is already bound
	if current_state != PumpState.E1_NA_BOUND or na_bound == 0:
		push_warning("[Na-K-ATPase] Cannot activate: No Na+ bound (current state: %s)" % PumpState.keys()[current_state])
		return

	# Check ATP availability
	var atp_required = pump_count
	if cell.atp < atp_required:
		push_warning("[Na-K-ATPase] Cannot activate: Insufficient ATP (required=%d, available=%d)" % [atp_required, cell.atp])
		return

	# Start ATP-dependent cycle
	cycling = true
	current_state = PumpState.E1P_NA_BOUND
	state_timer = 0.0
	atp_consumed = false
	k_bound = 0

	# Consume ATP immediately
	cell.atp -= atp_required
	atp_consumed = true
	cell.concentrations_updated.emit()
	print("[Na-K-ATPase] E1_NA_BOUND → E1P_NA_BOUND: ATP consumed (%d), phosphorylation complete" % atp_required)

func _advance_state():
	match current_state:
		PumpState.E1P_NA_BOUND:
			# E1-P + 3Na+ → E2-P (conformational change releases Na+ outside)
			_release_sodium()
			current_state = PumpState.E2P_EMPTY
			state_timer = 0.0
			print("[Na-K-ATPase] E1P_NA_BOUND → E2P_EMPTY: Conformational change, %d Na+ released to blood (2ms)" % na_bound)

		PumpState.E2P_K_BOUND:
			# E2-P + 2K+ → E2 + 2K+ (dephosphorylation)
			current_state = PumpState.E2_K_BOUND
			state_timer = 0.0
			print("[Na-K-ATPase] E2P_K_BOUND → E2_K_BOUND: Dephosphorylation complete (2ms)")

		PumpState.E2_K_BOUND:
			# E2 + 2K+ → E1 (conformational change)
			current_state = PumpState.E1_K_BOUND
			state_timer = 0.0
			print("[Na-K-ATPase] E2_K_BOUND → E1_K_BOUND: Conformational change back to E1 (2ms)")

		PumpState.E1_K_BOUND:
			# E1 + 2K+ → E1 (release K+ inside)
			_release_potassium()
			current_state = PumpState.E1_EMPTY
			cycling = false
			var released_na = na_bound
			var released_k = k_bound
			na_bound = 0
			k_bound = 0
			state_timer = 0.0
			print("[Na-K-ATPase] E1_K_BOUND → E1_EMPTY: %d K+ released to cell, cycle complete (3ms)" % released_k)

func _release_sodium():
	# E1-P-3Na+ → E2-P + 3Na+ (extracellular)
	# Conformational change releases Na+ to blood side
	if na_bound > 0:
		blood.sodium += na_bound
		blood.actual_sodium += na_bound
		blood.concentrations_updated.emit()

func _release_potassium():
	# E1 + 2K+ → E1 + 2K+ (intracellular)
	# Conformational change releases K+ to cell side
	if k_bound > 0:
		cell.potassium += k_bound
		cell.actual_potassium += k_bound
		cell.concentrations_updated.emit()

		# Final cycle summary
		var voltage = cell.electrochemical_field.calculate_resting_potential(blood) if cell.electrochemical_field else 0
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("[Na-K-ATPase] CYCLE COMPLETE (~17ms total)")
		print("  Net transport: %d Na+ OUT, %d K+ IN" % [na_bound, k_bound])
		print("  Membrane potential: %.2f mV" % voltage)
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
