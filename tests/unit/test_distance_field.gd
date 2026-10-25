extends TestCase

## 距离场（设计文档 6.3）。


func _open_map() -> BattleMap:
	var rows := PackedStringArray()
	rows.append("E".repeat(15))
	for k in 9:
		rows.append(".".repeat(15))
	rows.append("A".repeat(15))
	rows.append("######GGG######")
	return MapParser.parse(rows).map


## 开阔地上，城门场就等于到最近城门的格距。
func test_gate_field_equals_hex_distance_on_open_map() -> void:
	var map := _open_map()
	var occupant := PackedInt32Array()
	occupant.resize(map.cell_count)
	occupant.fill(-1)
	var f := DistanceField.new()
	f.setup(map, map.walk_enemy)
	f.build(map.gate_cells, map.gate_cells.size(), occupant, PackedByteArray(), -1)
	var mismatches: int = 0
	for c in map.cell_count:
		if map.walk_enemy[c] == 0:
			continue
		var best: int = 1 << 30
		for g in map.gate_cells:
			best = mini(best, map.distance(c, g))
		if f.dist[c] != best:
			mismatches += 1
	check_eq(mismatches, 0, "城门场与格距不一致的格子数")


## 自己人占着的格子代价是 3，后面的人会绕开。
func test_crowd_cost_makes_units_go_around() -> void:
	var map := _open_map()
	var s: int = map.cell_at(map.cell_q[5 * 15 + 7], map.cell_r[5 * 15 + 7])
	var sq: int = map.cell_q[s]
	var sr: int = map.cell_r[s]
	var c: int = map.cell_at(sq + 1, sr)     # 起点正东一格
	var d: int = map.cell_at(sq + 2, sr)     # 同一直线再往东一格：和起点只有 c 这一个公共邻居
	var occupant := PackedInt32Array()
	occupant.resize(map.cell_count)
	occupant.fill(-1)
	var team := PackedByteArray([0])
	occupant[c] = 0
	var f := DistanceField.new()
	f.setup(map, map.walk_ally)
	var sources := PackedInt32Array([s])
	f.build(sources, 1, occupant, team, 0)
	check_eq(f.dist[c], 1, "紧挨起点的格子")
	check_eq(f.dist[d], 3, "穿过自己人要 1+3=4，绕开只要 3")
	# 占格的是对方阵营时不加代价
	f.build(sources, 1, occupant, team, 1)
	check_eq(f.dist[d], 2, "对方单位不算拥挤")


func test_limit_stops_expansion() -> void:
	var map := _open_map()
	var occupant := PackedInt32Array()
	occupant.resize(map.cell_count)
	occupant.fill(-1)
	var f := DistanceField.new()
	f.setup(map, map.walk_enemy)
	f.build(map.gate_cells, map.gate_cells.size(), occupant, PackedByteArray(), -1, 2)
	var far: int = map.spawn_cells[0]
	check_eq(f.dist[far], DistanceField.UNREACHABLE, "超出上限的格子不展开")
	var g: int = map.gate_cells[1]
	check_eq(f.dist[g], 0, "起点为 0")
