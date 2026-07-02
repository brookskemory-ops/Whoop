class_name Ui
extends RefCounted
## Shared UI layout scaffold + styled component library. Replaces the old
## pattern of hand-building a CanvasLayer + dim ColorRect + a VBox pinned at
## hardcoded Vector2 coordinates on every screen. Everything here composes
## Godot Control containers with anchors so layout is responsive and
## consistent, and reuses UiTheme (palette/fonts/Theme) + the assets/ui frames.

# ── Design tokens ─────────────────────────────────────────────────────────────
const SP_S := 6
const SP_M := 12
const SP_L := 20
const SP_XL := 32

const TITLE := 46
const H1 := 26
const H2 := 18
const BODY := 15
const SMALL := 12

static var _vignette: GradientTexture2D

# Radial vignette (transparent center → dark edges) for menu/overlay depth.
static func vignette_tex() -> GradientTexture2D:
	if _vignette == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0.02, 0.015, 0.01, 0.75)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 256; t.height = 256
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_vignette = t
	return _vignette

## Builds a full-screen overlay: CanvasLayer → dusk backdrop + vignette + dark
## wash → an anchored MarginContainer carrying the theme → a centered content
## column. Returns {"layer": CanvasLayer, "column": VBoxContainer}. `centered`
## vertically centers short content (dialogs); otherwise content is top-aligned
## and scrolls (long menus). `pausable` keeps the layer processing while paused.
static func overlay(host: Node, theme: Theme, pausable: bool = false, centered: bool = false) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 10
	if pausable:
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)

	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/title_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.5, 0.48, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var wash := ColorRect.new()
	wash.color = Color(0.05, 0.045, 0.035, 0.76)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(wash)

	var vig := TextureRect.new()
	vig.texture = vignette_tex()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vig)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = theme   # children inherit; no per-control theme needed
	margin.add_theme_constant_override("margin_left", SP_L)
	margin.add_theme_constant_override("margin_right", SP_L)
	margin.add_theme_constant_override("margin_top", SP_XL)
	margin.add_theme_constant_override("margin_bottom", SP_L)
	layer.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", SP_M)

	if centered:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_child(center)
		center.add_child(column)
	else:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		margin.add_child(scroll)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(column)

	return {"layer": layer, "column": column}

# ── Components ────────────────────────────────────────────────────────────────

## A framed content panel. `ornate` wraps the content in the gold filigree
## panel_frame (for headline dialogs); otherwise a simple dark stone fill (for
## list cards). Returns {"panel": Control, "column": VBoxContainer} — add
## content to `column`.
static func panel(ornate: bool = false) -> Dictionary:
	var fill := PanelContainer.new()
	fill.add_theme_stylebox_override("panel", _fill_style())
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", SP_S)
	fill.add_child(column)
	if not ornate:
		return {"panel": fill, "column": column}
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _frame_style())
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(fill)
	return {"panel": frame, "column": column}

static func _fill_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UiTheme.STONE.r, UiTheme.STONE.g, UiTheme.STONE.b, 0.9)
	s.border_color = UiTheme.BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(SP_M)
	return s

static func _frame_style() -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load("res://assets/ui/panel_frame.png")
	s.set_texture_margin_all(70)
	# Content (the inner fill) sits inside the ornate border.
	s.content_margin_left = 22; s.content_margin_right = 22
	s.content_margin_top = 22; s.content_margin_bottom = 22
	return s

## Cinzel screen/dialog title (the caps accent). Everything below title level
## uses the mixed-case body font.
static func header(text: String, size: int = H1, color: Color = UiTheme.GOLD_BRIGHT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", size)
	return l

## Body/flavor label (EB Garamond, muted).
static func body(text: String, size: int = BODY, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_muted(l, size)
	return l

## Thin gold divider rule.
static func divider() -> Control:
	var r := ColorRect.new()
	r.color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.35)
	r.custom_minimum_size = Vector2(0, 2)
	return r

static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

## Themed menu button with optional left icon. Width expands to its column.
static func button(text: String, icon_path: String = "", primary: bool = false, min_h: int = 62) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true   # never let a label spill past the frame
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		b.theme_type_variation = "PrimaryButton"
	if icon_path != "" and ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
	return b

## A clickable framed row with a left name + optional detail line and a
## right-aligned value (e.g. shop upgrades: "Vigor" / "Lv 0/8 — +0 max HP" /
## "40 gold"). The inner HBox is inset past the ornate frame caps so text never
## collides with the border, and labels clip rather than overflow. Caller wires
## `.pressed` and adds the returned Button to a column.
static func stat_row(name: String, detail: String, value: String, enabled: bool = true) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 66)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 42; row.offset_right = -42   # clear the ornate side caps
	row.offset_top = 6; row.offset_bottom = 6
	row.add_theme_constant_override("separation", 10)
	b.add_child(row)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.clip_text = true
	UiTheme.style_heading(name_lbl, UiTheme.INK, 15)
	col.add_child(name_lbl)
	if detail != "":
		var det := Label.new()
		det.text = detail
		det.clip_text = true
		UiTheme.style_muted(det, 12)
		col.add_child(det)
	var val := Label.new()
	val.text = value
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.style_heading(val, UiTheme.GOLD_BRIGHT if enabled else UiTheme.MUTED, 14)
	row.add_child(val)
	return b

## A gold-framed value bar (HP / XP / boss). Returns {"root": Control,
## "fill": ColorRect}; drive it with `dict["fill"].size.x = width * frac`
## (the fill is manually sized, matching the existing _update_hud pattern).
static func framed_bar(fill_color: Color, w: float, h: float) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(w, h)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.6)
	s.border_color = UiTheme.GOLD
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	bg.add_theme_stylebox_override("panel", s)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(w - 4, h - 4)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	return {"root": root, "fill": fill}
