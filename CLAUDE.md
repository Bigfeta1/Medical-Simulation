# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Godot 4.5** medical simulation game focusing on accurate physiological modeling. The project uses **GDScript** for all logic.

## Architecture

### Autoload Singletons
The project uses two autoload singletons (defined in `project.godot`):
- `genome` - Manages genetic data (e.g., thalassemia-related genes on chromosomes 16)
- `scene_loader` - Handles dynamic scene loading

### Organ Systems
The codebase is organized by medical organ systems, each in its own directory:

**Uterus** (`/Uterus/`)
- State machine architecture with two states: PREGNANT and NONPREGNANT
- `UterusController.gd` - Main state controller, emits signals `state_changed_to_pregnant` and `state_changed_to_nonpregnant`
- Dynamically swaps between `NonpregnantUterus.glb` and `PregnantUterus.glb` 3D models
- `fetus.gd` - Manages fetal heart rate simulation with variability, contractions, and early decelerations
  - Controls contraction physics (uterus scaling, fallopian tube/ovary movement)
  - Uses recursive node search (`find_node_by_name`) to locate anatomical parts in loaded GLB models
  - Only processes when in PREGNANT state
- `fetal_heart_tracing.gd` - Renders real-time fetal heart rate tracing (Line2D)
- `cervical_display.gd` - Manages SubViewport cervical camera view with contraction-based camera bobbing
- UI components show/hide based on pregnancy state via signal connections

**Heart** (`/heart/`)
- `av_node.gd` - Atrioventricular node simulation (currently minimal)

**Blood** (`/blood/`)
- `hemoglobin.gd` - Hemoglobin state machine (Oxyhemoglobin, Carbaminohemoglobin, standby)
- Tracks globulin chains (alpha, beta, gamma for fetal hemoglobin)
- `globulin.gd` - Globulin modeling

**Kidney** (`/Kidney/`)
- `proxima_convoluted_tubule.gd` - Nephron simulation with filtration components (sodium, potassium, bicarbonate, glucose, amino acids, water)
- Models Na-K pump activity and transporter systems

### Medical Data
- `diagnoser.gd` - Hierarchical infertility diagnostic tree with percentages for each cause (male/female/unexplained)

## Signal Connections
**CRITICAL**: Signal connections MUST occur in `_ready()` or during instantiation. Never create separate functions for signal connection - connections must be "one and done" within `_ready()` itself.

Example (correct):
```gdscript
func _ready():
	uterus_controller.state_changed_to_pregnant.connect(_on_pregnant_state)
```

## Running the Project
Open the project in **Godot 4.5** and press F5 to run. The main scene is set in `project.godot`.

## Key Controls
- **P key or Enter** - Toggle uterus pregnancy state
- **E key** - Toggle early deceleration mode (when pregnant)

## Node References and Dynamic Loading
Many scripts cache references to nodes within dynamically loaded GLB files. When working with these:
- Nodes are found via recursive search after scene instantiation
- Original transforms (position, scale) are stored before modification
- References are cleared when switching states

## Display Settings
Project configured for 1920x1080 resolution with TAA and 2x MSAA enabled.
