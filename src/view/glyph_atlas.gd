class_name GlyphAtlas
extends Node

## 开局一次性把每种单位的"色块 + 一个字"画成贴图（设计文档 9.5）。
## 用一个只渲染一次的 SubViewport 画好，再切成每种单位一张贴图。渲染完成前先用纯色圆片占位。

signal textures_ready

const CELL: int = 64

var textures: Dictionary = {}
var placeholder: Texture2D


func _init() -> void:
	placeholder = _make_disc()


func texture_for(d: UnitDef) -> Texture2D:
	return textures.get(d, placeholder)


func build(defs: Array[UnitDef]) -> void:
	if defs.is_empty():
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * defs.size(), CELL)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := GlyphPainter.new()
	painter.defs = defs
	painter.cell = CELL
	vp.add_child(painter)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	for k in defs.size():
		var sub: Image = img.get_region(Rect2i(k * CELL, 0, CELL, CELL))
		textures[defs[k]] = ImageTexture.create_from_image(sub)
	vp.queue_free()
	textures_ready.emit()


static func _make_disc() -> Texture2D:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	var r: float = CELL * 0.5 - 1.0
	var center := Vector2(CELL * 0.5, CELL * 0.5)
	for y in CELL:
		for x in CELL:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
