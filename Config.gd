extends Node

var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")
var settings = preload("res://LoadoutLocker/LoadoutSettings.tres")

var config = ConfigFile.new()

const FILE_PATH = "user://MCM/LoadoutLocker"
const MOD_ID = "loadout-locker"

func _ready() -> void:
	config.set_value("Keycode", "loadoutLockerKey", {
		"name" = "Open Loadout Locker",
		"tooltip" = "Key to open the loadout locker (while inventory is open in a shelter)",
		"default" = KEY_F9,
		"value" = KEY_F9
	})

	if McmHelpers != null:
		if !FileAccess.file_exists(FILE_PATH + "/config.ini"):
			DirAccess.open("user://").make_dir_recursive(FILE_PATH)
			config.save(FILE_PATH + "/config.ini")
		else:
			McmHelpers.CheckConfigurationHasUpdated(MOD_ID, config, FILE_PATH + "/config.ini")
			config.load(FILE_PATH + "/config.ini")

		_on_config_updated(config)

		McmHelpers.RegisterConfiguration(
			MOD_ID,
			"Loadout Locker",
			FILE_PATH,
			"Configure the Loadout Locker keybind",
			{
				"config.ini" = _on_config_updated
			}
		)

func _on_config_updated(_config: ConfigFile):
	settings.openKey = _config.get_value("Keycode", "loadoutLockerKey")["value"]
	print("Loadout Locker: Keybind updated to " + str(settings.openKey))
