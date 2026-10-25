class_name Hex
extends RefCounted

## 六角格坐标工具。逻辑层一律使用轴向坐标 (q, r)，尖顶朝上。
## 全项目只有这里的 distance() 一个距离公式：移动、普攻、技能、选择器都调用它（设计文档 6.1）。

const SQRT3: float = 1.7320508075688772

## 6 个邻居方向，顺序固定：东、东北、西北、西、西南、东南。
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func distance(a: Vector2i, b: Vector2i) -> int:
	return distance_qr(a.x, a.y, b.x, b.y)


static func distance_qr(aq: int, ar: int, bq: int, br: int) -> int:
	var dq: int = aq - bq
	var dr: int = ar - br
	return (absi(dq) + absi(dr) + absi(dq + dr)) >> 1


static func neighbor(c: Vector2i, direction: int) -> Vector2i:
	return c + DIRECTIONS[direction]


## 字符画地图按"奇行偏移"排列（奇数行右移半格）。
## 偏移坐标只允许出现在地图解析里，逻辑代码永远用轴向坐标。
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - ((row - (row & 1)) >> 1), row)


static func axial_to_offset(c: Vector2i) -> Vector2i:
	return Vector2i(c.x + ((c.y - (c.y & 1)) >> 1), c.y)


## 轴向坐标 → 格子中心的像素位置（size 为六边形外接圆半径）。
static func to_pixel(c: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (c.x + c.y * 0.5), size * 1.5 * c.y)


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q: float = (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r: float = (2.0 / 3.0 * p.y) / size
	return round_axial(q, r)


## 按立方坐标取整，保证结果落在最近的格子上。
static func round_axial(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: float = roundf(q)
	var rr: float = roundf(r)
	var rs: float = roundf(s)
	var dq: float = absf(rq - q)
	var dr: float = absf(rr - r)
	var ds: float = absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))
