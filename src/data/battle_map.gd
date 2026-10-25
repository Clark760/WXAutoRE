class_name BattleMap
extends RefCounted

## 解析后的战场地图（设计文档 6.1）。
## 格子用整数下标表示；逻辑层只通过下标、轴向坐标和 Hex.distance 访问格子，看不到偏移坐标。

enum CellType { FLOOR, WALL, SPAWN, DEPLOY, GATE }

var width: int = 0
var height: int = 0
var cell_count: int = 0

var cell_type: PackedByteArray = PackedByteArray()
var cell_q: PackedInt32Array = PackedInt32Array()
var cell_r: PackedInt32Array = PackedInt32Array()

## cell * 6 + 方向 → 邻格下标；越界或墙为 -1。城门格保留（敌人能走），我方另看 walk_ally。
var neighbors: PackedInt32Array = PackedInt32Array()
## 敌人能站的格子：除墙以外全部。
var walk_enemy: PackedByteArray = PackedByteArray()
## 我方能站的格子：既不是墙也不是城门。
var walk_ally: PackedByteArray = PackedByteArray()

var gate_cells: PackedInt32Array = PackedInt32Array()
var spawn_cells: PackedInt32Array = PackedInt32Array()
var deploy_cells: PackedInt32Array = PackedInt32Array()
## 出生区、部署区按连通块分组，从左到右排序（关卡数据里的 area 编号就是这里的下标）。
var spawn_areas: Array[PackedInt32Array] = []
var deploy_areas: Array[PackedInt32Array] = []

var q_min: int = 0
var q_max: int = 0


## 轴向坐标 → 格子下标；不在地图内返回 -1。
func cell_at(q: int, r: int) -> int:
	if r < 0 or r >= height:
		return -1
	var col: int = q + ((r - (r & 1)) >> 1)
	if col < 0 or col >= width:
		return -1
	return r * width + col


func axial(cell: int) -> Vector2i:
	return Vector2i(cell_q[cell], cell_r[cell])


func distance(a: int, b: int) -> int:
	return Hex.distance_qr(cell_q[a], cell_r[a], cell_q[b], cell_r[b])


func to_pixel(cell: int, size: float) -> Vector2:
	return Hex.to_pixel(axial(cell), size)
