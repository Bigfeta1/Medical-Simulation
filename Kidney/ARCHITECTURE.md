# PCT Transport Simulation Architecture

## Core Philosophy: Bottom-Up Causality

**Critical Rule: No coupling outcomes to upstream effects. Only model root causes.**

The simulation must produce physiological results (e.g., 67% reabsorption in PCT) as **emergent outputs**, not hardcoded inputs. We achieve physiological accuracy by modeling the actual mechanisms, not by forcing predetermined concentration profiles.

---

## Three-Layer System

### 1. Particle Layer (Discrete Agents)
Individual ions and molecules exist as distinct entities:
- `Na+`, `K+`, `Cl-`, `Glucose`, `H+`, `HCO3-`, `Amino Acids`, `H2O`
- Each particle has:
  - Position (3D coordinates in lumen/cell/blood compartment)
  - Charge (for electrostatic interactions)
  - Velocity (influenced by fields and diffusion)
  - Mass (for physics calculations)

**Particle Behavior:**
```gdscript
class IonParticle:
	var position: Vector3
	var velocity: Vector3
	var charge: float

	func _physics_process(delta):
		# Calculate forces from ALL nearby charged particles
		var electric_field = calculate_coulomb_forces()

		# Brownian motion (thermal diffusion)
		var brownian = random_thermal_motion()

		# Bulk flow (tubular fluid movement)
		var flow = get_local_flow_velocity()

		# Update motion
		velocity += (electric_field + brownian + flow) * delta
		position += velocity * delta
```

**Key Point:** Particles don't "know" about concentration gradients. They only respond to:
- Electrostatic forces from other charged particles
- Random thermal motion
- Bulk fluid flow
- Direct interaction with transporters

---

### 2. Transporter Layer (Molecular Machines)

Each ion channel/transporter is a state machine that **physically moves particles**.

**Na-K-ATPase Example:**
```gdscript
func pump_cycle():
    if state != READY:
        return

    if atp_available < 1:
        return

    # Find particles within binding radius
    var na_particles = find_particles_in_radius("Na+", cell_side, binding_radius)
    var k_particles = find_particles_in_radius("K+", blood_side, binding_radius)

    if na_particles.size() < 3 or k_particles.size() < 3:
        return  # Not enough substrate

    # Execute transport
    for i in range(3):
        move_particle(na_particles[i], cell → blood)

    for i in range(2):
        move_particle(k_particles[i], blood → cell)

    atp_available -= 1
    state = CYCLING
```

**SGLT2 Example:**
```gdscript
func cotransport_cycle():
    if state != READY:
        return

    # Must bind BOTH substrates
    var na = find_particle_in_radius("Na+", lumen_side, binding_radius)
    var glucose = find_particle_in_radius("Glucose", lumen_side, binding_radius)

    if na == null or glucose == null:
        return

    # Simultaneous transport (stoichiometry: 1 Na+ : 1 Glucose)
    move_particle(na, lumen → cell)
    move_particle(glucose, lumen → cell)

    state = CYCLING
```

**Transporter Properties (from physiology):**
- `binding_radius` - capture distance for substrates
- `cycle_time` - time between transport events
- `affinity` - probability of binding when substrate is in range
- `density` - number of transporters per unit membrane area

---

### 3. Emergent Properties Layer

These are **calculated outputs**, not inputs:

#### **Electronegativity (Membrane Potential)**
```gdscript
func calculate_membrane_potential(intracellular_field, extracellular_field):
    # Get ion concentrations from both compartments
    var k_in = intracellular_field.get_ion_concentration("k")
    var na_in = intracellular_field.get_ion_concentration("na")
    var cl_in = intracellular_field.get_ion_concentration("cl")

    var k_out = extracellular_field.get_ion_concentration("k")
    var na_out = extracellular_field.get_ion_concentration("na")
    var cl_out = extracellular_field.get_ion_concentration("cl")

    # Goldman-Hodgkin-Katz equation with permeability weighting
    # P_K : P_Na : P_Cl = 1.0 : 0.04 : 0.45
    var numerator = (1.0 * k_out) + (0.04 * na_out) + (0.45 * cl_in)
    var denominator = (1.0 * k_in) + (0.04 * na_in) + (0.45 * cl_out)

    return 61.5 * log(numerator / denominator) / log(10)  # mV
```

**Critical Physics:** Membrane potential comes from **ion concentration gradients** weighted by **membrane permeabilities**, NOT from total charge differences. Compartments remain nearly electroneutral (charge difference ~10^-6 of total ions), but concentration gradients create voltage via selective ion flow.

The Na-K-ATPase creates voltage **by changing ion concentration gradients** (moving Na+ out, K+ in), which shifts the GHK equation output, not by creating charge imbalance.

#### **Concentration**
```gdscript
func get_concentration(substance, voxel):
    var particle_count = count_particles_of_type(substance, voxel)
    return particle_count / voxel.volume
```

Concentration IS particle density. No manual gradient setting.

#### **Flow Along PCT**
```gdscript
class PCTVoxel:
    var particles: Array[Particle]
    var flow_velocity: float  # Set by tubular flow rate (from GFR)

    func _process(delta):
        # Particles that reach voxel boundary flow to next segment
        for particle in particles:
            if particle.position.x > voxel_end_x:
                next_voxel.receive_particle(particle)
                particles.erase(particle)
```

Downstream concentrations emerge from:
- Upstream particle arrival rate
- Local transporter activity (removes particles)
- Flow rate (moves particles forward)

---

## Spatial Discretization

The PCT is divided into **voxels** (3D spatial segments):

```
[Glomerulus] → [Early PCT] → [Mid PCT] → [Late PCT] → [Loop of Henle]
                  ↓ SGLT2        ↓ SGLT1       ↓ Reduced
                  ↓ NHE3         ↓ NHE3         ↓ transport
```

**Each voxel contains:**
- Lumen compartment (tubular fluid)
- Cell compartment (epithelial cell interior)
- Blood compartment (peritubular capillaries)
- Apical membrane (with apical transporters)
- Basolateral membrane (with basolateral transporters)

**Voxel Properties:**
- Transporter densities (early PCT has more SGLT2 than late PCT - from histology)
- Membrane permeabilities
- Volume
- Flow velocity

---

## Physiological Calibration

We **set biologically accurate inputs**:

### Input Parameters (from literature):
- **GFR:** 125 mL/min → particle spawn rate at glomerulus
- **Tubular flow velocity:** ~2-5 mm/s
- **Na-K-ATPase density:** ~30 million pumps per cell
- **SGLT2 density:** Higher in S1/S2 segments, lower in S3
- **ATP availability:** Function of cellular metabolism
- **Binding affinities:** Km values from biochemistry literature

### Expected Emergent Outputs (validation):
- **67% of filtrate reabsorbed in PCT** ✓
- **90% of glucose reabsorbed by early PCT** ✓
- **Sodium concentration drops from 140→70 mM along PCT** ✓
- **Membrane potential: -70 mV (intracellular)** ✓

If outputs don't match physiology, we adjust **mechanism parameters** (transporter density, cycle rates), not outcomes.

---

## Implementation Strategy

### Phase 1: Single Voxel Proof-of-Concept
- 3 compartments (lumen, cell, blood)
- Spawn Na+ and Glucose particles in lumen
- Implement SGLT2 and Na-K-ATPase
- Verify particle movement creates concentration gradient
- Measure emergent membrane potential

### Phase 2: Multi-Voxel PCT Segment
- Chain 10-20 voxels together
- Add axial flow
- Implement all major transporters (NHE3, NBC1, GLUT2, KCC)
- Verify concentration profile along PCT matches physiology

### Phase 3: Full Nephron Integration
- Connect PCT to glomerular filtration
- Add Loop of Henle, DCT, collecting duct
- Model countercurrent multiplication
- Full urine output simulation

### Phase 4: Pathology Modeling
- ATN: Reduce ATP → pumps stop → particles accumulate
- Loss of polarity: Randomize transporter locations
- Diuretics: Block specific transporters (e.g., SGLT2 inhibitors)
- Fanconi syndrome: Disable proximal tubule reabsorption

---

## Technical Considerations

### Performance Optimization
- Use spatial partitioning (octree/grid) for particle neighbor searches
- Limit particle count via representative scaling (1 sim particle = N real ions)
- GPU compute shaders for field calculations
- LOD system for distant voxels

### Validation Metrics
- Compare concentration profiles to experimental data
- Verify transporter kinetics match Michaelis-Menten curves
- Check energy balance (ATP consumption vs. transport work)
- Osmolality calculations (particle counts determine osmotic pressure)

---

## Key Insight

**The beauty of this approach:** We're not programming the kidney's function. We're programming the kidney's **mechanisms**, and function emerges naturally.

If we set transporter densities correctly and give them accurate kinetics, the 67% reabsorption happens automatically. If we model ATN by reducing ATP, the kidney failure emerges from the broken mechanisms—we don't have to script "what happens in kidney failure."

This is true simulation, not animation.

---

## Implementation Progress (2025-12-16)

### Completed: Electrochemical Field Foundation

**Files Created:**
- `Kidney/Scripts/Nephron/utilities/electrochemical_field.gd` - ElectrochemicalField class

**Files Modified:**
- `Kidney/Scripts/Nephron/pct_cell.gd` - Added ion tracking and field integration
- `Kidney/Scripts/Nephron/pct/pct_solute_display_manager.gd` - Added membrane potential display

**What Was Built:**

1. **ElectrochemicalField Class** (`electrochemical_field.gd`)
   - Calculates emergent electrochemical properties from ion particle counts
   - Methods:
     - `calculate_total_charge()` - Sums charges from all ions in compartment (for debugging/validation)
     - `calculate_potential_difference(other_field)` - GHK membrane potential between two compartments
     - `get_ion_concentration(ion_name)` - Converts particle counts to mM concentrations
     - `calculate_osmolality()` - Total osmotic pressure from all particles
     - `calculate_resting_potential(external_compartment)` - Goldman-Hodgkin-Katz equation (-70.1 mV)
   - Uses physical constants (Faraday, Gas constant, body temperature)
   - All calculations use actual particle counts, not debug-scaled values
   - **Physics:** Voltage calculated from ion concentration gradients and permeabilities (GHK), not charge imbalance

2. **PCT Cell Compartment** (`pct_cell.gd`)
   - Physiologically accurate intracellular ion concentrations:
     - Na+ = 12 mM (low, actively pumped out)
     - K+ = 140 mM (high, actively pumped in)
     - Cl- = 7 mM (very low, actively excluded to maintain -70 mV potential)
     - Glucose = 5 mM
     - HCO3- = 24 mM
     - H+ = 63 nM (pH 7.2)
     - Amino acids = 2 mM
     - ATP = 5 mM
   - Cell volume = 2 picoliters (2e-12 L)
   - Dual particle count system:
     - `sodium`, `potassium`, etc. - Display values (scaled in debug mode)
     - `actual_sodium`, `actual_potassium`, etc. - True physiological particle counts
   - Debug mode: Scales display values by 1.32e-5 (smallest value = 1, ratios preserved)
   - Signal: `concentrations_updated` - Emitted when ion counts change
   - ElectrochemicalField child node for calculations

3. **Architecture Pattern Established**
   - **Generic compartment model**: Any compartment (lumen, cell, blood) can have:
     - Ion concentration variables
     - ElectrochemicalField child node
     - Volume property
   - **Separation of concerns**:
     - Compartments store ion counts
     - ElectrochemicalField calculates emergent properties
     - Display manager updates UI
   - **Debug scaling**: Display values scale for readability, but physics calculations always use actual particle counts

4. **UI Integration**
   - Membrane potential displayed in real-time (-70.1 mV)
   - Updates automatically when debug mode toggles
   - All ion concentrations displayed with proper scaling

**Current Status:**
- ✅ Single compartment (cell) with electrochemical field working
- ✅ Realistic intracellular ion concentrations initialized
- ✅ Membrane potential calculation using Goldman-Hodgkin-Katz equation (-70.1 mV)
- ✅ Debug mode for human-readable particle counts
- ✅ GHK equation accounts for K+, Na+, and Cl- permeabilities
- ✅ **Blood compartment implemented with full display**
- ✅ **Generic compartment interface pattern working**
- ✅ **Global CompartmentRegistry for cross-system compartment references**
- ✅ **Na-K-ATPase functional with ion transport and voltage changes**
- ✅ **Interactive receptor activation system with UI**
- ⏳ Lumen compartment not yet implemented
- ⏳ Other transporters (SGLT2, NHE3, etc.) not yet implemented

**Membrane Potential Details:**
- Uses Goldman-Hodgkin-Katz (GHK) equation for physiological accuracy
- Permeability ratios: P_K : P_Na : P_Cl = 1.0 : 0.04 : 0.45
- Intracellular concentrations: K+ = 140 mM, Na+ = 12 mM, Cl- = 7 mM
- Extracellular concentrations: K+ = 5 mM, Na+ = 140 mM, Cl- = 110 mM
- Calculated resting potential: **-70.1 mV** (physiologically accurate)
- Example: 8.43 × 10⁹ Cl- ions in 2 pL cell volume = 7 mM

**Next Steps:**
1. Create lumen compartment with tubular fluid concentrations
2. Implement transporter mechanics (Na-K-ATPase, SGLT2) that physically move particles
3. Add spatial voxel discretization along PCT length

---

### Completed: Generic Compartment Interface & Blood Compartment (2025-12-16)

**Files Modified:**
- `Kidney/Scripts/Nephron/nephron_blood_vessel.gd` - Implemented compartment interface pattern
- `Kidney/Scripts/Nephron/pct/pct_solute_display_manager.gd` - Refactored to work generically with any compartment
- `Uterus/node_3d.tscn` - Added ElectrochemicalField to BloodVessel node

**What Was Built:**

1. **Generic Compartment Interface Pattern**
   - ANY node can be a compartment by:
     - Having an ElectrochemicalField child node
     - Exposing standard ion variables (sodium, potassium, chloride, etc.)
     - Emitting `concentrations_updated` signal
     - Having `actual_*` variables for true particle counts
   - No inheritance required - uses duck typing/interface approach
   - Compartments can be MeshInstance3D, AnimatedSprite3D, or any node type

2. **Blood Vessel Compartment Implementation** (`nephron_blood_vessel.gd`)
   - Instantiates PCTBloodCompartment in `_ready()`
   - Relays compartment data to parent node variables for display access
   - Signal forwarding: compartment.concentrations_updated → parent.concentrations_updated
   - Volume: 5 picoliters (peritubular capillary segment)
   - Physiological blood plasma concentrations:
     - Na+ = 140 mM, K+ = 5 mM, Cl- = 110 mM
     - Glucose = 5 mM, HCO3- = 24 mM, H+ = 40 nM (pH 7.4)
     - Amino acids = 2.5 mM

3. **Generic Solute Display Manager** (`pct_solute_display_manager.gd`)
   - Changed from hardcoded `pct_cell` reference to generic `compartment_node`
   - Uses `get_parent().get_parent()` to find any compartment (BloodVessel or PCTCell)
   - Works with ANY node that implements the compartment interface
   - Single script serves multiple compartment displays

4. **Scene Structure**
   - BloodVessel (MeshInstance3D)
     - ElectrochemicalField (Node3D) - calculates emergent properties
     - SoluteDisplay (Control) - UI display
       - Solute_Display_Manager - generic display script
   - PCTCell (AnimatedSprite3D)
     - ElectrochemicalField (Node3D)
     - SoluteDisplay (Control)
       - Solute_Display_Manager - same generic script

**Key Architecture Win:**
The display manager is now **completely decoupled** from specific compartment types. It works with:
- BloodVessel (MeshInstance3D with PCTBloodCompartment instance)
- PCTCell (AnimatedSprite3D with direct compartment variables)
- ANY future compartment that implements the interface

This is true interface-based programming - no class inheritance, just structural contracts.

---

### Completed: CompartmentRegistry & Functional Ion Transport (2025-12-16)

**Files Created:**
- `General/compartment_registry.gd` - Global autoload singleton for compartment management
- `General/channels/na_k_at_pase.gd` - Functional Na-K-ATPase transporter
- `General/channels/activate_receptor_button.gd` - UI button for activating selected channels

**Files Modified:**
- `project.godot` - Added CompartmentRegistry autoload
- `Kidney/Scripts/Nephron/pct_cell.gd` - Registers with CompartmentRegistry as "kidney.pct.cell"
- `Kidney/Scripts/Nephron/nephron_blood_vessel.gd` - Registers as "kidney.pct.blood"
- `Kidney/Scripts/Nephron/utilities/electrochemical_field.gd` - GHK equation now uses actual blood compartment
- `Kidney/Scripts/Nephron/pct/pct_solute_display_manager.gd` - Passes blood compartment for voltage calculation
- `Kidney/Data/Nephron/pct_channels.json` - Updated Na_K_ATPase transport definitions with registry IDs
- `General/channels/ion_channel.gd` - Added activate() function with pulse animation

**What Was Built:**

1. **Global Compartment Registry** (`compartment_registry.gd`)
   - Autoload singleton accessible from anywhere in the project
   - Manages all physiological compartments across all organ systems
   - Methods:
     - `register(id, compartment)` - Register with full ID (e.g., "kidney.pct.lumen")
     - `register_scoped(scope, location, compartment)` - Auto-namespacing (e.g., "kidney.pct", "lumen")
     - `get_compartment(id)` - Retrieve compartment reference by ID
     - `has_compartment(id)` - Check if compartment exists
     - `unregister(id)` - Remove compartment (cleanup)
   - **Namespace pattern**: `organ.substructure.compartment_type`
     - Examples: "kidney.pct.cell", "kidney.pct.blood", "heart.left_ventricle.blood"
   - Decouples transporters from hardcoded node paths
   - Enables JSON-driven compartment references

2. **Functional Na-K-ATPase** (`na_k_at_pase.gd`)
   - Extends IonChannel base class
   - Retrieves cell and blood compartments from registry
   - Moves ions on activation:
     - 3 Na+ from cell → blood
     - 2 K+ from blood → cell
     - Updates both display values and actual particle counts
   - Scaled to 10^6 pump cycles per activation (physiologically representative)
   - Emits `concentrations_updated` signals to update UI
   - Includes pulse animation via `super.activate()`

3. **Improved Voltage Calculation**
   - `calculate_resting_potential()` now accepts `external_compartment` parameter
   - Reads actual K+, Na+, Cl- from blood compartment instead of hardcoded values
   - GHK equation now reflects changes in BOTH cell and blood compartments
   - Voltage changes are more noticeable because:
     - Cell K+ increases as pumps move K+ in
     - Blood K+ decreases as pumps extract K+ from blood
     - Both sides of the equation change simultaneously
   - Display manager passes blood compartment reference for accurate voltage

4. **Interactive Activation System**
   - Activate button in InfoPanel
   - Auto-finds NephronSelectionManager (3 levels up, then down via Nephron/NephronSelectionManager)
   - Connects to `channel_selected` and `channel_deselected` signals
   - Calls `activate()` on currently selected channel/receptor
   - Button disabled when no channel selected

5. **Channel Activation Animation**
   - IonChannel base class has `activate()` function
   - Creates tween-based pulse animation (scale up 1.3x, then back to original)
   - Stores `original_scale` in `_ready()` to prevent compound scaling
   - Kills previous tween before starting new one (prevents stacking on spam-click)
   - 0.4 second animation (0.2s up, 0.2s down)

6. **JSON-Driven Transport Definitions**
   - `pct_channels.json` updated with registry IDs:
     ```json
     {
       "substrate": "Na+",
       "source": "kidney.pct.cell",
       "destination": "kidney.pct.blood",
       "quantity": 3
     }
     ```
   - Future transporters can read from JSON and use registry to find compartments
   - Decouples transport logic from scene structure

**Architecture Benefits:**
- **Cross-system compatibility**: Same registry works for kidney, heart, uterus, etc.
- **JSON-driven configuration**: Transport definitions reference compartments by ID, not node paths
- **Runtime flexibility**: Compartments can be added/removed dynamically
- **Debugging**: `get_all_ids()` method lists all registered compartments
- **Decoupling**: Transporters don't need to know scene tree structure

**Physiological Validation:**
- Na-K-ATPase moving 3M Na+ and 2M K+ per activation
- Cell has ~14.4 billion Na+ ions (12 mM in 2 pL)
- Each activation moves 0.02% of cell Na+ pool
- Voltage changes from -70.14 mV → -70.15 mV per activation
- Continuous pumping would be needed for significant physiological effect

**Next Steps:**
1. Implement continuous/automatic pumping driven by ATP availability
2. Add SGLT2, NHE3, and other transporters from JSON
3. Create lumen compartment and register as "kidney.pct.lumen"
4. Scale simulation to represent realistic time (e.g., 1 activation = 1 second of pumping)

---

### Completed: Fixed Voltage Calculation Physics (2025-12-16)

**Files Modified:**
- `Kidney/Scripts/Nephron/utilities/electrochemical_field.gd` - Fixed `calculate_potential_difference()`
- `Kidney/ARCHITECTURE.md` - Updated physics documentation

**What Was Fixed:**

**The Problem:**
The original `calculate_potential_difference()` function used incorrect physics:
```gdscript
# WRONG - used total charge ratio
var ratio = abs(charge_there / charge_here)
var potential_mv = (RT/F) * log(ratio)
```

This was fundamentally flawed because:
1. Compartments remain nearly **electroneutral** (total charge ≈ 0)
2. Charge imbalance is ~10^-6 of total ions, ratio would be ~1.0
3. Membrane potential comes from **ion concentration gradients** and **permeabilities**, not total charge
4. Would give nonsensical results as ions moved between compartments

**The Fix:**
Rewrote function to use **Goldman-Hodgkin-Katz equation** with proper physics:
```gdscript
# Get ion concentrations from both compartments
var k_in = get_ion_concentration("k")
var na_in = get_ion_concentration("na")
var cl_in = get_ion_concentration("cl")

var k_out = other_field.get_ion_concentration("k")
var na_out = other_field.get_ion_concentration("na")
var cl_out = other_field.get_ion_concentration("cl")

# GHK equation with permeability weighting
# P_K : P_Na : P_Cl = 1.0 : 0.04 : 0.45
var numerator = (p_k * k_out) + (p_na * na_out) + (p_cl * cl_in)
var denominator = (p_k * k_in) + (p_na * na_in) + (p_cl * cl_out)

var potential_mv = 61.5 * log(numerator / denominator) / log(10)
```

**Key Physics Principles:**
1. **Electroneutrality**: Compartments maintain near-zero net charge (anions ≈ cations)
2. **Selective Permeability**: Membrane lets K+ through easily (P_K = 1.0), Na+ barely (P_Na = 0.04), Cl- moderately (P_Cl = 0.45)
3. **Concentration Gradients**: High K+ inside vs. outside drives voltage negative
4. **GHK Weighting**: Each ion's contribution weighted by its permeability
5. **Voltage Source**: Comes from gradient × permeability, not charge separation

**Why This Matters:**
- Moving 3M Na+ ions barely changes total charge (still ~electroneutral)
- But it **does** change Na+ concentration gradient
- GHK correctly captures this gradient change and updates voltage
- Voltage now tracks ion movements accurately even in electroneutral compartments

**Validation:**
- Both `calculate_potential_difference()` and `calculate_resting_potential()` now use identical GHK physics
- Voltage responds to ion movements in both cell and blood compartments
- Compartments remain electroneutral while maintaining physiological voltages (-70 mV)
