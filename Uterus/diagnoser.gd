# InfertilityData.gd
extends Node

# Clean, flat structure - much easier to read and work with!
var conditions = {
	# Root
	"infertility": {
		"name": "Infertility",
		"percentage": 100,
		"parent": null,
		"details": ""
	},
	
	# Main Categories
	"unexplained": {
		"name": "Unexplained",
		"percentage": 17,
		"parent": "infertility",
		"details": ""
	},
	
	"male_causes": {
		"name": "Male causes", 
		"percentage": 25,
		"parent": "infertility",
		"details": ""
	},
	
	"female_causes": {
		"name": "Female causes",
		"percentage": 58, 
		"parent": "infertility",
		"details": ""
	},
	
	# Male Subcategories
	"primary_hypogonadism": {
		"name": "Primary hypogonadism",
		"percentage": 35,
		"parent": "male_causes",
		"details": "↑ FSH"
	},
	
	"secondary_hypogonadism": {
		"name": "Secondary hypogonadism", 
		"percentage": 2,
		"parent": "male_causes",
		"details": "↓ FSH, ↓ LH"
	},
	
	"sperm_transport": {
		"name": "Disordered sperm transport",
		"percentage": 15,
		"parent": "male_causes", 
		"details": ""
	},
	
	"male_unknown": {
		"name": "Unknown",
		"percentage": 45,
		"parent": "male_causes",
		"details": ""
	},
	
	# Female Subcategories
	"ovulatory_dysfunction": {
		"name": "Amenorrhea/ovulatory dysfunction",
		"percentage": 46,
		"parent": "female_causes",
		"details": ""
	},
	
	"tubal_defect": {
		"name": "Tubal defect",
		"percentage": 38,
		"parent": "female_causes",
		"details": ""
	},
	
	"endometriosis": {
		"name": "Endometriosis", 
		"percentage": 9,
		"parent": "female_causes",
		"details": ""
	},
	
	"female_other": {
		"name": "Other",
		"percentage": 7,
		"parent": "female_causes",
		"details": ""
	},
	
	# Ovulatory Dysfunction Subcategories
	"hypothalamic_pituitary": {
		"name": "Hypothalamic/pituitary causes",
		"percentage": 51,
		"parent": "ovulatory_dysfunction",
		"details": ""
	},
	
	"pcos": {
		"name": "Polycystic ovary syndrome",
		"percentage": 30,
		"parent": "ovulatory_dysfunction", 
		"details": ""
	},
	
	"premature_ovarian_failure": {
		"name": "Premature ovarian failure",
		"percentage": 12,
		"parent": "ovulatory_dysfunction",
		"details": ""
	},
	
	"uterine_outflow": {
		"name": "Uterine or outflow tract disorders",
		"percentage": 7,
		"parent": "ovulatory_dysfunction",
		"details": ""
	}
}

func _ready():
	print("=== Infertility Causes Data Structure ===")
	print_structure()

func print_structure():
	print_children_recursive("infertility", 0)

func print_children_recursive(parent_id: String, indent_level: int):
	# Print the current item
	if conditions.has(parent_id):
		var item = conditions[parent_id]
		var indent = "  ".repeat(indent_level)
		var line = indent + item.name + ": " + str(item.percentage) + "%"
		if item.details != "":
			line += " (" + item.details + ")"
		print(line)
	
	# Find and print all child conditions
	for id in conditions.keys():
		var condition = conditions[id]
		if condition.parent == parent_id:
			print_children_recursive(id, indent_level + 1)

# Helper functions to work with the data
func get_condition(id: String) -> Dictionary:
	"""Get a condition by its ID"""
	return conditions.get(id, {})

func get_child_conditions(parent_id: String) -> Array:
	"""Get all child conditions of a parent condition"""
	var children = []
	for id in conditions.keys():
		if conditions[id].parent == parent_id:
			children.append(id)
	return children
