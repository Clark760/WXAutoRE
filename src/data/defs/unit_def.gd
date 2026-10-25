class_name UnitDef
extends RefCounted

## 单位定义。M0 先在 src/dev/dev_scenarios.gd 里写死，M1 起从 mods/base/data/units 加载。

var id: String = ""
var name: String = ""
## 棋子上显示的那个字（设计文档 9.5）。
var glyph: String = ""
var color: Color = Color.WHITE
var is_hero: bool = false

var hp: float = 100.0
var atk: float = 10.0
var iat: float = 0.0
var def_ext: float = 0.0
var def_int: float = 0.0
var attack_interval: float = 1.0
var attack_range: int = 1
var move_interval: float = 0.5
var crit: float = 0.05

## 我方驻守时能离开部署格的最大距离（设计文档 6.5）。
var guard_radius: int = 3
## 敌方警戒半径；死士类为 0（设计文档 6.4）。
var alert_radius: int = 2
## 死士类：只有被挡住才交战。
var suicider: bool = false


static func make(p_id: String, p_name: String, p_glyph: String, p_color: Color, stats: Dictionary) -> UnitDef:
	var d := UnitDef.new()
	d.id = p_id
	d.name = p_name
	d.glyph = p_glyph
	d.color = p_color
	for key in stats:
		d.set(key, stats[key])
	return d
