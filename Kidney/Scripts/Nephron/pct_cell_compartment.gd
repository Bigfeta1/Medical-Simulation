extends NephronCompartment
class_name PCTCellCompartment

## PCT epithelial cell intracellular compartment

var atp: int = 0

func _ready():
	volume = 2e-12  # PCT cell volume ~2 picoliters
	super._ready()

func _initialize_concentrations():
	# Physiologically accurate intracellular concentrations for PCT epithelial cell
	set_concentration("sodium", 12.0)      # 12 mM - low, actively pumped out
	set_concentration("potassium", 140.0)  # 140 mM - high, actively pumped in
	set_concentration("chloride", 7.0)     # 7 mM - very low for -70mV potential
	set_concentration("glucose", 5.0)      # 5 mM
	set_concentration("bicarbonate", 24.0) # 24 mM
	set_concentration("protons", 0.000063) # 63 nM (pH 7.2)
	set_concentration("amino_acids", 2.0)  # 2 mM

	# ATP pool: ~5 mM for active cell
	var scale = debug_scale_factor if debug_mode else 1.0
	atp = int(5e-3 * volume * 6.022e23 * scale)

	concentrations_updated.emit()
