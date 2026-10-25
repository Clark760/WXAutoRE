extends TestCase

## 字符画地图解析与检查（设计文档 6.1）。


func test_parse_b1_counts() -> void:
	var r := MapParser.parse(DevScenarios.map_b1())
	check(r.ok(), "B1 地图应当解析成功：%s" % "；".join(r.errors))
	if not r.ok():
		return
	check_eq(r.map.gate_cells.size(), 4, "城门格数")
	check_eq(r.map.spawn_cells.size(), 120, "出生区格数")
	check_eq(r.map.deploy_cells.size(), 120, "部署区格数")
	check_eq(r.map.spawn_areas.size(), 1, "出生区块数")


func test_areas_sorted_left_to_right() -> void:
	var r := MapParser.parse(DevScenarios.map_b2())
	check(r.ok(), "B2 地图应当解析成功")
	if not r.ok():
		return
	check_eq(r.map.spawn_areas.size(), 3, "三路出生区")
	check_eq(r.map.deploy_areas.size(), 3, "三路部署区")
	var xs: Array[float] = []
	for area in r.map.spawn_areas:
		var c: int = area[0]
		xs.append(r.map.to_pixel(c, 1.0).x)
	check(xs[0] < xs[1] and xs[1] < xs[2], "出生区按从左到右排序：%s" % [xs])


func test_uneven_rows() -> void:
	var r := MapParser.parse(PackedStringArray(["E..", "..", "AGA"]))
	check(not r.ok(), "行宽不一致应当报错")
	check_contains(r.errors, "第 2 行", "报错要指出是哪一行")


func test_unknown_char() -> void:
	var r := MapParser.parse(PackedStringArray(["E.x", "...", "AGA"]))
	check(not r.ok(), "未知字符应当报错")
	check_contains(r.errors, "未知字符", "报错说明原因")
	check_contains(r.errors, "第 1 行第 3 列", "报错指出位置")


func test_missing_gate() -> void:
	var r := MapParser.parse(PackedStringArray(["EEE", "...", "AAA"]))
	check_contains(r.errors, "没有城门", "缺城门应当报错")


func test_spawn_must_reach_gate() -> void:
	var r := MapParser.parse(PackedStringArray([
		"#####E",
		"#E####",
		"#####.",
		"AAAA..",
		"GGG###",
	]))
	check(not r.ok(), "被墙围住的出生区应当报错")
	check_contains(r.errors, "走不到任何城门", "报错说明原因")


func test_capacity() -> void:
	var r := MapParser.parse(DevScenarios.map_b1())
	var errors := MapParser.check_capacity(r.map, 121, 10)
	check_contains(errors, "放不下 121 个敌人", "出生区容量")
	errors = MapParser.check_capacity(r.map, 10, 121)
	check_contains(errors, "放不下上阵上限 121 人", "部署区容量")
	check_eq(MapParser.check_capacity(r.map, 120, 120).size(), 0, "刚好放得下")


func test_walk_masks() -> void:
	var r := MapParser.parse(DevScenarios.map_b1())
	var map: BattleMap = r.map
	for g in map.gate_cells:
		check_eq(map.walk_ally[g], 0, "我方不能站城门格")
		check_eq(map.walk_enemy[g], 1, "敌人可以踏上城门格")
	# 城门两侧是墙：墙格的所有邻居都是 -1，墙也不会出现在别人的邻居里
	for c in map.cell_count:
		for k in 6:
			var n: int = map.neighbors[c * 6 + k]
			if n >= 0:
				check(map.cell_type[n] != BattleMap.CellType.WALL, "邻居表里不能有墙")
				check_eq(map.distance(c, n), 1, "邻居距离为 1")
