extends TestCase

## Hex：全项目唯一的距离公式和坐标换算（设计文档 6.1）。


func test_distance_known_answers() -> void:
	var cases: Array = [
		[Vector2i(0, 0), Vector2i(0, 0), 0],
		[Vector2i(0, 0), Vector2i(1, 0), 1],
		[Vector2i(0, 0), Vector2i(2, -1), 2],
		[Vector2i(0, 0), Vector2i(3, -3), 3],
		[Vector2i(1, 2), Vector2i(-2, 1), 4],
		[Vector2i(0, 0), Vector2i(-1, 2), 2],
		[Vector2i(-3, 5), Vector2i(4, -2), 7],
	]
	for c in cases:
		check_eq(Hex.distance(c[0], c[1]), c[2], "%s 到 %s 的距离" % [c[0], c[1]])
		check_eq(Hex.distance(c[1], c[0]), c[2], "距离应当对称")


func test_six_neighbors_are_distinct_and_adjacent() -> void:
	var seen: Dictionary = {}
	for k in 6:
		var n: Vector2i = Hex.neighbor(Vector2i(2, 3), k)
		check_eq(Hex.distance(Vector2i(2, 3), n), 1, "方向 %d 的邻居距离" % k)
		seen[n] = true
	check_eq(seen.size(), 6, "6 个邻居互不相同")


func test_offset_axial_roundtrip() -> void:
	for row in 8:
		for col in 8:
			var a: Vector2i = Hex.offset_to_axial(col, row)
			check_eq(Hex.axial_to_offset(a), Vector2i(col, row), "偏移 (%d,%d) 往返" % [col, row])


## 旧项目的索敌 bug 就出在这里：奇数行和偶数行的邻居不一样，必须先换成轴向再算距离。
func test_odd_r_layout_neighbors() -> void:
	# 奇数行 (1,1) 的邻居（偏移坐标）
	var odd_center: Vector2i = Hex.offset_to_axial(1, 1)
	for o in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 2), Vector2i(2, 2)]:
		check_eq(Hex.distance(odd_center, Hex.offset_to_axial(o.x, o.y)), 1, "奇数行邻居 %s" % o)
	check_eq(Hex.distance(odd_center, Hex.offset_to_axial(0, 0)), 2, "奇数行的左上斜对角不是邻居")
	# 偶数行 (1,2) 的邻居
	var even_center: Vector2i = Hex.offset_to_axial(1, 2)
	for o in [Vector2i(0, 2), Vector2i(2, 2), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 3), Vector2i(1, 3)]:
		check_eq(Hex.distance(even_center, Hex.offset_to_axial(o.x, o.y)), 1, "偶数行邻居 %s" % o)
	check_eq(Hex.distance(even_center, Hex.offset_to_axial(2, 1)), 2, "偶数行的右上斜对角不是邻居")


func test_pixel_roundtrip() -> void:
	for q in range(-4, 5):
		for r in range(-4, 5):
			var c := Vector2i(q, r)
			check_eq(Hex.from_pixel(Hex.to_pixel(c, 16.0), 16.0), c, "像素往返 %s" % c)
			# 格子边缘附近也要落回本格
			var p: Vector2 = Hex.to_pixel(c, 16.0) + Vector2(6.0, -5.0)
			check_eq(Hex.from_pixel(p, 16.0), c, "偏离中心的像素点 %s" % c)
