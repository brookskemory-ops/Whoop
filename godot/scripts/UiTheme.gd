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

# Medieval serif type: Cinzel (engraved Roman caps) for titles/headings/buttons,
# EB Garamond (old-style serif) for body text. Loaded lazily + cached.
static var _title_font: FontFile
static var _body_font: FontFile

static func title_font() -> FontFile:
	if _title_font == null:
		_title_font = load("res://assets/fonts/Cinzel.ttf")
	return _title_font

static func body_font() -> FontFile:
	if _body_font == null:
		_body_font = load("res://assets/fonts/EBGaramond.ttf")
	return _body_font

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

# 9-patch button built from the ornate stone+gold frame art. `mod` tints the
# whole texture per state (hover brighter, pressed/disabled darker).
static func button_tex(mod: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load("res://assets/ui/button_frame.png")
	# Source frame is 512x192 with thick borders; list buttons are short, so
	# keep wide side caps but small top/bottom margins or the 9-patch collapses.
	s.texture_margin_left = 60; s.texture_margin_right = 60
	s.texture_margin_top = 15; s.texture_margin_bottom = 15
	s.content_margin_left = 26; s.content_margin_right = 26
	s.content_margin_top = 7; s.content_margin_bottom = 7
	s.modulate_color = mod
	return s

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 16

	var btn := button_tex(Color(1, 1, 1))
	var btn_hover := button_tex(Color(1.18, 1.16, 1.05))
	var btn_pressed := button_tex(Color(0.82, 0.82, 0.82))
	var btn_disabled := button_tex(Color(0.55, 0.53, 0.5))

	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_hover)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_font("font", "Button", title_font())   # engraved-caps look on buttons
	theme.set_font_size("font_size", "Button", 17)

	# Primary CTA button (New Run / Begin / Resume) — same ornate frame with a
	# warm gold wash and bright-gold engraved text so it reads as the CTA.
	var primary := button_tex(Color(1.18, 1.05, 0.78))
	var primary_hover := button_tex(Color(1.32, 1.18, 0.9))
	var primary_pressed := button_tex(Color(1.02, 0.9, 0.66))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", primary)
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	theme.set_stylebox("pressed", "PrimaryButton", primary_pressed)
	theme.set_stylebox("focus", "PrimaryButton", primary_hover)
	theme.set_stylebox("disabled", "PrimaryButton", btn_disabled)
	theme.set_color("font_color", "PrimaryButton", GOLD_BRIGHT)
	theme.set_color("font_hover_color", "PrimaryButton", Color("fff0c0"))
	theme.set_color("font_pressed_color", "PrimaryButton", GOLD_BRIGHT)
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
	lbl.add_theme_font_override("font", title_font())
	lbl.add_theme_font_size_override("font_size", size)

static func style_muted(lbl: Label, size: int = 13) -> void:
	lbl.add_theme_color_override("font_color", MUTED)
	lbl.add_theme_font_override("font", body_font())
	lbl.add_theme_font_size_override("font_size", size)

static func style_heading(lbl: Label, color: Color = GOLD, size: int = 20) -> void:
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_override("font", title_font())
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
