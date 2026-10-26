class_name GlyphPainter
extends Node2D

## 在 SubViewport 里把每种单位画成"色块 + 一个字"，由 GlyphAtlas 截下来切成贴图。
## 格子大小通过 cell 传进来，不反向引用 GlyphAtlas。

var defs: Array[UnitDef] = []
var cell: int = 64
## 字体必须由节点持有：_draw 只是记录绘制命令，真正渲染在之后，局部变量的字体那时已被释放。
var font: SystemFont = SystemFont.new()


func _init() -> void:
	font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Microsoft YaHei", "Noto Sans CJK SC"])


func _draw() -> void:
	for k in defs.size():
		var d: UnitDef = defs[k]
		var center := Vector2(k * cell + cell * 0.5, cell * 0.5)
		draw_circle(center, cell * 0.47, d.color)
		draw_arc(center, cell * 0.44, 0.0, TAU, 48, d.color.darkened(0.45), 3.0, true)
		var text_color: Color = Color("fff6e6") if d.color.get_luminance() < 0.6 else Color("231f1b")
		var size: int = 38
		var ascent: float = font.get_ascent(size)
		var descent: float = font.get_descent(size)
		var baseline: float = cell * 0.5 + (ascent - descent) * 0.5
		draw_string(font, Vector2(k * cell, baseline), d.glyph, HORIZONTAL_ALIGNMENT_CENTER, cell, size, text_color)
