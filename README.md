# Medical Simulation Game

A Godot 4.5 medical simulation focusing on accurate physiological modeling at the cellular and molecular level.

## Overview

This project simulates organ systems with bottom-up causality - physiological outcomes emerge from mechanistic modeling rather than being hardcoded. The simulation tracks individual ion particles, transporter kinetics, and electrochemical fields to produce realistic organ function.

## Current Features

### Kidney/Nephron System
- **Proximal Convoluted Tubule (PCT)** simulation with:
  - Electrochemical field calculations using Goldman-Hodgkin-Katz equation
  - Physiologically accurate intracellular ion concentrations
  - Membrane potential modeling (-70.1 mV)
  - Ion channel/transporter infrastructure (Na-K-ATPase, SGLT2, NHE3, etc.)
  - Real-time solute display with debug mode

### Uterus System
- **Pregnancy state machine** (PREGNANT/NONPREGNANT)
- **Fetal heart rate simulation** with variability and early decelerations
- Dynamic 3D model swapping
- Contraction physics with cervical display

### Blood/Hemoglobin
- Hemoglobin state machine (Oxyhemoglobin, Carbaminohemoglobin)
- Globulin chain modeling (alpha, beta, gamma)

### Genetic System
- Genome autoload singleton
- Thalassemia gene modeling

## Architecture

### Core Philosophy: Bottom-Up Causality
The simulation produces physiological results as **emergent outputs**, not hardcoded inputs. For example:
- 67% reabsorption in PCT emerges from transporter densities and kinetics
- Membrane potential emerges from ion distributions
- Kidney failure emerges from ATP depletion affecting pumps

### Three-Layer System
1. **Particle Layer** - Individual ions (Na+, K+, Cl-, glucose, etc.) as discrete entities
2. **Transporter Layer** - Molecular machines that physically move particles (Na-K-ATPase, SGLT2, etc.)
3. **Emergent Properties** - Concentration gradients, electronegativity, osmolality calculated from particle counts

See [Kidney/ARCHITECTURE.md](Kidney/ARCHITECTURE.md) for detailed implementation notes.

## Technical Details

- **Engine**: Godot 4.5
- **Language**: GDScript
- **Resolution**: 1920x1080
- **Rendering**: Forward+, TAA, 2x MSAA

## Project Structure

```
medicine/
├── Kidney/
│   ├── Scripts/Nephron/
│   │   ├── utilities/
│   │   │   ├── electrochemical_field.gd
│   │   │   └── nephron_compartment.gd
│   │   ├── channels/
│   │   │   ├── ion_channel.gd
│   │   │   ├── na_k_atpase.gd
│   │   │   └── sglt2.gd
│   │   ├── pct_cell.gd
│   │   └── pct_blood.gd
│   ├── Data/Nephron/
│   │   └── pct_channels.json
│   └── ARCHITECTURE.md
├── Uterus/
│   ├── UterusController.gd
│   ├── fetus.gd
│   └── cervical_display.gd
├── blood/
│   ├── hemoglobin.gd
│   └── globulin.gd
└── General/
    └── channels/
        └── activate_receptor_button.gd
```

## Development Guidelines

### Signal Connections
Signal connections **must** occur in `_ready()` or during instantiation. Never create separate functions for signal connection - connections must be "one and done."

### Code Style
- Never guess or make assumptions
- Verify solutions before implementing
- Prefer editing existing files over creating new ones
- No unnecessary documentation unless explicitly requested

## Getting Started

1. Clone this repository
2. Open the project in Godot 4.5
3. Press F5 to run

### Controls
- **P key or Enter** - Toggle uterus pregnancy state
- **E key** - Toggle early deceleration mode (when pregnant)

## Roadmap

### Nephron System
- [ ] Implement Na-K-ATPase activation with 6-step state machine
- [ ] Create lumen compartment with tubular fluid concentrations
- [ ] Add spatial voxel discretization along PCT length
- [ ] Implement remaining transporters (NHE3, NBC1, GLUT2, KCC)
- [ ] Multi-voxel PCT segment with axial flow
- [ ] Full nephron integration (Loop of Henle, DCT, collecting duct)
- [ ] Pathology modeling (ATN, loss of polarity, Fanconi syndrome)

### Performance Optimization
- Spatial partitioning for particle neighbor searches
- GPU compute shaders for field calculations
- LOD system for distant voxels

## License

[To be determined]

## Contributing

[To be determined]
