class_name UiTheme
extends RefCounted
## Shared Theme + palette, ported from styles.css so the Godot menus/HUD
## visually match the HTML5 build's dark/gold medieval look.

const BG := Color("15130f")
const STONE := Color("211d17")
const STONE2 := Color("2c261d")
const INK := Color("ece3cf")
const MUTED := Color("a99f86")
const GOLD := Color("d9b25a")
const GOLD_BRIGHT := Color("f0c869")
const HP_COLOR := Color("c0473f")
const XP_COLOR := Color("5aa9d9")
const BORDER := Color("463b2a")
const BLOOD := Color("b5413a")
const DARK_TEXT := Color("1a1308")

static func panel_style(margin: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = STONE2
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(margin)
	return s

static func button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16

	var btn := button_style(STONE2, BORDER)
	var btn_hover := button_style(STONE2.lightened(0.1), BORDER)
	var btn_pressed := button_style(STONE, BORDER)
	var btn_disabled := button_style(STONE.darkened(0.3), BORDER.darkened(0.3))

	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_hover)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_font_size("font_size", "Button", 16)

	# Primary CTA button (New Run / Begin / Resume) — gold, dark text.
	var primary := button_style(GOLD_BRIGHT, Color("8a6a2c"))
	var primary_hover := button_style(GOLD_BRIGHT.lightened(0.08), Color("8a6a2c"))
	var primary_pressed := button_style(GOLD, Color("8a6a2c"))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", primary)
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	theme.set_stylebox("pressed", "PrimaryButton", primary_pressed)
	theme.set_stylebox("focus", "PrimaryButton", primary_hover)
	theme.set_stylebox("disabled", "PrimaryButton", btn_disabled)
	theme.set_color("font_color", "PrimaryButton", DARK_TEXT)
	theme.set_color("font_hover_color", "PrimaryButton", DARK_TEXT)
	theme.set_color("font_pressed_color", "PrimaryButton", DARK_TEXT)
	theme.set_color("font_disabled_color", "PrimaryButton", MUTED)

	theme.set_color("font_color", "Label", INK)
	theme.set_font_size("font_size", "Label", 15)

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = STONE
	slider_bg.set_corner_radius_all(6)
	slider_bg.content_margin_top = 6; slider_bg.content_margin_bottom = 6
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = GOLD
	slider_fill.set_corner_radius_all(6)
	slider_fill.content_margin_top = 6; slider_fill.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	return theme

# Label helper: bold-ish title text (large, gold-bright, matches CSS .big).
static func style_title(lbl: Label, size: int = 40) -> void:
	lbl.add_theme_color_override("font_color", GOLD_BRIGHT)
	lbl.add_theme_font_size_override("font_size", size)

static func style_muted(lbl: Label, size: int = 13) -> void:
	lbl.add_theme_color_override("font_color", MUTED)
	lbl.add_theme_font_size_override("font_size", size)

static func style_heading(lbl: Label, color: Color = GOLD, size: int = 20) -> void:
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)

# Per-instance accent-bordered panel style for a Button (class cards / chips).
static func accent_button_style(base: Button, accent: Color, selected: bool) -> void:
	var normal := button_style(STONE2, accent if selected else BORDER)
	if selected:
		normal.set_border_width_all(2)
	var hover := button_style(STONE2.lightened(0.08), accent)
	base.add_theme_stylebox_override("normal", normal)
	base.add_theme_stylebox_override("hover", hover)
	base.add_theme_stylebox_override("pressed", normal)
	base.add_theme_stylebox_override("focus", hover)
