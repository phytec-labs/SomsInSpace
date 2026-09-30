# game_session.gd
# Autoload (GameSession): per-kiosk session state that outlives scene changes.
# Holds the ship chosen on the ship select screen. Nothing is persisted: every
# boot starts on the first ship in GameConfig.ships (index 0).
extends Node

const ShipDefinitionScript := preload("res://scripts/data/ship_definition.gd")
const GAME_CONFIG := preload("res://data/game_config.tres")

## Index into GameConfig.ships of the selected ship.
var selected_ship_index: int = 0

## The selected ship (the first configured ship if none was chosen).
## Assigning a ship from GameConfig.ships also updates the index.
var selected_ship: ShipDefinitionScript:
	get:
		if _selected_ship == null:
			var ships := get_ships()
			if not ships.is_empty():
				selected_ship_index = clampi(selected_ship_index, 0, ships.size() - 1)
				_selected_ship = ships[selected_ship_index]
		return _selected_ship
	set(value):
		_selected_ship = value
		var index := get_ships().find(value)
		if index >= 0:
			selected_ship_index = index

var _selected_ship: ShipDefinitionScript = null


func get_ships() -> Array:
	return GAME_CONFIG.ships


## Select by index into GameConfig.ships (clamped).
func select_ship(index: int) -> void:
	var ships := get_ships()
	if ships.is_empty():
		return
	selected_ship = ships[clampi(index, 0, ships.size() - 1)]
