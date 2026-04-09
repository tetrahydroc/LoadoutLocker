extends Node

var gameData = preload("res://Resources/GameData.tres")
var audioLibrary = preload("res://Resources/AudioLibrary.tres")
var audioInstance2D = preload("res://Resources/AudioInstance2D.tscn")
var _SaveScript = preload("res://LoadoutLocker/LoadoutSave.gd")
var _settings = preload("res://LoadoutLocker/LoadoutSettings.tres")

const SAVE_PATH = "user://Loadouts.cfg"
const LEGACY_SAVE_PATH = "user://Loadouts.tres"

var _panel: PanelContainer = null
var _loadoutSave = null
var _currentLoadout: int = 0
var _contentLabel: Label = null
var _tabContainer: HBoxContainer = null
var _vbox: VBoxContainer = null
var _isOpen = false
var _costLabel: Label = null
var _buyButton: Button = null

# Drag state
var _dragging = false
var _drag_offset = Vector2.ZERO
var _titleBar: ColorRect = null

# Resize state
var _resizing = false
var _resize_offset = Vector2.ZERO
var _resize_handle: ColorRect = null
const MIN_SIZE = Vector2(300, 400)

func _ready():
	print("Loadout Locker: Loaded")

func _process(_delta):
	# Auto-close locker if inventory is closed
	if _isOpen and !gameData.interface:
		_close_ui()

func _input(event):
	if event is InputEventKey and event.pressed and !event.echo:
		if event.keycode == _settings.openKey:
			if !gameData.shelter:
				return
			if _isOpen:
				_close_ui()
			else:
				_open_ui()

	# Handle drag and resize
	if _isOpen and _panel and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if !event.pressed:
				_dragging = false
				_resizing = false

	if _isOpen and _panel and event is InputEventMouseMotion:
		if _dragging:
			_panel.position = event.global_position - _drag_offset
		elif _resizing:
			var new_size = event.global_position - _panel.position + _resize_offset
			new_size.x = max(new_size.x, MIN_SIZE.x)
			new_size.y = max(new_size.y, MIN_SIZE.y)
			_panel.custom_minimum_size = new_size
			_panel.size = new_size

# --- Save/Load ---

func _load_save():
	# Try new ConfigFile format
	if FileAccess.file_exists(SAVE_PATH):
		var cfg = ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			var save = _SaveScript.new()
			var count = cfg.get_value("loadouts", "count", 0)
			for i in count:
				var name = cfg.get_value("loadout_" + str(i), "name", "Loadout " + str(i + 1))
				save.loadoutNames.append(name)
				var slot_count = cfg.get_value("loadout_" + str(i), "slot_count", 0)
				var slots: Array[SlotData] = []
				for j in slot_count:
					var key = "loadout_" + str(i) + "_slot_" + str(j)
					var item_file = cfg.get_value(key, "item_file", "")
					if item_file == "":
						continue
					var item_data = _find_item_data(item_file)
					if !item_data:
						continue
					var sd = SlotData.new()
					sd.itemData = item_data
					sd.condition = cfg.get_value(key, "condition", 100)
					sd.amount = cfg.get_value(key, "amount", 0)
					sd.position = cfg.get_value(key, "position", 0)
					sd.mode = cfg.get_value(key, "mode", 1)
					sd.zoom = cfg.get_value(key, "zoom", 1)
					sd.chamber = cfg.get_value(key, "chamber", false)
					sd.casing = cfg.get_value(key, "casing", false)
					sd.state = cfg.get_value(key, "state", "")
					sd.slot = cfg.get_value(key, "slot", "")
					# Restore nested attachments
					var nested_count = cfg.get_value(key, "nested_count", 0)
					for k in nested_count:
						var nf = cfg.get_value(key, "nested_" + str(k), "")
						var nd = _find_item_data(nf)
						if nd:
							sd.nested.append(nd)
					slots.append(sd)
				save.loadoutSlots.append(slots)
			return save

	# Try legacy .tres format
	if FileAccess.file_exists(LEGACY_SAVE_PATH):
		var save = load(LEGACY_SAVE_PATH)
		if save and "loadoutNames" in save:
			return save

	var save = _SaveScript.new()
	return save

func _find_item_data(file_name: String) -> ItemData:
	var scene = Database.get(file_name)
	if scene and scene is PackedScene:
		var path = scene.resource_path.replace(".tscn", ".tres")
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is ItemData:
				return res
	return null

func _save_data():
	if !_loadoutSave:
		return
	var cfg = ConfigFile.new()
	cfg.set_value("loadouts", "count", _loadoutSave.loadoutNames.size())
	for i in _loadoutSave.loadoutNames.size():
		cfg.set_value("loadout_" + str(i), "name", _loadoutSave.loadoutNames[i])
		var slots = _loadoutSave.loadoutSlots[i]
		cfg.set_value("loadout_" + str(i), "slot_count", slots.size())
		for j in slots.size():
			var sd = slots[j]
			if !sd or !sd.itemData:
				continue
			var key = "loadout_" + str(i) + "_slot_" + str(j)
			cfg.set_value(key, "item_file", sd.itemData.file)
			cfg.set_value(key, "condition", sd.condition)
			cfg.set_value(key, "amount", sd.amount)
			cfg.set_value(key, "position", sd.position)
			cfg.set_value(key, "mode", sd.mode)
			cfg.set_value(key, "zoom", sd.zoom)
			cfg.set_value(key, "chamber", sd.chamber)
			cfg.set_value(key, "casing", sd.casing)
			cfg.set_value(key, "state", sd.state)
			cfg.set_value(key, "slot", sd.slot)
			cfg.set_value(key, "nested_count", sd.nested.size())
			for k in sd.nested.size():
				cfg.set_value(key, "nested_" + str(k), sd.nested[k].file)
	cfg.save(SAVE_PATH)

# --- UI ---

func _open_ui():
	var interface = _get_interface()
	if !interface:
		return
	if !gameData.interface:
		return

	_loadoutSave = _load_save()

	if _loadoutSave.loadoutNames.size() == 0:
		_loadoutSave.loadoutNames.append("Loadout 1")
		_loadoutSave.loadoutSlots.append([])
		_save_data()

	if _currentLoadout >= _loadoutSave.loadoutNames.size():
		_currentLoadout = 0

	_create_ui(interface)
	_isOpen = true
	gameData.isOccupied = true
	_refresh_display()

func _close_ui():
	if _panel:
		_panel.queue_free()
		_panel = null
	_isOpen = false
	gameData.isOccupied = false
	_contentLabel = null
	_tabContainer = null
	_vbox = null
	_titleBar = null
	_resize_handle = null
	_dragging = false
	_resizing = false

func _get_interface():
	var scene = get_tree().current_scene
	if !scene:
		return null
	return scene.get_node_or_null("Core/UI/Interface")

func _create_ui(interface):
	if _panel:
		_panel.queue_free()

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(340, 480)
	_panel.position = Vector2(960, 100)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	interface.add_child(_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(_vbox)

	# Title bar (draggable)
	_titleBar = ColorRect.new()
	_titleBar.color = Color(1, 1, 1, 0.1)
	_titleBar.custom_minimum_size = Vector2(0, 28)
	_titleBar.mouse_filter = Control.MOUSE_FILTER_STOP
	_titleBar.gui_input.connect(_on_title_gui_input)
	_vbox.add_child(_titleBar)

	var title = Label.new()
	title.text = "LOADOUT LOCKER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.anchors_preset = Control.PRESET_FULL_RECT
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titleBar.add_child(title)

	# Tab row
	var tabScroll = ScrollContainer.new()
	tabScroll.custom_minimum_size = Vector2(0, 36)
	tabScroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabScroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_vbox.add_child(tabScroll)

	_tabContainer = HBoxContainer.new()
	_tabContainer.add_theme_constant_override("separation", 4)
	tabScroll.add_child(_tabContainer)

	_rebuild_tabs()

	_vbox.add_child(HSeparator.new())

	# Content in a scroll container so it grows with the panel
	var contentScroll = ScrollContainer.new()
	contentScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contentScroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contentScroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contentScroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_vbox.add_child(contentScroll)

	_contentLabel = Label.new()
	_contentLabel.add_theme_font_size_override("font_size", 11)
	_contentLabel.autowrap_mode = TextServer.AUTOWRAP_WORD
	_contentLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contentLabel.mouse_filter = Control.MOUSE_FILTER_STOP
	contentScroll.add_child(_contentLabel)

	_vbox.add_child(HSeparator.new())

	# Action buttons
	var btnRow = HBoxContainer.new()
	btnRow.add_theme_constant_override("separation", 4)
	btnRow.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(btnRow)

	_make_button("Store Equip", _on_store_pressed, btnRow, 110)
	_make_button("Equip", _on_equip_pressed, btnRow, 70)
	_make_button("Clear", _on_clear_pressed, btnRow, 60)
	_make_button("Delete", _on_delete_pressed, btnRow, 60)

	# Cash System integration (optional)
	var cashSystem = _get_cash_system()
	if cashSystem:
		var cashRow = HBoxContainer.new()
		cashRow.add_theme_constant_override("separation", 4)
		cashRow.alignment = BoxContainer.ALIGNMENT_CENTER
		_vbox.add_child(cashRow)

		_costLabel = Label.new()
		_costLabel.add_theme_font_size_override("font_size", 11)
		_costLabel.text = "Cost: ---"
		_costLabel.custom_minimum_size = Vector2(140, 28)
		_costLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cashRow.add_child(_costLabel)

		_buyButton = Button.new()
		_buyButton.text = "Buy Loadout"
		_buyButton.custom_minimum_size = Vector2(110, 28)
		_buyButton.add_theme_font_size_override("font_size", 11)
		_buyButton.pressed.connect(_on_buy_pressed)
		cashRow.add_child(_buyButton)

	var bottomRow = HBoxContainer.new()
	bottomRow.add_theme_constant_override("separation", 4)
	bottomRow.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(bottomRow)

	_make_button("Add Loadout", _on_add_pressed, bottomRow, 110)
	_make_button("Close", _close_ui, bottomRow, 60)

	# Resize handle (bottom-right corner)
	var resizeRow = HBoxContainer.new()
	resizeRow.alignment = BoxContainer.ALIGNMENT_END
	_vbox.add_child(resizeRow)

	_resize_handle = ColorRect.new()
	_resize_handle.color = Color(1, 1, 1, 0.15)
	_resize_handle.custom_minimum_size = Vector2(14, 14)
	_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_handle.gui_input.connect(_on_resize_gui_input)
	resizeRow.add_child(_resize_handle)

func _on_title_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = event.global_position - _panel.position
		else:
			_dragging = false

func _on_resize_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resizing = true
			_resize_offset = _panel.size - (event.global_position - _panel.position)
		else:
			_resizing = false

func _make_button(text: String, callback: Callable, parent: Node, width: int):
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 28)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _rebuild_tabs():
	if !_tabContainer:
		return
	for child in _tabContainer.get_children():
		child.queue_free()

	for i in _loadoutSave.loadoutNames.size():
		var tab = Button.new()
		tab.text = _loadoutSave.loadoutNames[i]
		tab.custom_minimum_size = Vector2(80, 28)
		tab.add_theme_font_size_override("font_size", 11)
		tab.toggle_mode = true
		tab.button_pressed = (i == _currentLoadout)
		tab.pressed.connect(_on_tab_pressed.bind(i))
		_tabContainer.add_child(tab)

func _on_tab_pressed(index: int):
	_currentLoadout = index
	_refresh_display()
	_rebuild_tabs()
	_play_click()

func _refresh_display():
	if !_contentLabel or !_loadoutSave:
		return

	if _currentLoadout >= _loadoutSave.loadoutSlots.size():
		_contentLabel.text = "(Invalid loadout)"
		return

	var slots = _loadoutSave.loadoutSlots[_currentLoadout]
	if slots.size() == 0:
		_contentLabel.text = "(Empty)\n\nStore your current equipment to save a loadout."
	else:
		var text = ""
		for slotData in slots:
			if slotData and slotData.itemData:
				var line = slotData.slot + ": " + slotData.itemData.name
				if slotData.itemData.showCondition:
					line += " (" + str(slotData.condition) + "%)"
				if slotData.nested.size() > 0:
					for nested in slotData.nested:
						line += "\n  + " + nested.display
				text += line + "\n"
		_contentLabel.text = text

	# Update cost label if Cash System is available
	if _costLabel:
		var cost = _calculate_loadout_cost()
		var cashSystem = _get_cash_system()
		if cost > 0 and cashSystem:
			var playerCash = cashSystem.CountCash()
			_costLabel.text = "Cost: €" + str(cost) + " (Have: €" + str(playerCash) + ")"
			if playerCash >= cost:
				_costLabel.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			else:
				_costLabel.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		else:
			_costLabel.text = "Cost: ---"
			_costLabel.add_theme_color_override("font_color", Color(1, 1, 1))

# --- Add / Delete loadout ---

func _on_add_pressed():
	_loadoutSave = _load_save()
	var num = _loadoutSave.loadoutNames.size() + 1
	_loadoutSave.loadoutNames.append("Loadout " + str(num))
	_loadoutSave.loadoutSlots.append([])
	_currentLoadout = _loadoutSave.loadoutNames.size() - 1
	_save_data()
	_rebuild_tabs()
	_refresh_display()
	_play_click()

func _on_delete_pressed():
	var interface = _get_interface()
	if !interface:
		return

	_loadoutSave = _load_save()
	if _loadoutSave.loadoutNames.size() <= 1:
		return

	gameData.isOccupied = false
	var slots = _loadoutSave.loadoutSlots[_currentLoadout]
	for slotData in slots:
		if slotData and slotData.itemData:
			interface.Create(slotData, interface.inventoryGrid, true)
	gameData.isOccupied = true

	_loadoutSave.loadoutNames.remove_at(_currentLoadout)
	_loadoutSave.loadoutSlots.remove_at(_currentLoadout)
	if _currentLoadout >= _loadoutSave.loadoutNames.size():
		_currentLoadout = _loadoutSave.loadoutNames.size() - 1
	_save_data()
	_rebuild_tabs()
	_refresh_display()
	_play_click()

# --- Store current equipment into loadout ---

func _on_store_pressed():
	var interface = _get_interface()
	if !interface:
		return

	gameData.isOccupied = false
	_loadoutSave = _load_save()

	var existingSlots = _loadoutSave.loadoutSlots[_currentLoadout]
	if existingSlots.size() > 0:
		for slotData in existingSlots:
			if slotData and slotData.itemData:
				interface.Create(slotData, interface.inventoryGrid, true)
		_loadoutSave.loadoutSlots[_currentLoadout] = []

	var slots: Array[SlotData] = []

	for equipmentSlot in interface.equipment.get_children():
		if equipmentSlot is Slot and equipmentSlot.get_child_count() > 0:
			var slotItem = equipmentSlot.get_child(0)
			var newSlotData = SlotData.new()
			newSlotData.Update(slotItem.slotData)
			newSlotData.SlotSave(equipmentSlot.name)
			slots.append(newSlotData)
			var unequipped = interface.Unequip(equipmentSlot)
			unequipped.queue_free()

	var rigManager = interface.rigManager
	gameData.primary = false
	gameData.secondary = false
	gameData.knife = false
	gameData.grenade1 = false
	gameData.grenade2 = false
	rigManager.UpdateRig(false)

	_loadoutSave.loadoutSlots[_currentLoadout] = slots
	_save_data()
	_refresh_display()
	interface.UpdateStats(true)
	_play_click()
	gameData.isOccupied = true

# --- Equip loadout onto player ---

func _on_equip_pressed():
	var interface = _get_interface()
	if !interface:
		return

	gameData.isOccupied = false
	_loadoutSave = _load_save()
	var slots = _loadoutSave.loadoutSlots[_currentLoadout]
	if slots.size() == 0:
		gameData.isOccupied = true
		return

	var loadoutSlotNames = {}
	for slotData in slots:
		if slotData and slotData.itemData:
			loadoutSlotNames[slotData.slot] = true

	for equipmentSlot in interface.equipment.get_children():
		if equipmentSlot is Slot and equipmentSlot.get_child_count() > 0:
			if loadoutSlotNames.has(equipmentSlot.name):
				var unequipped = interface.Unequip(equipmentSlot)
				if !interface.AutoPlace(unequipped, interface.inventoryGrid, null, false):
					interface.Drop(unequipped)

	if loadoutSlotNames.has("Primary"):
		gameData.primary = false
	if loadoutSlotNames.has("Secondary"):
		gameData.secondary = false
	if loadoutSlotNames.has("Knife"):
		gameData.knife = false
	if loadoutSlotNames.has("Grenade_1"):
		gameData.grenade1 = false
	if loadoutSlotNames.has("Grenade_2"):
		gameData.grenade2 = false

	for slotData in slots:
		if slotData and slotData.itemData:
			interface.LoadSlotItem(slotData, slotData.slot)

	var rigManager = interface.rigManager
	var primarySlot = interface.equipment.get_child(1)
	var secondarySlot = interface.equipment.get_child(2)

	if primarySlot.get_child_count() > 0 and loadoutSlotNames.has("Primary"):
		gameData.primary = true
		rigManager.LoadPrimary()
	elif secondarySlot.get_child_count() > 0 and loadoutSlotNames.has("Secondary"):
		gameData.secondary = true
		rigManager.LoadSecondary()
	else:
		rigManager.UpdateRig(false)

	_loadoutSave.loadoutSlots[_currentLoadout] = []
	_save_data()
	_refresh_display()
	interface.UpdateStats(true)
	_play_click()
	gameData.isOccupied = true

# --- Clear loadout (return items to inventory) ---

func _on_clear_pressed():
	var interface = _get_interface()
	if !interface:
		return

	gameData.isOccupied = false
	_loadoutSave = _load_save()
	var slots = _loadoutSave.loadoutSlots[_currentLoadout]
	if slots.size() == 0:
		gameData.isOccupied = true
		return

	for slotData in slots:
		if slotData and slotData.itemData:
			interface.Create(slotData, interface.inventoryGrid, true)

	_loadoutSave.loadoutSlots[_currentLoadout] = []
	_save_data()
	_refresh_display()
	interface.UpdateStats(true)
	_play_click()
	gameData.isOccupied = true

func _on_buy_pressed():
	var interface = _get_interface()
	if !interface:
		return
	var cashSystem = _get_cash_system()
	if !cashSystem:
		return

	_loadoutSave = _load_save()
	var slots = _loadoutSave.loadoutSlots[_currentLoadout]
	if slots.size() == 0:
		return

	var cost = _calculate_loadout_cost()
	if cashSystem.CountCash() < cost:
		_play_click()
		return

	# Deduct cash (physical items from inventory)
	if !cashSystem.RemoveCash(cost):
		_play_click()
		return

	# Unequip current items in slots the loadout needs
	gameData.isOccupied = false

	var loadoutSlotNames = {}
	for slotData in slots:
		if slotData and slotData.itemData:
			loadoutSlotNames[slotData.slot] = true

	for equipmentSlot in interface.equipment.get_children():
		if equipmentSlot is Slot and equipmentSlot.get_child_count() > 0:
			if loadoutSlotNames.has(equipmentSlot.name):
				var unequipped = interface.Unequip(equipmentSlot)
				if !interface.AutoPlace(unequipped, interface.inventoryGrid, null, false):
					interface.Drop(unequipped)

	if loadoutSlotNames.has("Primary"):
		gameData.primary = false
	if loadoutSlotNames.has("Secondary"):
		gameData.secondary = false
	if loadoutSlotNames.has("Knife"):
		gameData.knife = false
	if loadoutSlotNames.has("Grenade_1"):
		gameData.grenade1 = false
	if loadoutSlotNames.has("Grenade_2"):
		gameData.grenade2 = false

	# Create fresh copies of all items at 100% condition and equip them
	for slotData in slots:
		if slotData and slotData.itemData:
			var newSlotData = SlotData.new()
			newSlotData.Update(slotData)
			newSlotData.condition = 100
			newSlotData.SlotSave(slotData.slot)
			interface.LoadSlotItem(newSlotData, slotData.slot)

	# Restore weapon rig
	var rigManager = interface.rigManager
	var primarySlot = interface.equipment.get_child(1)
	var secondarySlot = interface.equipment.get_child(2)

	if primarySlot.get_child_count() > 0 and loadoutSlotNames.has("Primary"):
		gameData.primary = true
		rigManager.LoadPrimary()
	elif secondarySlot.get_child_count() > 0 and loadoutSlotNames.has("Secondary"):
		gameData.secondary = true
		rigManager.LoadSecondary()
	else:
		rigManager.UpdateRig(false)

	# Loadout stays saved (buying creates copies, doesn't consume the loadout)
	_refresh_display()
	interface.UpdateStats(true)
	_play_click()
	gameData.isOccupied = true
	print("Loadout Locker: Bought loadout for €" + str(cost))

func _get_cash_system():
	# v2.5+ registers via Engine.set_meta
	if Engine.has_meta("CashMain"):
		return Engine.get_meta("CashMain")
	# Fallback: search ModLoader children
	var modloader = get_node_or_null("/root/ModLoader")
	if modloader:
		for child in modloader.get_children():
			if child.has_method("CountCash"):
				return child
	return null

func _calculate_loadout_cost() -> int:
	if !_loadoutSave or _currentLoadout >= _loadoutSave.loadoutSlots.size():
		return 0
	var total = 0
	for slotData in _loadoutSave.loadoutSlots[_currentLoadout]:
		if slotData and slotData.itemData:
			total += slotData.itemData.value
			# Add nested attachment values
			for nested in slotData.nested:
				if nested:
					total += nested.value
	return total

func _play_click():
	var audio = audioInstance2D.instantiate()
	add_child(audio)
	audio.PlayInstance(audioLibrary.UIClick)
