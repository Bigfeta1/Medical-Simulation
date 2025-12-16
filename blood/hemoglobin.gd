extends Node3D

enum HEMOGLOBIN_STATE {
	Oxyhemoglobin,
	Carbaminohemoglobin,
	standby
}

var current_state: HEMOGLOBIN_STATE = HEMOGLOBIN_STATE.Oxyhemoglobin

var alpha_globulin = 2
var beta_globulin = 2
var gamma_globulin = 0 #Fetal Hemoglobin chain
