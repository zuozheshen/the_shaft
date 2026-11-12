extends RefCounted
## 只为三块终端屏提供颜色、字体角色与方角样式。

const DESK := Color("#241b16")
const SURFACE := Color("#30251c")
const EDGE := Color("#806243")
const AMBER := Color("#e1ba7d")
const MUTED := Color("#bc9d77")
const ACTIVE := Color("#c79a5b")
const INACTIVE := Color("#604831")
const PAPER := Color("#d9c6a1")
const INK := Color("#35271d")
const HOVER := Color("#ebcf9a")
const PICKED := Color("#805027")
const LIGHT := Color("#fff1cf")

static func font(names: PackedStringArray) -> SystemFont:
	var result := SystemFont.new()
	result.font_names = names
	return result

static func box(fill: Color, border: Color = EDGE, width: int = 1,
		x: float = 8.0, y: float = 4.0) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(width)
	result.content_margin_left = x
	result.content_margin_right = x
	result.content_margin_top = y
	result.content_margin_bottom = y
	return result

static func make_theme(font_size: int) -> Theme:
	var result := Theme.new()
	result.default_font = font(["Noto Sans SC", "Microsoft YaHei UI", "Microsoft YaHei"])
	result.default_font_size = font_size
	result.set_color("font_color", "Label", AMBER)
	result.set_stylebox("separator", "HSeparator", box(EDGE, EDGE, 0, 0, 0.5))
	result.set_stylebox("panel", "PanelContainer", box(SURFACE))
	result.set_stylebox("scroll", "VScrollBar", box(DESK, EDGE, 0, 4, 4))
	result.set_stylebox("grabber", "VScrollBar", box(EDGE, EDGE, 0, 4, 4))
	result.set_stylebox("grabber_highlight", "VScrollBar", box(ACTIVE, EDGE, 0, 4, 4))
	result.set_stylebox("grabber_pressed", "VScrollBar", box(AMBER, EDGE, 0, 4, 4))
	result.set_stylebox("normal", "Button", box(SURFACE))
	result.set_stylebox("hover", "Button", box(HOVER))
	result.set_stylebox("pressed", "Button", box(ACTIVE))
	result.set_stylebox("hover_pressed", "Button", box(HOVER))
	result.set_stylebox("disabled", "Button", box(DESK, EDGE))
	var focus := box(Color.TRANSPARENT, AMBER, 2)
	result.set_stylebox("focus", "Button", focus)
	result.set_stylebox("focus", "ScrollContainer", box(Color.TRANSPARENT, EDGE, 1))
	result.set_color("font_color", "Button", AMBER)
	result.set_color("font_focus_color", "Button", AMBER)
	result.set_color("font_disabled_color", "Button", MUTED)
	for state in ["hover", "pressed", "hover_pressed"]:
		result.set_color("font_%s_color" % state, "Button", INK)
	return result
