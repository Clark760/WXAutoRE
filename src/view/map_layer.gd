class_name MapLayer
extends Node2D

## 战场地图层：所有格子画成六边形，画一次；调试叠加时额外画出我方防区。
## 需要的数值都通过 setup() 传进来，不反向引用 BattleView，避免某些 Godot 版本解析全局类时循环依赖。

## 按 BattleMap.CellType 的顺序：空地、墙、出生区、部署区、城门
const CELL_COLORS: Array[Color] = [
	Color("ece2cc"),
	Color("3b342c"),
	Color("e6cfc4"),
	Color("d6e2cf"),
	Color("a8322d"),
]
const GUARD_RING_COLOR: Color = Color(0.2, 0.5, 0.9, 0.25)

var overlay: bool = false

var _sim: BattleSim
var _pixel: PackedVector2Array = PackedVector2Array()
var _hex_size: float = 16.0
var _corners: PackedVector2Array = PackedVector2Array()


func setup(sim: BattleSim, pixel: PackedVector2Array, hex_size: float) -> void:
	_sim = sim
	_pixel = pixel
	_hex_size = hex_size
	_corners.resize(6)
	var r: float = hex_size * 0.96
	for k in 6:
		var a: float = deg_to_rad(60.0 * k - 30.0)
		_corners[k] = Vector2(cos(a), sin(a)) * r
	queue_redraw()


func _draw() -> void:
	if _sim == null:
		return
	var map: BattleMap = _sim.map
	var poly := PackedVector2Array()
	poly.resize(6)
	for c in map.cell_count:
		var p: Vector2 = _pixel[c]
		for k in 6:
			poly[k] = p + _corners[k]
		draw_colored_polygon(poly, CELL_COLORS[map.cell_type[c]])
	if not overlay:
		return
	# 调试：我方防区
	var st: BattleState = _sim.st
	var step: float = _hex_size * Hex.SQRT3
	for i in st.unit_count:
		if st.alive[i] == 1 and st.team[i] == BattleState.TEAM_ALLY:
			var radius: float = (st.guard_radius[i] + 0.5) * step
			draw_arc(_pixel[st.home[i]], radius, 0.0, TAU, 32, GUARD_RING_COLOR, 1.0)
