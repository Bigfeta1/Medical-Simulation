extends NephronCompartment
class_name PCTBloodCompartment

## Peritubular capillary blood compartment
## Represents blood plasma in the capillaries surrounding the PCT

func _ready():
	volume = 5e-12  # Peritubular capillary segment ~5 picoliters
	super._ready()

func _initialize_concentrations():
	# Physiologically accurate blood plasma concentrations (extracellular fluid)
	set_concentration("sodium", 140.0)     # 140 mM - plasma Na+
	set_concentration("potassium", 5.0)    # 5 mM - plasma K+
	set_concentration("chloride", 110.0)   # 110 mM - plasma Cl-
	set_concentration("glucose", 5.0)      # 5 mM - plasma glucose
	set_concentration("bicarbonate", 24.0) # 24 mM - plasma HCO3-
	set_concentration("protons", 0.00004)  # 40 nM (pH 7.4, slightly more basic than cell)
	set_concentration("amino_acids", 2.5)  # 2.5 mM - plasma amino acids

	concentrations_updated.emit()
