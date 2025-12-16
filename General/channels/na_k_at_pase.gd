extends IonChannel

# Na-K-ATPase pump cycle states (Post-Albers scheme)
enum PumpState {
	STANDBY,           # E1 - Ready to bind Na+
	NA_BINDING,        # E1 + 3Na+ (intracellular) binding
	ATP_HYDROLYSIS,    # E1-P formation (ATP → ADP + Pi)
	NA_RELEASE,        # E2-P conformational change, Na+ released extracellularly
	K_BINDING,         # E2-P + 2K+ (extracellular) binding
	DEPHOSPHORYLATION, # E2 dephosphorylation
	K_RELEASE          # E1 conformational change, K+ released intracellularly
}

var current_state: PumpState = PumpState.STANDBY
var state_timer: float = 0.0
var cycling: bool = false

# Pump cycle timing (total ~17ms per cycle)
const CYCLE_TIME = 0.017  # 17 milliseconds
const STATE_DURATIONS = {
	PumpState.NA_BINDING: 0.003,        # 3ms - Na+ binding
	PumpState.ATP_HYDROLYSIS: 0.002,    # 2ms - ATP phosphorylation
	PumpState.NA_RELEASE: 0.004,        # 4ms - Conformational change + Na+ release
	PumpState.K_BINDING: 0.003,         # 3ms - K+ binding
	PumpState.DEPHOSPHORYLATION: 0.002, # 2ms - Dephosphorylation
	PumpState.K_RELEASE: 0.003          # 3ms - Conformational change + K+ release
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

	if not cycling:
		return

	state_timer += delta

	# Check if current state duration is complete
	var current_duration = STATE_DURATIONS.get(current_state, 0.0)
	if state_timer >= current_duration:
		_advance_state()
		state_timer = 0.0

func activate():
	super.activate()  # Pulse animation

	if cycling:
		return  # Already cycling

	# Start pump cycle
	cycling = true
	current_state = PumpState.NA_BINDING
	state_timer = 0.0
	atp_consumed = false
	na_bound = 0
	k_bound = 0

func _advance_state():
	match current_state:
		PumpState.NA_BINDING:
			_bind_sodium()
			current_state = PumpState.ATP_HYDROLYSIS

		PumpState.ATP_HYDROLYSIS:
			_hydrolyze_atp()
			current_state = PumpState.NA_RELEASE

		PumpState.NA_RELEASE:
			_release_sodium()
			current_state = PumpState.K_BINDING

		PumpState.K_BINDING:
			_bind_potassium()
			current_state = PumpState.DEPHOSPHORYLATION

		PumpState.DEPHOSPHORYLATION:
			_dephosphorylate()
			current_state = PumpState.K_RELEASE

		PumpState.K_RELEASE:
			_release_potassium()
			current_state = PumpState.STANDBY
			cycling = false

func _bind_sodium():
	# Bind 3 Na+ from intracellular side
	var na_to_bind = 3 * pump_count

	if cell.sodium >= na_to_bind:
		na_bound = na_to_bind
		# Don't remove from cell yet - binding is reversible until phosphorylation
	else:
		# Insufficient substrate - abort cycle
		cycling = false
		current_state = PumpState.STANDBY

func _hydrolyze_atp():
	# ATP + E1-3Na+ → E1-P-3Na+ + ADP
	# Check ATP availability
	var atp_required = pump_count  # 1 ATP per pump cycle

	if cell.atp >= atp_required:
		# Consume ATP (this phosphorylates the pump, making Na+ binding irreversible)
		cell.atp -= atp_required
		atp_consumed = true

		# Now irreversibly remove Na+ from cell (committed to transport)
		cell.sodium -= na_bound
		cell.actual_sodium -= na_bound

		cell.concentrations_updated.emit()
	else:
		# No ATP - abort cycle, return Na+ to pool
		cycling = false
		current_state = PumpState.STANDBY
		na_bound = 0

func _release_sodium():
	# E1-P-3Na+ → E2-P + 3Na+ (extracellular)
	# Conformational change releases Na+ to blood side
	if atp_consumed and na_bound > 0:
		blood.sodium += na_bound
		blood.actual_sodium += na_bound
		blood.concentrations_updated.emit()

func _bind_potassium():
	# Bind 2 K+ from extracellular side
	var k_to_bind = 2 * pump_count

	if blood.potassium >= k_to_bind:
		k_bound = k_to_bind
		# Don't remove from blood yet - binding is reversible until dephosphorylation
	else:
		# Insufficient substrate - cycle stalls but can continue if K+ becomes available
		# In real biology, pump would wait or slowly reverse
		cycling = false
		current_state = PumpState.STANDBY

func _dephosphorylate():
	# E2-P-2K+ → E2-2K+ + Pi
	# Dephosphorylation makes K+ binding irreversible
	if k_bound > 0:
		blood.potassium -= k_bound
		blood.actual_potassium -= k_bound
		blood.concentrations_updated.emit()

func _release_potassium():
	# E2-2K+ → E1 + 2K+ (intracellular)
	# Conformational change releases K+ to cell side
	if k_bound > 0:
		cell.potassium += k_bound
		cell.actual_potassium += k_bound
		cell.concentrations_updated.emit()

		# Cycle complete
		var voltage = cell.electrochemical_field.calculate_resting_potential(blood) if cell.electrochemical_field else 0
		print("Na-K-ATPase cycle complete (17ms): %d Na+ out, %d K+ in | Voltage: %.2f mV" % [na_bound, k_bound, voltage])
