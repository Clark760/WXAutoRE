class_name MapParser
extends RefCounted

## 把关卡里的字符画解析成 BattleMap，并做设计文档 6.1 要求的检查。
## 字符：. 空地  # 墙  E 敌方出生区  A 我方部署区  G 城门

const CHAR_TYPES: Dictionary = {
	".": BattleMap.CellType.FLOOR,
	"#": BattleMap.CellType.WALL,
	"E": BattleMap.CellType.SPAWN,
	"A": BattleMap.CellType.DEPLOY,
	"G": BattleMap.CellType.GATE,
}

## 同一类错误最多列出几条，避免一张错图刷屏。
const MAX_ERRORS_PER_KIND: int = 5


class Result:
	extends RefCounted
	var map: BattleMap = null
	var errors: PackedStringArray = PackedStringArray()

	func ok() -> bool:
		return errors.is_empty()


static func parse(rows: PackedStringArray) -> Result:
	var result := Result.new()
	if rows.is_empty():
		result.errors.append("地图是空的")
		return result

	_check_shape(rows, result.errors)
	if not result.ok():
		return result

	var map := _build(rows)
	if map.gate_cells.is_empty():
		result.errors.append("地图里没有城门（G）")
	if map.spawn_cells.is_empty():
		result.errors.append("地图里没有敌方出生区（E）")
	if map.deploy_cells.is_empty():
		result.errors.append("地图里没有我方部署区（A）")
	if not result.ok():
		return result

	_check_spawn_reaches_gate(map, result.errors)
	if result.ok():
		result.map = map
	return result


## 关卡层面的容量检查：出生区放得下全部敌人，部署区放得下上阵上限。
static func check_capacity(map: BattleMap, enemy_count: int, deploy_cap: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if map.spawn_cells.size() < enemy_count:
		errors.append("出生区只有 %d 格，放不下 %d 个敌人" % [map.spawn_cells.size(), enemy_count])
	if map.deploy_cells.size() < deploy_cap:
		errors.append("部署区只有 %d 格，放不下上阵上限 %d 人" % [map.deploy_cells.size(), deploy_cap])
	return errors


static func _check_shape(rows: PackedStringArray, errors: PackedStringArray) -> void:
	var width: int = rows[0].length()
	if width == 0:
		errors.append("第 1 行是空的")
		return
	var bad_chars: int = 0
	for row in rows.size():
		var line: String = rows[row]
		if line.length() != width:
			errors.append("第 %d 行有 %d 个字符，第 1 行有 %d 个；每行必须等长" % [row + 1, line.length(), width])
			continue
		for col in width:
			var ch: String = line[col]
			if CHAR_TYPES.has(ch):
				continue
			bad_chars += 1
			if bad_chars <= MAX_ERRORS_PER_KIND:
				errors.append("第 %d 行第 %d 列：未知字符 \"%s\"（可用：. # E A G）" % [row + 1, col + 1, ch])
	if bad_chars > MAX_ERRORS_PER_KIND:
		errors.append("……另有 %d 个未知字符" % (bad_chars - MAX_ERRORS_PER_KIND))


static func _build(rows: PackedStringArray) -> BattleMap:
	var map := BattleMap.new()
	map.width = rows[0].length()
	map.height = rows.size()
	map.cell_count = map.width * map.height
	map.cell_type.resize(map.cell_count)
	map.cell_q.resize(map.cell_count)
	map.cell_r.resize(map.cell_count)
	map.walk_enemy.resize(map.cell_count)
	map.walk_ally.resize(map.cell_count)
	map.q_min = 1 << 30
	map.q_max = -(1 << 30)

	# 这里是全项目唯一一处把偏移坐标换成轴向坐标的地方
	for row in map.height:
		var line: String = rows[row]
		for col in map.width:
			var cell: int = row * map.width + col
			var c: Vector2i = Hex.offset_to_axial(col, row)
			var t: int = CHAR_TYPES[line[col]]
			map.cell_type[cell] = t
			map.cell_q[cell] = c.x
			map.cell_r[cell] = c.y
			map.q_min = mini(map.q_min, c.x)
			map.q_max = maxi(map.q_max, c.x)
			map.walk_enemy[cell] = 0 if t == BattleMap.CellType.WALL else 1
			var ally_ok: bool = t != BattleMap.CellType.WALL and t != BattleMap.CellType.GATE
			map.walk_ally[cell] = 1 if ally_ok else 0
			match t:
				BattleMap.CellType.GATE:
					map.gate_cells.append(cell)
				BattleMap.CellType.SPAWN:
					map.spawn_cells.append(cell)
				BattleMap.CellType.DEPLOY:
					map.deploy_cells.append(cell)

	map.neighbors.resize(map.cell_count * 6)
	for cell in map.cell_count:
		for k in 6:
			var n: int = -1
			if map.walk_enemy[cell] == 1:
				var d: Vector2i = Hex.DIRECTIONS[k]
				n = map.cell_at(map.cell_q[cell] + d.x, map.cell_r[cell] + d.y)
				if n >= 0 and map.walk_enemy[n] == 0:
					n = -1
			map.neighbors[cell * 6 + k] = n

	map.spawn_areas = _group_areas(map, map.spawn_cells)
	map.deploy_areas = _group_areas(map, map.deploy_cells)
	return map


## 从城门反向搜索，所有出生区格子都必须能走到某个城门。
static func _check_spawn_reaches_gate(map: BattleMap, errors: PackedStringArray) -> void:
	var seen := PackedByteArray()
	seen.resize(map.cell_count)
	var queue: PackedInt32Array = map.gate_cells.duplicate()
	for cell in queue:
		seen[cell] = 1
	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		for k in 6:
			var n: int = map.neighbors[cell * 6 + k]
			if n >= 0 and seen[n] == 0:
				seen[n] = 1
				queue.append(n)
	var stuck: int = 0
	for cell in map.spawn_cells:
		if seen[cell] == 1:
			continue
		stuck += 1
		if stuck <= MAX_ERRORS_PER_KIND:
			var row: int = cell / map.width
			var col: int = cell % map.width
			errors.append("第 %d 行第 %d 列的出生区走不到任何城门" % [row + 1, col + 1])
	if stuck > MAX_ERRORS_PER_KIND:
		errors.append("……另有 %d 个出生区格子走不到城门" % (stuck - MAX_ERRORS_PER_KIND))


## 同类格子按六向连通分块，再按块的平均横向位置从左到右排序。
static func _group_areas(map: BattleMap, cells: PackedInt32Array) -> Array[PackedInt32Array]:
	var area_of := PackedInt32Array()
	area_of.resize(map.cell_count)
	area_of.fill(-1)
	var areas: Array[PackedInt32Array] = []
	var centers: Array[float] = []
	for start in cells:
		if area_of[start] >= 0:
			continue
		var t: int = map.cell_type[start]
		var area := PackedInt32Array([start])
		area_of[start] = areas.size()
		var head: int = 0
		while head < area.size():
			var cell: int = area[head]
			head += 1
			for k in 6:
				var n: int = map.neighbors[cell * 6 + k]
				if n >= 0 and area_of[n] < 0 and map.cell_type[n] == t:
					area_of[n] = areas.size()
					area.append(n)
		var sum_x: float = 0.0
		for cell in area:
			sum_x += map.cell_q[cell] + map.cell_r[cell] * 0.5
		areas.append(area)
		centers.append(sum_x / area.size())

	var order: Array[int] = []
	for i in areas.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return centers[a] < centers[b])
	var sorted: Array[PackedInt32Array] = []
	for i in order:
		sorted.append(areas[i])
	return sorted
