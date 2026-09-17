extends Node

const SETTINGS_PATH := "user://viewer.cfg"
const PANEL_WIDTH := 720.0
const UI_DESKTOP := Vector2i(720, 1600)
const UI_VR := Vector2i(1920, 1480)

var _world: Node3D
var _stage: EnvironmentStage
var _assembly: ModelAssembly
var _camera: OrbitCamera
var _xr: XRRig
var _ui: CanvasLayer
var _side_panel: Panel
var _ui_viewport: SubViewport
var _desktop_host: DesktopUiView
var _folder_edit: LineEdit
var _file_list: Tree
var _status: Label
var _meta: Label
var _scale_slider: HSlider
var _scale_label: Label
var _vr_button: Button
var _origin_check: CheckBox
var _btn_add_pack: Button
var _btn_add_all: Button
var _env_radios: Array[CheckBox] = []
var _parent_folder := ""
var _scene_name_edit: LineEdit
var _scene_list: ItemList
var _light_option: OptionButton
var _dimmer_slider: HSlider
var _dimmer_label: Label
var _updating_ui := false
var _folder := ""
var _file_dialog: FileDialog
var _splat_label: Label
var _splat_section: Control
var _splat_list: ItemList
var _splat_folder := ""
var _splat_folder_label: Label
var _col_files: VBoxContainer
var _col_modify: VBoxContainer
var _col_scene: VBoxContainer
var _col_world: VBoxContainer
var _tabs: TabContainer
var _files_page: VBoxContainer
var _files_scroll: ScrollContainer
var _files_load_row: HBoxContainer
var _tab_scrolls: Array = []
var _parts_list: ItemList
var _parts_status: Label
var _btn_unlink: Button
var _btn_relink: Button
var _btn_delete_part: Button
var _col_tools: VBoxContainer
var _wide_row: HBoxContainer
var _narrow_stack: VBoxContainer
var _desktop_scroll: ScrollContainer
var _tools_scroll: ScrollContainer
var _vr_gutter: ColorRect
var _tint_mixer: Control
var _tint_picker: ColorPicker
var _mix_btn: Button
var _close_color_btn: Button
var _tint_preview: ColorRect
var _library_mode := false
var _library_check: CheckBox
var _tag_filter: LineEdit
var _library := ModelTagsLibrary.new()
var _tag_index := TagIndex.new()
var _host_events := HostEvents.new()
var _library_packs: Array[LibraryPack] = []
var _pack_preview: TextureRect
var _pack_card: PanelContainer
var _pack_title: Label
var _keyboard_grid: Control
var _btn_recenter_board: Button
var _vr_wide := false
var _pack_meta_label: Label
var _options_box: VBoxContainer
var _options_title: Label
var _selected_pack: LibraryPack
var _files_keyboard: Control
var _filter_debounce: Timer
var _mode_files_btn: Button
var _mode_library_btn: Button
const DEFAULT_LIBRARY_ROOT := "res://library"



func _ready() -> void:
	_build_world()
	_build_ui()
	_wire_vr_board()
	_load_settings()
	if _folder.is_empty():
		_folder = ProjectSettings.globalize_path("res://samples")
	_folder_edit.text = _folder
	_scan_folder()
	_update_status()
	if _has_flag("--smoke") or OS.get_environment("VR_VIEWER_SMOKE") == "1":
		var code := await _run_regression()
		get_tree().quit(code)
		return
	# Stay in desktop until Enter VR so the 2D view remains usable.


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.physical_keycode:
			KEY_ESCAPE:
				if _xr.xr_active:
					_raise_vr_board()
					get_viewport().set_input_as_handled()
			KEY_F1:
				_set_vr(not _xr.xr_active)
				get_viewport().set_input_as_handled()
			KEY_R:
				_assembly.return_to_origin()
				_camera.frame_aabb(_assembly.world_aabb())
				get_viewport().set_input_as_handled()


func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	_add_origin_gizmo()

	_stage = EnvironmentStage.new()
	_stage.name = "EnvironmentStage"
	_world.add_child(_stage)
	_stage.setup(_world.get_node("OriginGizmo"), null)

	_assembly = ModelAssembly.new()
	_assembly.name = "Assembly"
	_world.add_child(_assembly)
	_assembly.changed.connect(_on_assembly_changed)
	_stage.changed.connect(_on_stage_changed)

	_camera = OrbitCamera.new()
	_camera.name = "DesktopCamera"
	_world.add_child(_camera)

	_xr = XRRig.new()
	_xr.name = "XROrigin3D"
	_xr.assembly = _assembly
	_world.add_child(_xr)
	_xr.xr_started.connect(_on_xr_started)
	_xr.xr_stopped.connect(_on_xr_stopped)
	_xr.status_changed.connect(_on_xr_status)


func _wire_vr_board() -> void:
	if _xr and _xr.board and _ui_viewport:
		_xr.board.use_viewport(_ui_viewport)


func _add_origin_gizmo() -> void:
	var gizmo := Node3D.new()
	gizmo.name = "OriginGizmo"
	_world.add_child(gizmo)
	_axis(gizmo, Vector3(0.18, 0.006, 0.006), Color(0.85, 0.25, 0.22), Vector3(0.09, 0.003, 0))
	_axis(gizmo, Vector3(0.006, 0.18, 0.006), Color(0.28, 0.78, 0.32), Vector3(0, 0.09, 0))
	_axis(gizmo, Vector3(0.006, 0.006, 0.18), Color(0.28, 0.45, 0.9), Vector3(0, 0.003, 0.09))


func _axis(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)


func _build_ui() -> void:
	_filter_debounce = Timer.new()
	_filter_debounce.one_shot = true
	_filter_debounce.wait_time = 0.35
	_filter_debounce.timeout.connect(_apply_tag_filter)
	add_child(_filter_debounce)
	_ui_viewport = SubViewport.new()
	_ui_viewport.name = "UIViewport"
	_ui_viewport.size = UI_DESKTOP
	_ui_viewport.disable_3d = true
	_ui_viewport.transparent_bg = false
	_ui_viewport.handle_input_locally = true
	_ui_viewport.gui_embed_subwindows = true
	_ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ui_viewport)

	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)

	_desktop_host = DesktopUiView.new()
	_desktop_host.name = "DesktopHost"
	_desktop_host.target = _ui_viewport
	_desktop_host.texture = _ui_viewport.get_texture()
	_desktop_host.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_desktop_host.offset_right = PANEL_WIDTH
	_ui.add_child(_desktop_host)

	_side_panel = Panel.new()
	_side_panel.name = "SidePanel"
	_side_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_side_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 1.0)
	style.border_width_right = 1
	style.border_color = Color(0.22, 0.24, 0.28)
	_side_panel.add_theme_stylebox_override("panel", style)
	_ui_viewport.add_child(_side_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_side_panel.add_child(margin)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(shell)

	shell.add_child(_build_header())

	# Compat stubs — tabs replace the old dual-column layout.
	_wide_row = HBoxContainer.new()
	_wide_row.visible = false
	_vr_gutter = ColorRect.new()
	_tools_scroll = ScrollContainer.new()
	_desktop_scroll = ScrollContainer.new()
	_desktop_scroll.visible = false
	_narrow_stack = VBoxContainer.new()

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	shell.add_child(_tabs)
	_tab_scrolls.clear()

	# Files: scrollable body + sticky load row so Add pack stays reachable in 2D.
	_files_page = VBoxContainer.new()
	_files_page.name = "Files"
	_files_page.add_theme_constant_override("separation", 8)
	_files_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files_scroll = ScrollContainer.new()
	_files_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_col_files = _build_files_column()
	_col_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files_scroll.add_child(_col_files)
	_files_page.add_child(_files_scroll)
	_files_load_row = _build_files_load_row()
	_files_page.add_child(_files_load_row)
	_tabs.add_child(_files_page)
	_tab_scrolls.append(_files_scroll)

	_col_modify = _build_modify_column()
	_tabs.add_child(_wrap_tab_scroll("Modify", _col_modify))

	_col_scene = _build_scene_column()
	_tabs.add_child(_wrap_tab_scroll("Scene", _col_scene))

	_col_world = _build_world_column()
	_tabs.add_child(_wrap_tab_scroll("World", _col_world))

	_col_tools = _col_world

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Point at a folder, select files, load."
	shell.add_child(_status)

	_meta = Label.new()
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta.modulate = Color(0.68, 0.72, 0.78)
	shell.add_child(_meta)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.use_native_dialog = true
	_file_dialog.dir_selected.connect(_set_folder)
	_ui.add_child(_file_dialog)

	_apply_ui_mode(false)
	_fit_desktop_viewport()
	if _assembly and not _assembly.changed.is_connected(_refresh_parts_list):
		_assembly.changed.connect(_refresh_parts_list)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "VR Model Viewer"
	title.add_theme_font_size_override("font_size", 22)
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Desktop orbit + SteamVR / OpenXR"
	subtitle.modulate = Color(0.7, 0.74, 0.8)
	titles.add_child(subtitle)
	header.add_child(titles)
	_vr_button = _btn("Enter VR", func(): _set_vr(not _xr.xr_active))
	_vr_button.custom_minimum_size = Vector2(140, 44)
	header.add_child(_vr_button)
	return header



func _wrap_tab_scroll(tab_name: String, body: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	_tab_scrolls.append(sc)
	return sc


func _build_files_load_row() -> HBoxContainer:
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	_btn_add_pack = _btn("Add pack / files", _load_selected)
	_btn_add_pack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_btn_add_pack)
	_btn_add_all = _btn("Add all", _load_all)
	load_row.add_child(_btn_add_all)
	load_row.add_child(_btn("Clear", func(): _assembly.clear(); _refresh_parts_list()))
	return load_row


func _fit_desktop_viewport() -> void:
	## Match UI SubViewport height to the game window so 2D isn't a tiny fixed canvas.
	if _ui_viewport == null or _vr_wide:
		return
	var win_h := int(get_window().size.y)
	var h := clampi(win_h, 960, 2000)
	var w := int(PANEL_WIDTH)
	if _ui_viewport.size.x != w or _ui_viewport.size.y != h:
		_ui_viewport.size = Vector2i(w, h)
	if _desktop_host:
		_desktop_host.offset_right = PANEL_WIDTH


func _build_files_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.2
	col.add_child(_section("Files"))
	var folder_row := HBoxContainer.new()
	_folder_edit = LineEdit.new()
	_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_edit.placeholder_text = "Folder"
	_folder_edit.text_submitted.connect(func(text): _set_folder(text))
	folder_row.add_child(_folder_edit)
	folder_row.add_child(_btn("Up", _go_up))
	col.add_child(folder_row)
	var jump := HBoxContainer.new()
	jump.add_child(_btn("Home", func(): _set_folder(OS.get_environment("USERPROFILE") if OS.get_environment("USERPROFILE") != "" else OS.get_environment("HOME"))))
	jump.add_child(_btn("C:/", func(): _set_folder("C:/")))
	jump.add_child(_btn("Samples", func(): _set_folder(ProjectSettings.globalize_path("res://samples"))))
	col.add_child(jump)
	var mode_row := HBoxContainer.new()
	col.add_child(mode_row)
	_mode_files_btn = Button.new()
	_mode_files_btn.text = "Classic files"
	_mode_files_btn.toggle_mode = true
	_mode_files_btn.button_pressed = true
	_mode_files_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_files_btn.pressed.connect(func(): _set_view_mode(false))
	mode_row.add_child(_mode_files_btn)
	_mode_library_btn = Button.new()
	_mode_library_btn.text = "Library"
	_mode_library_btn.toggle_mode = true
	_mode_library_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_library_btn.pressed.connect(func(): _set_view_mode(true))
	mode_row.add_child(_mode_library_btn)
	_library_check = CheckBox.new()
	_library_check.text = "Library mode (model-tags)"
	_library_check.visible = false
	_library_check.toggled.connect(_on_library_mode)
	col.add_child(_library_check)
	_tag_filter = LineEdit.new()
	_tag_filter.placeholder_text = "tags AND-filter (e.g. hogtie, latex)"
	_tag_filter.visible = false
	_tag_filter.focus_mode = Control.FOCUS_ALL
	_tag_filter.text_changed.connect(_on_tag_filter_changed)
	_tag_filter.text_submitted.connect(func(_t): _apply_tag_filter())
	_tag_filter.gui_input.connect(_on_tag_filter_gui_input)
	_tag_filter.focus_entered.connect(_on_tag_filter_focus)
	col.add_child(_tag_filter)
	var filter_row := HBoxContainer.new()
	filter_row.add_child(_btn("Apply filter", _apply_tag_filter))
	filter_row.add_child(_btn("Clear filter", func(): _tag_filter.text = ""; _apply_tag_filter()))
	col.add_child(filter_row)
	_pack_preview = TextureRect.new()
	_pack_preview.custom_minimum_size = Vector2(0, 140)
	_pack_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pack_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pack_preview.visible = false
	col.add_child(_pack_preview)
	_pack_title = Label.new()
	_pack_title.visible = false
	_pack_title.add_theme_font_size_override("font_size", 18)
	_pack_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_pack_title)
	_pack_meta_label = Label.new()
	_pack_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pack_meta_label.visible = false
	col.add_child(_pack_meta_label)
	_options_title = Label.new()
	_options_title.text = "Options"
	_options_title.visible = false
	col.add_child(_options_title)
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 6)
	_options_box.visible = false
	col.add_child(_options_box)
	_files_keyboard = _build_keyboard()
	_files_keyboard.visible = false  # 2D has a physical keyboard; VR shows it
	col.add_child(_files_keyboard)

	_file_list = Tree.new()
	_file_list.columns = 2
	_file_list.hide_root = true
	_file_list.column_titles_visible = true
	_file_list.set_column_title(0, "Name")
	_file_list.set_column_title(1, "Ext")
	_file_list.set_column_expand(0, true)
	_file_list.set_column_expand(1, false)
	_file_list.set_column_clip_content(0, true)
	_file_list.set_column_custom_minimum_width(1, 64)
	_file_list.select_mode = Tree.SELECT_MULTI
	_file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_list.custom_minimum_size = Vector2(0, 260)
	_file_list.add_theme_font_size_override("font_size", 16)
	_file_list.item_activated.connect(_on_file_activated)
	_file_list.item_mouse_selected.connect(_on_file_mouse_selected)
	col.add_child(_file_list)

	# Load / Clear live in the sticky footer outside the scroll (_build_files_load_row).
	return col


func _build_modify_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	col.add_child(_section("Size"))
	var scale_row := HBoxContainer.new()
	_scale_label = Label.new()
	_scale_label.custom_minimum_size.x = 110
	_scale_label.text = "Size 100%"
	scale_row.add_child(_scale_label)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 10
	_scale_slider.max_value = 400
	_scale_slider.step = 10
	_scale_slider.value = 100
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.custom_minimum_size = Vector2(0, 36)
	_scale_slider.value_changed.connect(_on_scale_slider)
	scale_row.add_child(_scale_slider)
	col.add_child(scale_row)
	col.add_child(_btn("Return to origin", func(): _assembly.return_to_origin(); _camera.frame_aabb(_assembly.world_aabb())))

	col.add_child(_sep())
	col.add_child(_build_color_editor())

	col.add_child(_sep())
	col.add_child(_section("Parts / groups"))
	_parts_status = Label.new()
	_parts_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_parts_status.text = "Load a pack to create a linked group (shared origin)."
	col.add_child(_parts_status)
	_parts_list = ItemList.new()
	_parts_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts_list.custom_minimum_size = Vector2(0, 220)
	_parts_list.add_theme_font_size_override("font_size", 16)
	col.add_child(_parts_list)
	var prow := HBoxContainer.new()
	_btn_unlink = _btn("Unlink", _on_unlink_part)
	_btn_relink = _btn("Link", _on_relink_part)
	_btn_delete_part = _btn("Delete part", _on_delete_part)
	prow.add_child(_btn_unlink)
	prow.add_child(_btn_relink)
	prow.add_child(_btn_delete_part)
	col.add_child(prow)
	_origin_check = CheckBox.new()
	_origin_check.text = "Classic: assemble by shared origin"
	_origin_check.button_pressed = false
	_origin_check.toggled.connect(func(v): _assembly.keep_shared_origin = v)
	col.add_child(_origin_check)
	return col


func _build_scene_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_section("Scenes"))
	_scene_name_edit = LineEdit.new()
	_scene_name_edit.placeholder_text = "Scene name"
	_scene_name_edit.custom_minimum_size = Vector2(0, 44)
	col.add_child(_scene_name_edit)
	col.add_child(_build_keyboard())
	var scene_btns := HBoxContainer.new()
	scene_btns.add_child(_btn("Save", _save_scene))
	scene_btns.add_child(_btn("Load", _load_scene))
	scene_btns.add_child(_btn("Delete", _delete_scene))
	col.add_child(scene_btns)
	_scene_list = ItemList.new()
	_scene_list.custom_minimum_size = Vector2(0, 200)
	_scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_list.item_selected.connect(func(i): _scene_name_edit.text = _scene_list.get_item_text(i))
	col.add_child(_scene_list)
	_refresh_scene_list()
	return col


func _build_world_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_section("Environment"))
	col.add_child(_build_env_radios())
	col.add_child(_build_splat_section())

	var light_row := HBoxContainer.new()
	var light_name := Label.new()
	light_name.text = "Lighting"
	light_name.custom_minimum_size.x = 90
	light_row.add_child(light_name)
	_light_option = OptionButton.new()
	_light_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_option.custom_minimum_size = Vector2(0, 44)
	_light_option.item_selected.connect(_on_light_selected)
	light_row.add_child(_light_option)
	col.add_child(light_row)
	_fill_light_options()

	var dim_row := HBoxContainer.new()
	_dimmer_label = Label.new()
	_dimmer_label.custom_minimum_size.x = 130
	_dimmer_label.text = "Light 1.00x"
	dim_row.add_child(_dimmer_label)
	_dimmer_slider = HSlider.new()
	_dimmer_slider.min_value = 0.15
	_dimmer_slider.max_value = 2.0
	_dimmer_slider.step = 0.01
	_dimmer_slider.value = 1.0
	_dimmer_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dimmer_slider.custom_minimum_size = Vector2(0, 36)
	_dimmer_slider.value_changed.connect(_on_dimmer)
	dim_row.add_child(_dimmer_slider)
	col.add_child(dim_row)

	var surround_row := HBoxContainer.new()
	var surround_lab := Label.new()
	surround_lab.text = "Surround"
	surround_lab.custom_minimum_size.x = 90
	surround_row.add_child(surround_lab)
	var surround_s := HSlider.new()
	surround_s.min_value = 0.05
	surround_s.max_value = 1.0
	surround_s.step = 0.05
	surround_s.value = 0.28
	surround_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surround_s.custom_minimum_size = Vector2(0, 36)
	surround_s.value_changed.connect(func(v): _stage.set_surround(v))
	surround_row.add_child(surround_s)
	col.add_child(surround_row)

	var contrast_row := HBoxContainer.new()
	var contrast_lab := Label.new()
	contrast_lab.text = "Contrast"
	contrast_lab.custom_minimum_size.x = 90
	contrast_row.add_child(contrast_lab)
	var contrast_s := HSlider.new()
	contrast_s.min_value = 0.7
	contrast_s.max_value = 2.0
	contrast_s.step = 0.05
	contrast_s.value = 1.15
	contrast_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contrast_s.custom_minimum_size = Vector2(0, 36)
	contrast_s.value_changed.connect(func(v): _stage.set_contrast(v))
	contrast_row.add_child(contrast_s)
	col.add_child(contrast_row)

	_btn_recenter_board = _btn("Recenter board", _raise_vr_board)
	_btn_recenter_board.visible = false
	col.add_child(_btn_recenter_board)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.55, 0.58, 0.64)
	help.text = "VR: A raises this board. Trigger clicks UI or grabs a linked group / free part. Both triggers scale. Stick walks / turns."
	col.add_child(help)
	return col


func _build_tools_column() -> VBoxContainer:
	# Compat shim — World tab owns env/lighting now.
	return _build_world_column()


func _build_env_radios() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_env_radios.clear()
	for i in EnvironmentStage.ENV_IDS.size():
		var box := CheckBox.new()
		box.text = EnvironmentStage.ENV_LABELS[i]
		box.button_group = group
		box.button_pressed = i == 0
		box.custom_minimum_size = Vector2(0, 36)
		box.toggled.connect(_on_env_radio.bind(i))
		_env_radios.append(box)
		grid.add_child(box)
	return grid


func _build_splat_section() -> Control:
	_splat_section = VBoxContainer.new()
	_splat_section.add_theme_constant_override("separation", 6)
	_splat_section.visible = false
	var head := Label.new()
	head.text = "Splat captures"
	head.modulate = Color(0.78, 0.82, 0.88)
	_splat_section.add_child(head)
	_splat_folder_label = Label.new()
	_splat_folder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_splat_folder_label.modulate = Color(0.68, 0.72, 0.78)
	_splat_section.add_child(_splat_folder_label)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.58, 0.62, 0.68)
	hint.text = "Drop .ply / .splat / .sog files into the app splats folder."
	_splat_section.add_child(hint)
	var row := HBoxContainer.new()
	row.add_child(_btn("Refresh", _scan_splat_folder))
	row.add_child(_btn("Up", _splat_go_up))
	_splat_section.add_child(row)
	_splat_list = ItemList.new()
	_splat_list.select_mode = ItemList.SELECT_SINGLE
	_splat_list.custom_minimum_size = Vector2(0, 140)
	_splat_list.add_theme_font_size_override("font_size", 16)
	_splat_list.add_theme_constant_override("v_separation", 6)
	_splat_list.item_activated.connect(_on_splat_activated)
	_splat_list.item_clicked.connect(_on_splat_clicked)
	_splat_section.add_child(_splat_list)
	_splat_section.add_child(_btn("Load splat", _load_selected_splat_file))
	_splat_label = Label.new()
	_splat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_splat_label.modulate = Color(0.72, 0.76, 0.82)
	_splat_label.text = "Splat: none"
	_splat_section.add_child(_splat_label)
	_splat_folder = SplatLoader.app_dir()
	return _splat_section


func _build_color_editor() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.add_child(_section("Model color"))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_tint_preview = ColorRect.new()
	_tint_preview.custom_minimum_size = Vector2(36, 36)
	_tint_preview.color = Color(0.92, 0.92, 0.93)
	top.add_child(_tint_preview)
	_mix_btn = _btn("Mix color", _open_color_mixer)
	_mix_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_mix_btn)
	_close_color_btn = _btn("Close color", _close_color_mixer)
	_close_color_btn.visible = false
	top.add_child(_close_color_btn)
	wrap.add_child(top)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var presets := [
		["Clay", Color(0.92, 0.92, 0.93)],
		["White", Color(0.97, 0.97, 0.98)],
		["Steel", Color(0.58, 0.62, 0.66)],
		["Black", Color(0.12, 0.12, 0.13)],
		["Red", Color(0.82, 0.24, 0.18)],
		["Blue", Color(0.24, 0.44, 0.82)],
		["Gold", Color(0.82, 0.68, 0.28)],
		["Green", Color(0.28, 0.62, 0.38)],
	]
	for item in presets:
		flow.add_child(_preset_swatch(str(item[0]), item[1]))
	wrap.add_child(flow)

	_tint_mixer = VBoxContainer.new()
	_tint_mixer.visible = false
	_tint_mixer.add_theme_constant_override("separation", 8)
	_tint_picker = ColorPicker.new()
	_tint_picker.color = Color(0.92, 0.92, 0.93)
	_tint_picker.edit_alpha = false
	_tint_picker.sampler_visible = false
	_tint_picker.color_modes_visible = false
	_tint_picker.presets_visible = false
	_tint_picker.hex_visible = true
	_tint_picker.sliders_visible = true
	_tint_picker.picker_shape = ColorPicker.SHAPE_NONE
	_tint_picker.custom_minimum_size = Vector2(0, 150)
	_tint_picker.color_changed.connect(_on_tint_picker)
	_tint_mixer.add_child(_tint_picker)
	var done := _btn("Close color", _close_color_mixer)
	done.custom_minimum_size.y = 48
	_tint_mixer.add_child(done)
	wrap.add_child(_tint_mixer)
	return wrap


func _preset_swatch(label: String, color: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(72, 40)
	b.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.08)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var luma := color.get_luminance()
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.09) if luma > 0.45 else Color(0.95, 0.95, 0.96))
	b.pressed.connect(func(): _apply_tint(color, true))
	return b


func _open_color_mixer() -> void:
	if _tint_picker:
		_tint_picker.color = _assembly.model_tint
	if _tint_mixer:
		_tint_mixer.visible = true
	if _close_color_btn:
		_close_color_btn.visible = true
	if _mix_btn:
		_mix_btn.visible = false


func _close_color_mixer() -> void:
	if _tint_mixer:
		_tint_mixer.visible = false
	if _close_color_btn:
		_close_color_btn.visible = false
	if _mix_btn:
		_mix_btn.visible = true


func _on_tint_picker(color: Color) -> void:
	_apply_tint(color, false)


func _apply_tint(color: Color, close_mixer: bool) -> void:
	_assembly.set_model_tint(color)
	if _tint_preview:
		_tint_preview.color = color
	if _tint_picker and not _tint_picker.color.is_equal_approx(color):
		_tint_picker.set_block_signals(true)
		_tint_picker.color = color
		_tint_picker.set_block_signals(false)
	if close_mixer:
		_close_color_mixer()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not _vr_wide:
			_fit_desktop_viewport()


func _apply_ui_mode(wide: bool) -> void:
	if _ui_viewport == null or _tabs == null:
		return
	_vr_wide = wide
	if wide:
		_ui_viewport.size = UI_VR
	else:
		_fit_desktop_viewport()
	if _desktop_host:
		_desktop_host.offset_right = PANEL_WIDTH
		_desktop_host.visible = not wide
	var btn_h := 52 if wide else 44
	# Desktop: smaller list mins + scroll so Add pack stays on-screen.
	var list_h := 420 if wide else 180
	var preview_h := 240 if wide else 120
	if _file_list:
		_file_list.custom_minimum_size = Vector2(0, list_h)
		_file_list.add_theme_font_size_override("font_size", 18 if wide else 16)
	if _parts_list:
		_parts_list.custom_minimum_size = Vector2(0, 260 if wide else 200)
		_parts_list.add_theme_font_size_override("font_size", 18 if wide else 16)
	if _scene_list:
		_scene_list.custom_minimum_size = Vector2(0, 220 if wide else 160)
	if _splat_list:
		_splat_list.custom_minimum_size = Vector2(0, 180 if wide else 140)
	if _pack_preview:
		_pack_preview.custom_minimum_size = Vector2(0, preview_h)
	if _tag_filter:
		_tag_filter.custom_minimum_size = Vector2(0, 48 if wide else 0)
		_tag_filter.add_theme_font_size_override("font_size", 18 if wide else 16)
	if _btn_add_pack:
		_btn_add_pack.custom_minimum_size = Vector2(0, btn_h)
		_btn_add_pack.add_theme_font_size_override("font_size", 18 if wide else 16)
	if _btn_recenter_board:
		_btn_recenter_board.visible = wide
	# Desktop tabs scroll; VR board is sized to fit so keep scroll off when possible.
	for sc in _tab_scrolls:
		if sc is ScrollContainer:
			sc.vertical_scroll_mode = (
				ScrollContainer.SCROLL_MODE_DISABLED if wide else ScrollContainer.SCROLL_MODE_AUTO
			)
	if _files_scroll:
		_files_scroll.vertical_scroll_mode = (
			ScrollContainer.SCROLL_MODE_DISABLED if wide else ScrollContainer.SCROLL_MODE_AUTO
		)
	if _files_load_row:
		_files_load_row.visible = true
	if _files_keyboard:
		_files_keyboard.visible = wide
	if not wide and _keyboard_grid:
		_keyboard_grid.visible = false
	if _status:
		_status.add_theme_font_size_override("font_size", 16 if wide else 14)
	if _tabs:
		_tabs.add_theme_font_size_override("font_size", 18 if wide else 16)
	if _xr and _xr.board:
		_xr.board.use_viewport(_ui_viewport)


func _reparent_ui(node: Node, new_parent: Node) -> void:
	if node == null or new_parent == null or node.get_parent() == new_parent:
		return
	var parent := node.get_parent()
	if parent:
		parent.remove_child(node)
	new_parent.add_child(node)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.78, 0.82, 0.88)
	return l


func _sep() -> HSeparator:
	return HSeparator.new()


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b


func _build_keyboard() -> Control:
	var wrap := VBoxContainer.new()
	var toggle := Button.new()
	toggle.text = "Keyboard"
	toggle.custom_minimum_size = Vector2(0, 44)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.visible = false
	_keyboard_grid = grid
	toggle.pressed.connect(func():
		grid.visible = not grid.visible
		if grid.visible:
			_focus_library_filter()
	)
	wrap.add_child(toggle)
	wrap.add_child(grid)
	var keys := "1234567890QWERTYUIOPASDFGHJKLZXCVBNM-,"
	for i in keys.length():
		var ch := keys.substr(i, 1)
		var b := Button.new()
		b.text = ch
		b.custom_minimum_size = Vector2(40, 42)
		b.pressed.connect(func(): _type_into_name(ch))
		grid.add_child(b)
	var row := HBoxContainer.new()
	var space := Button.new()
	space.text = "Space"
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.pressed.connect(func(): _type_into_name(" "))
	var bk := Button.new()
	bk.text = "Bksp"
	bk.pressed.connect(_backspace_name)
	row.add_child(space)
	row.add_child(bk)
	wrap.add_child(row)
	return wrap




func _on_tag_filter_focus() -> void:
	if not _vr_wide:
		return
	if _files_keyboard:
		_files_keyboard.visible = true
	if _keyboard_grid:
		_keyboard_grid.visible = true



func _refresh_parts_list() -> void:
	if _parts_list == null:
		return
	_parts_list.clear()
	var rows: Array = _assembly.list_part_rows()
	for row in rows:
		var mark := "[L]" if bool(row.get("linked", false)) else "[ ]"
		var g := str(row.get("group_name", ""))
		var label := "%s %s" % [mark, str(row.get("name", "part"))]
		if g != "":
			label += "  -  %s" % g
		_parts_list.add_item(label)
		_parts_list.set_item_metadata(_parts_list.item_count - 1, row.get("part"))
	if _parts_status:
		var n := rows.size()
		var linked_n := 0
		for row2 in rows:
			if bool(row2.get("linked", false)):
				linked_n += 1
		_parts_status.text = "%s part%s - %s linked. Unlink to move/delete alone; Link keeps current pose." % [
			n, "" if n == 1 else "s", linked_n
		]


func _selected_part_from_list() -> Node3D:
	if _parts_list == null or _parts_list.get_selected_items().is_empty():
		return null
	var i: int = _parts_list.get_selected_items()[0]
	var meta = _parts_list.get_item_metadata(i)
	return meta as Node3D


func _on_unlink_part() -> void:
	var part := _selected_part_from_list()
	if part == null:
		_status.text = "Select a part in Modify."
		return
	_assembly.set_part_linked(part, false)
	_refresh_parts_list()
	_status.text = "Unlinked - move or delete freely."


func _on_relink_part() -> void:
	var part := _selected_part_from_list()
	if part == null:
		_status.text = "Select a part in Modify."
		return
	_assembly.set_part_linked(part, true)
	_refresh_parts_list()
	_status.text = "Linked - keeps current offset in its group."


func _on_delete_part() -> void:
	var part := _selected_part_from_list()
	if part == null:
		_status.text = "Select a part in Modify."
		return
	_assembly.remove_part(part)
	_refresh_parts_list()
	_update_status()
	_status.text = "Deleted one part."


func _focus_library_filter() -> void:
	if _tag_filter == null or not _tag_filter.visible:
		return
	_tag_filter.grab_focus()
	_tag_filter.caret_column = _tag_filter.text.length()


func _active_line_edit() -> LineEdit:
	if _tag_filter != null and _tag_filter.visible and _tag_filter.has_focus():
		return _tag_filter
	if _folder_edit != null and _folder_edit.editable and _folder_edit.has_focus():
		return _folder_edit
	if _scene_name_edit != null and _scene_name_edit.has_focus():
		return _scene_name_edit
	# Library filter is the usual target when browsing packs.
	if _library_mode and _tag_filter != null and _tag_filter.visible:
		return _tag_filter
	if _folder_edit != null and _folder_edit.editable and _folder_edit.visible:
		# Prefer scene name when both available and neither focused.
		pass
	return _scene_name_edit


func _type_into_name(ch: String) -> void:
	var edit := _active_line_edit()
	if edit == null:
		return
	if edit == _folder_edit:
		_folder_edit.text += ch
		_set_folder(_folder_edit.text)
		return
	edit.text += ch
	edit.caret_column = edit.text.length()
	if edit == _tag_filter:
		_on_tag_filter_changed(edit.text)
		edit.grab_focus()


func _backspace_name() -> void:
	var edit := _active_line_edit()
	if edit == null:
		return
	if edit == _folder_edit:
		var t := _folder_edit.text
		if t.length() > 0:
			_set_folder(t.substr(0, t.length() - 1))
		return
	var s := edit.text
	if s.length() > 0:
		edit.text = s.substr(0, s.length() - 1)
		edit.caret_column = edit.text.length()
	if edit == _tag_filter:
		_on_tag_filter_changed(edit.text)
		edit.grab_focus()


func _go_up() -> void:
	var parent := _folder.get_base_dir()
	if parent != "" and parent != _folder:
		_set_folder(parent)


func _set_folder(path: String) -> void:
	if path.is_empty():
		return
	_folder = path.replace("\\", "/")
	if _folder.ends_with(":") :
		_folder += "/"
	_folder_edit.text = _folder
	_save_settings()
	# Tree forbids clear/create during item_mouse_selected; always rebuild next frame.
	call_deferred("_scan_folder")


func _scan_folder() -> void:
	_file_list.clear()
	var root := _file_list.create_item()
	if root == null:
		call_deferred("_scan_folder")
		return
	root.set_text(0, _folder)
	if not DirAccess.dir_exists_absolute(_folder):
		_status.text = "Folder not found."
		return
	if _library_mode:
		_scan_library()
		return
	var dir := DirAccess.open(_folder)
	if dir == null:
		_status.text = "Cannot open folder."
		return
	dir.list_dir_begin()
	var dirs: PackedStringArray = []
	var files: PackedStringArray = []
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := _folder.path_join(name)
		if dir.current_is_dir():
			dirs.append(full)
		elif ModelLoader.is_mesh_file(full):
			files.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	dirs.sort()
	files.sort()
	for p in dirs:
		_add_file_row(p.get_file(), "dir", p)
	for p in files:
		_add_file_row(p.get_file(), p.get_extension().to_upper(), p)
	_status.text = "%s folders, %s meshes" % [dirs.size(), files.size()]


func _set_view_mode(library: bool) -> void:
	_library_mode = library
	if _mode_files_btn:
		_mode_files_btn.set_pressed_no_signal(not library)
	if _mode_library_btn:
		_mode_library_btn.set_pressed_no_signal(library)
	if _library_check:
		_library_check.set_pressed_no_signal(library)
	if _tag_filter:
		_tag_filter.visible = library
	if _pack_preview:
		_pack_preview.visible = library
	if _pack_meta_label:
		_pack_meta_label.visible = library
	if _pack_title:
		_pack_title.visible = library and _pack_title.text != ""
	if _options_title:
		_options_title.visible = library
	if _options_box:
		_options_box.visible = library
		if not library:
			_clear_options_ui()
			_selected_pack = null
	if _btn_add_pack:
		_btn_add_pack.text = "Add pack" if library else "Add pack / files"
	if _btn_add_all:
		# Library lists packs, not loose meshes — Add all is a Classic-files tool.
		_btn_add_all.visible = not library
	if _origin_check:
		# Library loads decide shared-origin from pack multipart; no per-file pick.
		_origin_check.visible = not library
	if library:
		var lib_path := ProjectSettings.globalize_path(DEFAULT_LIBRARY_ROOT)
		_folder = lib_path
		if _folder_edit:
			_folder_edit.text = lib_path
			_folder_edit.editable = false
		_file_list.set_column_title(0, "Pack")
		_file_list.set_column_title(1, "Tags")
	else:
		if _folder_edit:
			_folder_edit.editable = true
		_file_list.set_column_title(0, "Name")
		_file_list.set_column_title(1, "Ext")
		if _pack_preview:
			_pack_preview.texture = null
		if _pack_meta_label:
			_pack_meta_label.text = ""
	_save_settings()
	_scan_folder()


func _show_pack_preview(pack: LibraryPack) -> void:
	_selected_pack = pack
	_rebuild_options_ui(pack)
	if _pack_preview == null:
		return
	if pack == null:
		_pack_preview.texture = null
		if _pack_title:
			_pack_title.text = ""
			_pack_title.visible = false
		if _pack_meta_label:
			_pack_meta_label.text = ""
		return
	var tex: Texture2D = null
	for rel in pack.previews:
		var path := pack.folder.path_join(str(rel))
		if not FileAccess.file_exists(path):
			continue
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			continue
		tex = ImageTexture.create_from_image(img)
		break
	_pack_preview.texture = tex
	if _pack_title:
		var title := pack.display_name if pack.display_name != "" else pack.pack_id
		var ip := ""
		var character := ""
		if pack.identity is Dictionary:
			ip = str(pack.identity.get("ip", "")).strip_edges()
			character = str(pack.identity.get("character", "")).strip_edges()
		var headline := title
		if character != "":
			headline = "%s  ·  %s" % [title, character]
		elif ip != "":
			headline = "%s  ·  %s" % [title, ip]
		_pack_title.text = headline
		_pack_title.visible = true
	if _pack_meta_label:
		var nice: PackedStringArray = []
		for t in pack.tags:
			var s := str(t)
			if s.begins_with("artist-") or s == "multipart":
				continue
			nice.append(s)
		var tags := " · ".join(nice)
		if tags.length() > 160:
			tags = tags.substr(0, 157) + "..."
		var n_mesh := pack.parts.size()
		var opt_n := pack.options.size() if pack.options is Array else 0
		var bits := "%s mesh%s" % [n_mesh, "" if n_mesh == 1 else "es"]
		if opt_n > 0:
			bits += " · %s option group%s" % [opt_n, "" if opt_n == 1 else "s"]
		if tex == null:
			bits += " · no preview yet"
		_pack_meta_label.text = bits + ("\n" + tags if tags != "" else "")
		_pack_meta_label.visible = true
	if _status and _vr_wide:
		_status.text = "Selected - %s" % (pack.display_name if pack.display_name != "" else pack.pack_id)


func _on_library_mode(on: bool) -> void:
	_set_view_mode(on)


func _scan_library() -> void:
	var lib_path := ProjectSettings.globalize_path(DEFAULT_LIBRARY_ROOT)
	_library.set_root(lib_path)
	if _folder_edit:
		_folder_edit.text = lib_path
		_folder_edit.editable = false
	_folder = lib_path
	_library_packs = _library.list_packs()
	_tag_index.rebuild(_library_packs)
	var query := ""
	if _tag_filter:
		query = _tag_filter.text.strip_edges()
	var shown: Array[LibraryPack] = _tag_index.packs_matching_query(query)
	for pack in shown:
		var item := _file_list.create_item()
		var title := pack.display_name if pack.display_name != "" else pack.pack_id
		item.set_text(0, title)
		var tag_bits: PackedStringArray = []
		for t in pack.tags:
			var s := str(t)
			if s.begins_with("artist-") or s == "multipart":
				continue
			tag_bits.append(s)
			if tag_bits.size() >= 3:
				break
		var tag_line := ", ".join(tag_bits)
		if tag_line.is_empty():
			tag_line = "pack"
		elif tag_line.length() > 28:
			tag_line = tag_line.substr(0, 25) + "..."
		item.set_text(1, tag_line)
		item.set_metadata(0, {"kind": "pack", "pack_id": pack.pack_id})
		var ip := str(pack.identity.get("ip", "")) if pack.identity is Dictionary else ""
		var tip := title
		if ip != "":
			tip += " · " + ip
		tip += "\n" + ", ".join(pack.tags)
		item.set_tooltip_text(0, tip)
		item.set_custom_minimum_height(36 if _vr_wide else 28)
	_status.text = "%s pack%s%s" % [
		shown.size(),
		"" if shown.size() == 1 else "s",
		(" tagged %s" % query) if query != "" else "",
	]




func _on_tag_filter_changed(_t: String) -> void:
	if _filter_debounce:
		_filter_debounce.start()


func _on_tag_filter_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_tag_filter.grab_focus()


func _apply_tag_filter() -> void:
	var keep := _tag_filter.text if _tag_filter else ""
	_scan_folder()
	if _tag_filter and _library_mode:
		_tag_filter.text = keep
		_tag_filter.caret_column = keep.length()
		_tag_filter.call_deferred("grab_focus")


func _clear_options_ui() -> void:
	if _options_box == null:
		return
	for child in _options_box.get_children():
		child.queue_free()


func _rebuild_options_ui(pack: LibraryPack) -> void:
	_clear_options_ui()
	if _options_box == null:
		return
	var has := pack != null and pack.options is Array and pack.options.size() > 0
	if _options_title:
		_options_title.visible = _library_mode and has
	_options_box.visible = _library_mode and has
	if not has:
		return
	for group in pack.options:
		if typeof(group) != TYPE_DICTIONARY:
			continue
		var mode := str(group.get("mode", "exclusive"))
		var gid := str(group.get("id", ""))
		var label := str(group.get("label", gid))
		var choices: Array = group.get("choices", [])
		var title := Label.new()
		title.text = label
		_options_box.add_child(title)
		if mode == "toggle":
			for ch in choices:
				if typeof(ch) != TYPE_DICTIONARY:
					continue
				var cid := str(ch.get("id", ""))
				var cb := CheckBox.new()
				cb.text = str(ch.get("label", cid))
				cb.button_pressed = bool(ch.get("default", false))
				cb.custom_minimum_size = Vector2(0, 44)
				cb.set_meta("opt_group", gid)
				cb.set_meta("opt_choice", cid)
				cb.set_meta("opt_mode", "toggle")
				_options_box.add_child(cb)
		else:
			# Exclusive Buttons — OptionButton popups break in SubViewport/VR.
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.set_meta("opt_group", gid)
			row.set_meta("opt_mode", "exclusive")
			var btn_group := ButtonGroup.new()
			for ch in choices:
				if typeof(ch) != TYPE_DICTIONARY:
					continue
				var cid := str(ch.get("id", ""))
				var clabel := str(ch.get("label", cid))
				var b := Button.new()
				b.text = clabel
				b.toggle_mode = true
				b.button_group = btn_group
				b.custom_minimum_size = Vector2(0, 44)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.set_meta("opt_choice", cid)
				b.button_pressed = bool(ch.get("default", false))
				row.add_child(b)
			var any_on := false
			for child2 in row.get_children():
				if child2 is Button and (child2 as Button).button_pressed:
					any_on = true
					break
			if not any_on and row.get_child_count() > 0:
				var first := row.get_child(0) as Button
				if first:
					first.button_pressed = true
			_options_box.add_child(row)


func _read_option_selections() -> Dictionary:
	var out: Dictionary = {}
	if _options_box == null:
		return out
	for child in _options_box.get_children():
		if not child.has_meta("opt_mode"):
			continue
		var mode := str(child.get_meta("opt_mode"))
		var gid := str(child.get_meta("opt_group"))
		if mode == "exclusive":
			for b in child.get_children():
				if b is Button and (b as Button).button_pressed:
					out[gid] = str(b.get_meta("opt_choice"))
					break
		elif mode == "toggle" and child is CheckBox:
			var cb := child as CheckBox
			if not cb.button_pressed:
				continue
			var cid := str(cb.get_meta("opt_choice"))
			if not out.has(gid):
				out[gid] = []
			(out[gid] as Array).append(cid)
	return out


func _pack_by_id(pack_id: String) -> LibraryPack:
	for pack in _library_packs:
		if pack.pack_id == pack_id:
			return pack
	return null


func _add_file_row(label: String, ext: String, path: String) -> void:
	var item := _file_list.create_item()
	item.set_text(0, label)
	item.set_text(1, ext)
	item.set_metadata(0, path)
	item.set_tooltip_text(0, path)


func _file_row_count() -> int:
	var root := _file_list.get_root()
	if root == null:
		return 0
	return root.get_child_count()


func _on_file_activated() -> void:
	var item := _file_list.get_selected()
	if item:
		await _open_or_load_item(item)


func _on_file_mouse_selected(_at: Vector2, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT:
		return
	var item := _file_list.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY:
		var pack := _pack_by_id(str(meta.get("pack_id", "")))
		_host_events.selection_changed.emit(pack)
		_show_pack_preview(pack)
		return
	var path := str(meta)
	if DirAccess.dir_exists_absolute(path):
		_set_folder(path)


func _open_or_load_item(item: TreeItem) -> void:
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY and str(meta.get("kind", "")) == "pack":
		await _load_library_pack(_pack_by_id(str(meta.get("pack_id", ""))))
		return
	var path := str(meta)
	if DirAccess.dir_exists_absolute(path):
		_set_folder(path)
		return
	if ModelLoader.is_mesh_file(path):
		await _load_paths(PackedStringArray([path]))


func _selected_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var item := _file_list.get_next_selected(null)
	while item:
		var path := str(item.get_metadata(0))
		if ModelLoader.is_mesh_file(path) and FileAccess.file_exists(path):
			out.append(path)
		item = _file_list.get_next_selected(item)
	return out


func _all_mesh_paths_in_list() -> PackedStringArray:
	var out := PackedStringArray()
	var root := _file_list.get_root()
	if root == null:
		return out
	var item := root.get_first_child()
	while item:
		var path := str(item.get_metadata(0))
		if ModelLoader.is_mesh_file(path) and FileAccess.file_exists(path):
			out.append(path)
		item = item.get_next()
	return out


func _load_selected() -> void:
	var selected := _file_list.get_next_selected(null)
	if selected == null:
		_status.text = "Select a pack or mesh files."
		return
	var meta: Variant = selected.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY and str(meta.get("kind", "")) == "pack":
		await _load_library_pack(_pack_by_id(str(meta.get("pack_id", ""))))
		return
	if selected != null and _file_list.get_next_selected(selected) == null:
		var only := str(meta)
		if DirAccess.dir_exists_absolute(only):
			_set_folder(only)
			return
	var paths := _selected_paths()
	if paths.is_empty():
		_status.text = "Select mesh files (stl/obj/glb/gltf/fbx), or click a folder to open it."
		return
	await _load_paths(paths)


func _load_library_pack(pack: LibraryPack) -> void:
	if pack == null:
		_status.text = "Unknown pack."
		return
	var paths := _library.resolve_meshes(pack, _read_option_selections())
	if paths.is_empty():
		_status.text = "Pack '%s' has no mesh files." % pack.pack_id
		return
	var start_n := _assembly.parts.size()
	var shared := pack.is_multipart()
	_assembly.keep_shared_origin = shared
	if _origin_check:
		_origin_check.button_pressed = shared
	_host_events.pack_opened.emit(pack)
	_host_events.assembly_load_requested.emit(paths, shared)
	_status.text = "Adding pack %s..." % pack.pack_id
	await get_tree().process_frame
	_assembly.load_paths(paths, false, start_n == 0)
	if start_n > 0:
		_assembly.offset_parts_from_index(start_n)
		_assembly.ground_parts_from_index(start_n)
	var gname := pack.display_name if pack.display_name != "" else pack.pack_id
	_assembly.create_link_group_from_index(start_n, gname)
	_refresh_parts_list()
	if not _xr.xr_active:
		_camera.frame_aabb(_assembly.world_aabb())
	_status.text = "Added %s - %s" % [gname, _assembly.last_message]
	_update_status()


func _load_all() -> void:
	var paths := _all_mesh_paths_in_list()
	if paths.is_empty():
		_status.text = "No mesh files in this folder."
		return
	await _load_paths(paths)


func _load_paths(paths: PackedStringArray) -> void:
	_status.text = "Loading..."
	await get_tree().process_frame
	var start_n := _assembly.parts.size()
	_assembly.load_paths(paths, false)
	if _assembly.keep_shared_origin and _assembly.parts.size() > start_n:
		var gname := "Group %s" % _assembly._next_link_id
		_assembly.create_link_group_from_index(start_n, gname)
	_refresh_parts_list()
	if not _xr.xr_active:
		_camera.frame_aabb(_assembly.world_aabb())
	_status.text = _assembly.last_message
	_update_status()


func _on_scale_slider(value: float) -> void:
	if _updating_ui:
		return
	_assembly.set_size_percent(value)


func _fill_light_options() -> void:
	_updating_ui = true
	_light_option.clear()
	for label in _stage.condition_labels():
		_light_option.add_item(label)
	_light_option.select(clampi(_stage.condition_index, 0, _light_option.item_count - 1))
	_updating_ui = false


func _on_env_radio(pressed: bool, index: int) -> void:
	if _updating_ui or not pressed:
		return
	_stage.set_environment(index)
	_fill_light_options()
	_show_splat_section(_stage.is_splat())
	_save_settings()


func _show_splat_section(show: bool) -> void:
	if _splat_section:
		_splat_section.visible = show
	if show:
		if _splat_folder.is_empty():
			_splat_folder = SplatLoader.app_dir()
		_scan_splat_folder()
	_refresh_splat_label()


func _sync_env_radios() -> void:
	var env_index := EnvironmentStage.ENV_IDS.find(_stage.current_id)
	if env_index < 0:
		env_index = 0
	_updating_ui = true
	if env_index < _env_radios.size():
		_env_radios[env_index].button_pressed = true
	_updating_ui = false
	_show_splat_section(_stage.is_splat())


func _scan_splat_folder() -> void:
	if _splat_list == null:
		return
	_splat_list.clear()
	var root := SplatLoader.app_dir()
	if _splat_folder.is_empty() or not _splat_folder.begins_with(root):
		_splat_folder = root
	if not DirAccess.dir_exists_absolute(_splat_folder):
		DirAccess.make_dir_recursive_absolute(_splat_folder)
	if _splat_folder_label:
		var rel := _splat_folder.trim_prefix(root)
		if rel.begins_with("/"):
			rel = rel.substr(1)
		_splat_folder_label.text = "App folder: splats" + (("/" + rel) if rel != "" else "")
	var dir := DirAccess.open(_splat_folder)
	if dir == null:
		_splat_label.text = "Cannot open the app splats folder."
		return
	dir.list_dir_begin()
	var dirs: PackedStringArray = []
	var files: PackedStringArray = []
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := _splat_folder.path_join(name)
		if dir.current_is_dir():
			dirs.append(full)
		elif SplatLoader.is_splat_file(full) or SplatLoader.may_be_gaussian_mesh(full):
			files.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	dirs.sort()
	files.sort()
	for p in dirs:
		_splat_list.add_item("[dir] " + p.get_file())
		_splat_list.set_item_metadata(_splat_list.item_count - 1, p)
	for p in files:
		_splat_list.add_item(p.get_file())
		_splat_list.set_item_metadata(_splat_list.item_count - 1, p)
	if files.is_empty() and dirs.is_empty():
		_splat_label.text = "Empty â€” copy captures into the app splats folder."
	else:
		_refresh_splat_label()


func _splat_go_up() -> void:
	var root := SplatLoader.app_dir()
	var parent := _splat_folder.get_base_dir()
	if parent.begins_with(root) or parent == root:
		_splat_folder = parent if parent.begins_with(root) else root
		_scan_splat_folder()


func _on_splat_activated(index: int) -> void:
	await _open_or_load_splat(index)


func _on_splat_clicked(index: int, _at: Vector2, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT:
		return
	var path := str(_splat_list.get_item_metadata(index))
	if DirAccess.dir_exists_absolute(path):
		_splat_folder = path
		_scan_splat_folder()


func _open_or_load_splat(index: int) -> void:
	var path := str(_splat_list.get_item_metadata(index))
	if DirAccess.dir_exists_absolute(path):
		_splat_folder = path
		_scan_splat_folder()
		return
	await _load_splat_path(path)


func _load_selected_splat_file() -> void:
	if _splat_list == null:
		return
	var selected := _splat_list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select a splat in the app splats folder."
		return
	await _open_or_load_splat(selected[0])


func _load_splat_path(path: String) -> void:
	_status.text = "Loading splat..."
	await get_tree().process_frame
	var result: Dictionary = _stage.load_splat(path)
	_sync_env_radios()
	_fill_light_options()
	_refresh_splat_label()
	_status.text = str(result.get("message", _stage.splat_status()))
	_save_settings()


func _refresh_splat_label() -> void:
	if _splat_label == null:
		return
	if _stage.has_splat():
		_splat_label.text = "Loaded: %s" % _stage.splat_path().get_file()
	elif _stage.is_splat():
		_splat_label.text = "No splat loaded yet."
	else:
		_splat_label.text = "Splat: none"


func _on_light_selected(index: int) -> void:
	if _updating_ui or index < 0:
		return
	_stage.set_condition(index)
	_save_settings()


func _on_dimmer(value: float) -> void:
	if _updating_ui:
		return
	_dimmer_label.text = "Light %.2fx" % value
	_stage.set_dimmer(value)
	_save_settings()


func _on_assembly_changed() -> void:
	_update_status()


func _on_stage_changed() -> void:
	_sync_passthrough()
	if _splat_section:
		_splat_section.visible = _stage.is_splat()
	_refresh_splat_label()
	if _stage.is_splat():
		var msg := _stage.splat_status()
		if msg != "":
			_status.text = msg


func _sync_passthrough() -> void:
	if _xr == null:
		return
	var result: Dictionary = _xr.set_passthrough(_stage.is_passthrough())
	var msg := str(result.get("message", ""))
	if msg != "":
		_status.text = msg


func _update_status() -> void:
	_updating_ui = true
	_scale_slider.value = _assembly.size_percent
	_scale_label.text = "Size %.0f%%" % _assembly.size_percent
	_updating_ui = false
	if _assembly.parts.is_empty():
		_meta.text = "glTF, GLB, OBJ, STL, FBX"
		return
	var size: Vector3 = _assembly.size_meters()
	_meta.text = "%s parts  Â·  %s tris  Â·  %.2f Ã— %.2f Ã— %.2f m" % [
		_assembly.parts.size(),
		ModelAssembly._format_int(_assembly.last_triangles),
		size.x, size.y, size.z
	]
	if not _assembly.last_message.is_empty() and not _xr.xr_active:
		_status.text = _assembly.last_message


func _set_vr(enabled: bool) -> void:
	if enabled:
		if not _xr.start_session():
			return
	else:
		_xr.stop_session()


func _raise_vr_board() -> void:
	if _xr:
		_xr.raise_board()


func _on_xr_started() -> void:
	_apply_ui_mode(true)
	_camera.set_enabled(false)
	if _desktop_host:
		_desktop_host.visible = false
	_ui.visible = true
	if _xr.board:
		_xr.board.use_viewport(_ui_viewport)
		_xr.board.visible = true
		if _xr.headset_camera():
			_xr.board.place_in_front_of(_xr.headset_camera())
	_vr_button.text = "Exit VR"
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_xr_stopped() -> void:
	_apply_ui_mode(false)
	if _xr.board:
		_xr.board.visible = false
	var root_vp := get_tree().root
	root_vp.use_xr = false
	root_vp.transparent_bg = false
	root_vp.vrs_mode = Viewport.VRS_DISABLED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_camera.set_enabled(true)
	_camera.current = true
	_ui.visible = true
	if _desktop_host:
		_desktop_host.visible = true
	_vr_button.text = "Enter VR"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _assembly.parts.is_empty():
		_camera._apply()
	else:
		_camera.frame_aabb(_assembly.world_aabb())


func _on_xr_status(text: String) -> void:
	_status.text = text


func _has_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_args() or flag in OS.get_cmdline_user_args()


func _is_smoke_run() -> bool:
	return _has_flag("--smoke") or OS.get_environment("VR_VIEWER_SMOKE") == "1"


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_folder = str(cfg.get_value("session", "folder", ""))
	var env_id := str(cfg.get_value("session", "environment", "studio"))
	var cond := int(cfg.get_value("session", "lighting", 0))
	var dim := float(cfg.get_value("session", "dimmer", 1.0))
	var env_index := EnvironmentStage.ENV_IDS.find(env_id)
	if env_index < 0:
		env_index = 0
	_updating_ui = true
	_dimmer_slider.value = dim
	_dimmer_label.text = "Light %.2fx" % dim
	_updating_ui = false
	_stage.apply(env_id, cond, dim)
	_fill_light_options()
	var splat_path := str(cfg.get_value("session", "splat_path", ""))
	if env_id == "splat" and splat_path != "" and not _is_smoke_run():
		_stage.load_splat(splat_path)
	_sync_env_radios()
	_library_mode = bool(cfg.get_value("session", "library_mode", false))
	if _library_check:
		_library_check.set_pressed_no_signal(_library_mode)
	if _tag_filter:
		_tag_filter.visible = _library_mode


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "folder", _folder)
	cfg.set_value("session", "environment", _stage.current_id)
	cfg.set_value("session", "lighting", _stage.condition_index)
	cfg.set_value("session", "dimmer", _stage.dimmer)
	cfg.set_value("session", "splat_path", _stage.splat_path())
	cfg.set_value("session", "library_mode", _library_mode)
	cfg.save(SETTINGS_PATH)


func _refresh_scene_list() -> void:
	if _scene_list == null:
		return
	_scene_list.clear()
	for n in SceneStore.list_scenes():
		_scene_list.add_item(n)


func _save_scene() -> void:
	var n := _scene_name_edit.text.strip_edges()
	if n.is_empty():
		_status.text = "Enter a scene name."
		return
	var payload: Dictionary = _assembly.dump_state()
	payload["environment"] = _stage.current_id
	payload["lighting"] = _stage.condition_index
	payload["dimmer"] = _stage.dimmer
	payload["splat_path"] = _stage.splat_path()
	var ok := SceneStore.save_scene(n, payload)
	_status.text = "Saved scene '%s'." % n if ok else "Could not save scene."
	_refresh_scene_list()


func _load_scene() -> void:
	var n := _scene_name_edit.text.strip_edges()
	if n.is_empty() and _scene_list.get_selected_items().size() > 0:
		n = _scene_list.get_item_text(_scene_list.get_selected_items()[0])
	var data := SceneStore.load_scene(n)
	if data.is_empty():
		_status.text = "Scene not found."
		return
	_assembly.keep_shared_origin = bool(data.get("keep_origin", false))
	_origin_check.button_pressed = _assembly.keep_shared_origin
	var records: Array = data.get("parts", [])
	var paths := PackedStringArray()
	for rec in records:
		paths.append(str(rec.get("path", "")))
	var has_pose := bool(data.get("has_assembly_pose", false))
	var has_world := false
	for rec in records:
		if rec.has("global_position"):
			has_world = true
			break
	_assembly.load_paths(paths, true, not has_pose and not has_world)
	if has_pose:
		_assembly.restore_pose(data)
	_assembly.apply_part_transforms(records)
	_assembly.spawn_transform = _assembly.transform
	var env_id := str(data.get("environment", "studio"))
	_stage.apply(env_id, int(data.get("lighting", 0)), float(data.get("dimmer", 1.0)))
	var splat_path := str(data.get("splat_path", ""))
	if env_id == "splat" and splat_path != "":
		_stage.load_splat(splat_path)
	_updating_ui = true
	_dimmer_slider.value = _stage.dimmer
	_updating_ui = false
	_fill_light_options()
	_sync_env_radios()
	if not _xr.xr_active:
		_camera.frame_aabb(_assembly.world_aabb())
	_status.text = "Loaded scene '%s'." % n
	_update_status()


func _run_regression() -> int:
	var fails: PackedStringArray = []
	_library_mode = false
	if _library_check:
		_library_check.set_pressed_no_signal(false)
	if _tag_filter:
		_tag_filter.visible = false
	_stage.apply("studio", 0, 1.0)
	if _ui_viewport == null or _side_panel == null:
		fails.append("ui viewport/panel missing")
	elif _side_panel.get_parent() != _ui_viewport:
		fails.append("panel not parented to UI viewport")
	if _side_panel.get_child_count() < 1:
		fails.append("side panel has no children")
	var names := PackedStringArray()
	_collect_button_names(_side_panel, names)
	if not "Add selected" in names:
		fails.append("Add selected button missing")
	if not "Library (model-tags)" in names:
		fails.append("Library (model-tags) toggle missing")
	var issa_root := "C:/Users/zacha/Downloads/Issa"
	if DirAccess.dir_exists_absolute(issa_root):
		var adapter := ModelTagsLibrary.new()
		adapter.set_root(issa_root)
		var packs: Array[LibraryPack] = adapter.list_packs()
		var found_issa := false
		for pack in packs:
			if pack.pack_id == "issa":
				found_issa = true
				if adapter.resolve_meshes(pack).is_empty():
					fails.append("issa pack resolved no meshes")
				break
		if not found_issa:
			fails.append("model-tags scan did not find pack_id issa")
		var tagged: Array[LibraryPack] = TagIndex.filter_by_tag(packs, "ball-gag")
		var tag_hit := false
		for pack in tagged:
			if pack.pack_id == "issa":
				tag_hit = true
				break
		if not tag_hit:
			fails.append("tag filter ball-gag did not return issa")
	else:
		print("LIBRARY_SMOKE_SKIP no Issa folder at %s" % issa_root)
	if "Raise VR board" in names:
		fails.append("Raise VR board button should be gone")
	_set_folder(ProjectSettings.globalize_path("res://samples/assembly"))
	await get_tree().process_frame
	if _file_row_count() < 2:
		fails.append("file browser did not list assembly meshes")
	if _file_list.columns != 2:
		fails.append("file list is missing the extension column")
	var saw_stl_ext := false
	var assembly_root := _file_list.get_root()
	if assembly_root:
		var row := assembly_root.get_first_child()
		while row:
			if row.get_text(1) == "STL":
				saw_stl_ext = true
			row = row.get_next()
	if not saw_stl_ext:
		fails.append("file list did not show STL in the Ext column")
	await _load_all()
	if _assembly.parts.size() < 2:
		fails.append("initial load failed: %s" % _assembly.last_message)
	if _xr.board == null:
		fails.append("VR board missing")
	elif _xr.board.viewport != _ui_viewport:
		fails.append("VR board not wired to UI viewport")
	if VrBoard.BOARD_SIZE.x < 1.4:
		fails.append("VR board is not wide: %s" % VrBoard.BOARD_SIZE)
	if not "Mix color" in names:
		fails.append("Mix color button missing")
	if not "Close color" in names:
		fails.append("Close color button missing")
	if not "Clay" in names:
		fails.append("color presets missing")
	_on_xr_started()
	await get_tree().process_frame
	if _side_panel.get_parent() != _ui_viewport:
		fails.append("panel left UI viewport during VR")
	if _ui_viewport.size.x < 1200 or _ui_viewport.size.y < 1200:
		fails.append("VR dashboard viewport not widened: %s" % _ui_viewport.size)
	if _ui_viewport.size.y < 100:
		fails.append("UI viewport size collapsed in VR")
	if _ui_viewport.get_texture() == null:
		fails.append("UI viewport has no texture")
	if _tabs == null or _tabs.get_tab_count() < 4:
		fails.append("VR tab dashboard missing tabs")
	_on_xr_stopped()
	await get_tree().process_frame
	if _ui_viewport.size.x > 700:
		fails.append("desktop UI stayed at VR width: %s" % _ui_viewport.size)
	if _desktop_host == null or not _desktop_host.visible:
		fails.append("desktop UI hidden after Exit VR")
	if not _camera.current:
		fails.append("desktop camera not current after Exit VR")
	if _side_panel.get_parent() != _ui_viewport:
		fails.append("panel not in UI viewport after Exit VR")
	_assembly.clear()
	await _load_all()
	if _assembly.parts.size() < 2:
		fails.append("load after Exit VR failed: %s" % _assembly.last_message)
	var samples := ProjectSettings.globalize_path("res://samples")
	_assembly.clear()
	_assembly.keep_shared_origin = false
	_assembly.load_paths(PackedStringArray([samples.path_join("assembly")]), false)
	if _assembly.parts.size() != 0:
		fails.append("directory was imported as a mesh")
	_assembly.clear()
	_assembly.keep_shared_origin = false
	_assembly.load_paths(PackedStringArray([samples.path_join("cube_meters.obj")]), true)
	var first_pose := Transform3D.IDENTITY
	var x0 := 0.0
	if _assembly.parts.size() == 1:
		first_pose = _assembly.parts[0].global_transform
		x0 = first_pose.origin.x
	_assembly.load_paths(PackedStringArray([samples.path_join("assembly/base.stl")]), false)
	if _assembly.parts.size() != 2:
		fails.append("could not add a second model from another file")
	else:
		if _assembly.parts[0].global_position.distance_to(first_pose.origin) > 0.08:
			fails.append("adding a second model moved the first")
		var x1 := _assembly.parts[1].global_position.x
		if absf(x1 - x0) < 0.05:
			fails.append("second model overlapped the first")
	_assembly.set_size_percent(200.0)
	var kept := _assembly.size_percent
	_assembly.return_to_origin()
	if absf(_assembly.size_percent - kept) > 1.0:
		fails.append("return to origin changed scale")
	_assembly.clear()
	_assembly.keep_shared_origin = true
	var base := samples.path_join("assembly/base.stl")
	var post := samples.path_join("assembly/post.stl")
	_assembly.load_paths(PackedStringArray([base]), true)
	_assembly.load_paths(PackedStringArray([post]), false)
	if _assembly.parts.size() != 2:
		fails.append("shared-origin second part did not load")
	else:
		var combined := _assembly.size_meters()
		if combined.y < 0.05 or combined.y > 4.0:
			fails.append("combined assembly not fitted in play area: %s" % combined)
	_assembly.clear()
	_assembly.keep_shared_origin = false
	var color_obj := samples.path_join("color_cube.obj")
	_set_folder(samples)
	await get_tree().process_frame
	var saw_obj_ext := false
	var files_root := _file_list.get_root()
	if files_root:
		var row := files_root.get_first_child()
		while row:
			if str(row.get_metadata(0)).get_file() == "color_cube.obj" and row.get_text(1) == "OBJ":
				saw_obj_ext = true
			row = row.get_next()
	if not saw_obj_ext:
		fails.append("file list did not show color_cube.obj as OBJ")
	_assembly.load_paths(PackedStringArray([color_obj]), true)
	if _assembly.parts.is_empty():
		fails.append("colored OBJ failed to load")
	elif not bool(_assembly.parts[0].get_meta("native_color", false)):
		fails.append("colored OBJ lost its materials")
	elif not _part_has_loaded_color(_assembly.parts[0]):
		fails.append("colored OBJ did not keep MTL colours")
	_assembly.clear()
	_assembly.keep_shared_origin = false
	_assembly.load_paths(PackedStringArray([samples.path_join("cube_meters.obj")]), true)
	_assembly.load_paths(PackedStringArray([samples.path_join("assembly/base.stl")]), false)
	if _assembly.parts.size() == 2:
		_assembly.parts[0].global_position = Vector3(0.85, 0.0, -2.15)
		_assembly.parts[1].global_position = Vector3(-0.72, 0.0, -0.95)
		_assembly.parts[1].scale *= 1.6
		var saved_a := _assembly.parts[0].global_position
		var saved_b := _assembly.parts[1].global_position
		var saved_s := _assembly.parts[1].global_transform.basis.get_scale().x
		_scene_name_edit.text = "_reg_pose"
		_save_scene()
		_assembly.clear()
		_load_scene()
		if _assembly.parts.size() != 2:
			fails.append("scene reload lost models")
		else:
			if _assembly.parts[0].global_position.distance_to(saved_a) > 0.1:
				fails.append("scene did not restore first model position")
			if _assembly.parts[1].global_position.distance_to(saved_b) > 0.1:
				fails.append("scene did not restore second model position")
			if absf(_assembly.parts[1].global_transform.basis.get_scale().x - saved_s) > 0.12:
				fails.append("scene did not restore model scale")
		SceneStore.delete_scene("_reg_pose")
	else:
		fails.append("could not set up scene pose regression")
	if not "Gaussian splat" in EnvironmentStage.ENV_LABELS:
		fails.append("gaussian splat environment missing")
	if not "Gaussian splat" in names:
		fails.append("gaussian splat radio missing")
	if not "Load splat" in names:
		fails.append("Load splat button missing")
	if "Use selected splat" in names:
		fails.append("old Use selected splat button should be gone")
	var splat_index := EnvironmentStage.ENV_IDS.find("splat")
	_stage.set_environment(splat_index)
	_sync_env_radios()
	await get_tree().process_frame
	if _splat_section == null or not _splat_section.visible:
		fails.append("splat section did not appear when Gaussian splat was selected")
	var splat_dir := SplatLoader.app_dir()
	if not splat_dir.replace("\\", "/").ends_with("/splats"):
		fails.append("splat directory is not inside the app folder: %s" % splat_dir)
	var listed_splat := false
	for i in _splat_list.item_count:
		if str(_splat_list.get_item_metadata(i)).get_file() == "demo.sog":
			listed_splat = true
			break
	if not listed_splat:
		fails.append("app splats folder did not list demo.sog")
	var demo_splat := splat_dir.path_join("demo.sog")
	if FileAccess.file_exists(demo_splat):
		var loaded: Dictionary = _stage.load_splat(demo_splat)
		if not bool(loaded.get("ok", false)):
			fails.append("demo splat failed: %s" % str(loaded.get("message", "")))
		elif not _stage.has_splat():
			fails.append("splat node missing after load")
		if _stage.current_id != "splat":
			fails.append("loading a splat did not stay on the splat environment")
	_stage.apply("studio", 0, 1.0)
	if _stage.current_id != "studio":
		fails.append("could not leave splat environment back to studio")
	if fails.is_empty():
		print("REGRESSION_OK parts=%s viewport=%s buttons=%s" % [_assembly.parts.size(), _ui_viewport.size, names.size()])
		return 0
	for f in fails:
		print("REGRESSION_FAIL ", f)
	return 1


func _part_has_loaded_color(node: Node) -> bool:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i)
				if src is BaseMaterial3D:
					var mat := src as BaseMaterial3D
					if mat.albedo_texture != null:
						return true
					var c := mat.albedo_color
					if absf(c.r - c.g) > 0.08 or absf(c.g - c.b) > 0.08:
						return true
	for child in node.get_children():
		if _part_has_loaded_color(child):
			return true
	return false


func _collect_button_names(node: Node, names: PackedStringArray) -> void:
	if node is Button:
		names.append((node as Button).text)
	for child in node.get_children():
		_collect_button_names(child, names)


func _delete_scene() -> void:
	var n := _scene_name_edit.text.strip_edges()
	if n.is_empty() and _scene_list.get_selected_items().size() > 0:
		n = _scene_list.get_item_text(_scene_list.get_selected_items()[0])
	if n.is_empty():
		return
	SceneStore.delete_scene(n)
	_refresh_scene_list()
	_status.text = "Deleted scene '%s'." % n
