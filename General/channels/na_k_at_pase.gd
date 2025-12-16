extends IonChannel

func activate():
	super.activate()  # Pulse animation

	# Get compartments from registry
	var cell = CompartmentRegistry.get_compartment("kidney.pct.cell")
	var blood = CompartmentRegistry.get_compartment("kidney.pct.blood")

	if not cell or not blood:
		push_error("Na_K_ATPase: Could not find compartments")
		return

	# Typical PCT cell has ~10^6 to 10^7 Na-K-ATPase pumps
	# Scale transport by 1e6 pump cycles
	var pump_count = 1e6
	var na_to_move = 3 * pump_count
	var k_to_move = 2 * pump_count

	# Move 3 Na+ per pump from cell to blood (update both display and actual)
	if cell.sodium >= na_to_move:
		cell.sodium -= na_to_move
		cell.actual_sodium -= na_to_move
		blood.sodium += na_to_move
		blood.actual_sodium += na_to_move

	# Move 2 K+ per pump from blood to cell (update both display and actual)
	if blood.potassium >= k_to_move:
		blood.potassium -= k_to_move
		blood.actual_potassium -= k_to_move
		cell.potassium += k_to_move
		cell.actual_potassium += k_to_move

	# Emit signals to update UI
	cell.concentrations_updated.emit()
	blood.concentrations_updated.emit()

	# Debug: Check voltage change
	var voltage_before = cell.electrochemical_field.calculate_resting_potential() if cell.electrochemical_field else 0
	print("Na_K_ATPase activated: Moved %d Na+ out, %d K+ in (representing %d pump cycles)" % [na_to_move, k_to_move, pump_count])
	print("Cell Na: %d -> %d, K: %d -> Blood K: %d" % [cell.sodium + na_to_move, cell.sodium, cell.potassium - k_to_move, blood.potassium + k_to_move])
	print("Cell voltage: %.2f mV" % voltage_before)
