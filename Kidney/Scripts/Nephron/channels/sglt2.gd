extends IonChannel

# SGLT2 cotransporter states
enum TransporterState {
	EMPTY,              # No substrates bound, ready to bind Na+ or Glucose
	NA_BOUND,           # Na+ bound, waiting for glucose
	GLUCOSE_BOUND,      # Glucose bound, waiting for Na+
	BOTH_BOUND,         # Both substrates bound, waiting for activation
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
var transport_count = 1e6

# Compartment references (cached)
var lumen = null
var cell = null

# Substrate binding flags
var na_bound: int = 0
var glucose_bound: int = 0

func _ready():
	super._ready()

	# Cache compartment references
	lumen = CompartmentRegistry.get_compartment("kidney.pct.lumen")
	cell = CompartmentRegistry.get_compartment("kidney.pct.cell")

	if not lumen or not cell:
		push_error("SGLT2: Could not find compartments")

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
			# Waiting for user activation
			pass

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
			print("[SGLT2] GLUCOSE_BOUND → BOTH_BOUND: Bound %d Na+ ([Na+]=%0.2f mM, saturation=%0.1f%%)" % [na_to_bind, na_concentration_mM, fractional_saturation * 100])
		else:
			current_state = TransporterState.NA_BOUND
			print("[SGLT2] EMPTY → NA_BOUND: Bound %d Na+ ([Na+]=%0.2f mM, saturation=%0.1f%%)" % [na_to_bind, na_concentration_mM, fractional_saturation * 100])

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
			print("[SGLT2] NA_BOUND → BOTH_BOUND: Bound %d Glucose ([Glucose]=%0.2f mM, saturation=%0.1f%%)" % [glucose_to_bind, glucose_concentration_mM, fractional_saturation * 100])
		else:
			current_state = TransporterState.GLUCOSE_BOUND
			print("[SGLT2] EMPTY → GLUCOSE_BOUND: Bound %d Glucose ([Glucose]=%0.2f mM, saturation=%0.1f%%)" % [glucose_to_bind, glucose_concentration_mM, fractional_saturation * 100])

func activate():
	super.activate()  # Pulse animation

	if cycling:
		print("[SGLT2] Cannot activate: Already cycling (current state: %s)" % TransporterState.keys()[current_state])
		return

	# Can only activate if BOTH substrates are bound
	if current_state != TransporterState.BOTH_BOUND or na_bound == 0 or glucose_bound == 0:
		push_warning("[SGLT2] Cannot activate: Both Na+ and Glucose must be bound (current state: %s)" % TransporterState.keys()[current_state])
		return

	# Start conformational change cycle
	cycling = true
	current_state = TransporterState.TRANSLOCATING
	state_timer = 0.0
	print("[SGLT2] BOTH_BOUND → TRANSLOCATING: Starting conformational change")

func _advance_state():
	match current_state:
		TransporterState.TRANSLOCATING:
			# Conformational change complete, now release substrates to cell
			current_state = TransporterState.RELEASING
			state_timer = 0.0
			print("[SGLT2] TRANSLOCATING → RELEASING: Conformational change complete (5ms)")

		TransporterState.RELEASING:
			# Release both substrates to cell
			_release_substrates()
			current_state = TransporterState.EMPTY
			cycling = false
			var released_na = na_bound
			var released_glucose = glucose_bound
			na_bound = 0
			glucose_bound = 0
			state_timer = 0.0
			print("[SGLT2] RELEASING → EMPTY: Released %d Na+ and %d Glucose to cell (3ms)" % [released_na, released_glucose])
			print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
			print("[SGLT2] CYCLE COMPLETE (~8ms total)")
			print("  Net transport: %d Na+ IN, %d Glucose IN (from lumen → cell)" % [released_na, released_glucose])
			print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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
