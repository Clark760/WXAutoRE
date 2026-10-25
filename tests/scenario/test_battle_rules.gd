extends TestCase

## 城门、敌我行为、确定性（设计文档 6.4、6.5、6.7、9.6）。

var _defs: Dictionary = DevScenarios.unit_defs()


## 15×12 开阔地：上面两行出生区，下面一行部署区，最下面中间 3 格城门。
func _open_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	rows.append("E".repeat(15))
	rows.append("E".repeat(15))
	for k in 8:
		rows.append(".".repeat(15))
	rows.append("A".repeat(15))
	rows.append("######GGG######")
	return rows


func _sim(rows: PackedStringArray, capacity: int) -> BattleSim:
	var parsed := MapParser.parse(rows)
	check(parsed.ok(), "测试地图应当合法：%s" % "；".join(parsed.errors))
	var sim := BattleSim.new()
	sim.setup(parsed.map, capacity, 1)
	return sim


func _at(sim: BattleSim, col: int, row: int) -> int:
	return row * sim.map.width + col


func _def(key: String, overrides: Dictionary = {}) -> UnitDef:
	var src: UnitDef = _defs[key]
	var d := UnitDef.make(src.id, src.name, src.glyph, src.color, {})
	for p in ["hp", "atk", "iat", "def_ext", "def_int", "attack_interval", "attack_range",
			"move_interval", "crit", "guard_radius", "alert_radius", "suicider"]:
		d.set(p, src.get(p))
	for key2 in overrides:
		d.set(key2, overrides[key2])
	return d


func _run(sim: BattleSim, ticks: int) -> void:
	for k in ticks:
		if not sim.is_running():
			return
		sim.tick()


func test_breach_fails_on_the_same_tick() -> void:
	var sim := _sim(_open_rows(), 2)
	sim.add_unit(_def("wuseng"), BattleState.TEAM_ALLY, _at(sim, 0, 10))
	# 敌人站在城门正上方一格，下一帧就会踏上城门
	var e: int = sim.add_unit(_def("bandit"), BattleState.TEAM_ENEMY, _at(sim, 7, 10))
	sim.start()
	sim.tick()
	check_eq(sim.outcome, BattleSim.Outcome.LOSS_BREACH, "敌人踏上城门的当帧就失败")
	check_eq(sim.breach_unit, e, "记录是谁踏上了城门")


func test_ally_cannot_be_placed_on_gate() -> void:
	var sim := _sim(_open_rows(), 1)
	for g in sim.map.gate_cells:
		check_eq(sim.map.walk_ally[g], 0, "城门格对我方不可站")
	check_eq(sim.st.occupant[sim.map.gate_cells[0]], -1, "城门格是空的")


## 驻守单位迎敌不出防区，敌人死了以后回到部署格。
func test_guard_stays_in_zone_and_returns_home() -> void:
	var sim := _sim(_open_rows(), 3)
	var home: int = _at(sim, 3, 10)
	var a: int = sim.add_unit(_def("wuseng", {"atk": 400.0}), BattleState.TEAM_ALLY, home)
	# 弱小的敌人出现在防区边上（3 格），站着不动
	var e: int = sim.add_unit(_def("bandit", {"hp": 30.0}), BattleState.TEAM_ENEMY, _at(sim, 3, 7))
	sim.st.move_cd[e] = 1000.0
	# 远处一个几乎不动的敌人，让战斗不会提前结束
	var far: int = sim.add_unit(_def("bandit"), BattleState.TEAM_ENEMY, _at(sim, 14, 0))
	sim.st.move_interval[far] = 1000.0
	sim.start()
	var max_dist: int = 0
	for k in 80:
		sim.tick()
		max_dist = maxi(max_dist, sim.map.distance(home, sim.st.cell[a]))
	check_eq(sim.st.alive[e], 0, "防区里的敌人被消灭")
	check(max_dist >= 1, "驻守单位确实出去迎敌了")
	check(max_dist <= sim.st.guard_radius[a], "不出防区（最远 %d 格）" % max_dist)
	check_eq(sim.st.cell[a], home, "敌人死后回到部署格")
	check_eq(sim.st.state[a], BattleState.UnitState.GUARD, "回到原位后是驻守状态")


## 远程驻守单位打射程内离城门最近的敌人，而不是离自己最近的。
func test_ranged_targets_enemy_closest_to_gate() -> void:
	var sim := _sim(_open_rows(), 3)
	var a: int = sim.add_unit(_def("tangmen"), BattleState.TEAM_ALLY, _at(sim, 2, 10))
	var near_me: int = sim.add_unit(_def("bandit"), BattleState.TEAM_ENEMY, _at(sim, 1, 8))
	var near_gate: int = sim.add_unit(_def("bandit"), BattleState.TEAM_ENEMY, _at(sim, 5, 9))
	for e in [near_me, near_gate]:
		sim.st.move_cd[e] = 1000.0
		sim.st.alert_radius[e] = 0
	sim.start()
	var map: BattleMap = sim.map
	var gd: PackedInt32Array = sim.gate_field.dist
	var ac: int = sim.st.cell[a]
	check(map.distance(ac, sim.st.cell[near_me]) < map.distance(ac, sim.st.cell[near_gate]), "前提：near_me 离我更近")
	check(gd[sim.st.cell[near_gate]] < gd[sim.st.cell[near_me]], "前提：near_gate 离城门更近")
	check(map.distance(ac, sim.st.cell[near_gate]) <= 4, "前提：两个都在射程内")
	sim.tick()
	check_eq(sim.st.target[a], near_gate, "选离城门最近的敌人")


## 死士挨打不反击，只管冲城门；普通敌人挨打会转身去找打它的人。
func test_suicider_ignores_attacks_but_normal_enemy_reacts() -> void:
	for suicider in [true, false]:
		var sim := _sim(_open_rows(), 2)
		# 远程站在右侧，不挡敌人去城门的路；射程 6，敌人路过时一定会挨打
		var a: int = sim.add_unit(_def("tangmen", {"atk": 1.0, "hp": 99999.0, "attack_range": 6}),
				BattleState.TEAM_ALLY, _at(sim, 12, 10))
		sim.st.guard_radius[a] = 0
		var key: String = "scout" if suicider else "bandit"
		var e: int = sim.add_unit(_def(key, {"hp": 99999.0, "alert_radius": 0}), BattleState.TEAM_ENEMY, _at(sim, 10, 4))
		sim.end_on_breach = false
		sim.start()
		var min_dist: int = 1 << 30
		for k in 120:
			if sim.st.alive[e] == 0 or not sim.is_running():
				break
			sim.tick()
			if sim.st.alive[e] == 1:
				min_dist = mini(min_dist, sim.map.distance(sim.st.cell[a], sim.st.cell[e]))
		if suicider:
			check(sim.breach_count == 1, "死士一路冲到城门")
			check(min_dist > 1, "死士没有贴上去打远程（最近 %d 格）" % min_dist)
		else:
			check(min_dist <= 1, "普通敌人挨打后贴上去反击（最近 %d 格）" % min_dist)


## 一格宽的走廊里，死士被挡住就和挡路的人交战。
func test_blocked_suicider_attacks_blocker() -> void:
	var rows := PackedStringArray(["##E##", "##.##", "##.##", "##A##", "##G##"])
	var sim := _sim(rows, 2)
	var a: int = sim.add_unit(_def("wuseng", {"atk": 1.0}), BattleState.TEAM_ALLY, _at(sim, 2, 3))
	var s: int = sim.add_unit(_def("scout"), BattleState.TEAM_ENEMY, _at(sim, 2, 0))
	sim.start()
	_run(sim, 40)
	check_eq(sim.st.target[s], a, "死士把挡路的人当成目标")
	check(sim.st.hp[a] < sim.st.hp_max[a], "挡路的人挨了打")
	check_eq(sim.breach_count, 0, "没有冲过去")


## 普通敌人警戒范围内出现我方单位时，放下城门去交战；警戒半径为 0 时不理会。
## 摆位：我方在敌人左上方 2 格，敌人去城门要往右下走，两个方向相反。
func test_normal_enemy_engages_within_alert_radius() -> void:
	for alert in [2, 0]:
		var sim := _sim(_open_rows(), 2)
		var a: int = sim.add_unit(_def("wuseng", {"atk": 1.0, "hp": 99999.0}), BattleState.TEAM_ALLY, _at(sim, 1, 7))
		sim.st.guard_radius[a] = 0
		var e: int = sim.add_unit(_def("bandit", {"hp": 99999.0}), BattleState.TEAM_ENEMY, _at(sim, 3, 8))
		sim.st.alert_radius[e] = alert
		sim.end_on_breach = false
		check_eq(sim.map.distance(sim.st.cell[a], sim.st.cell[e]), 2, "前提：相距 2 格")
		sim.start()
		_run(sim, 10)
		var d: int = sim.map.distance(sim.st.cell[a], sim.st.cell[e])
		if alert == 2:
			check_eq(d, 1, "警戒半径 2：敌人转身贴上来")
			check_eq(sim.st.target[e], a, "并把我方单位当成目标")
		else:
			check(d > 2, "警戒半径 0：敌人照常去城门（相距 %d 格）" % d)


## 隔着墙走不过去的我方单位，敌方远程不会停下来射（M0 压测 B3 的死锁就是这样来的）。
func test_ranged_enemy_does_not_camp_behind_wall() -> void:
	var rows := PackedStringArray([
		"EEEE###....",
		"....###....",
		"....###AAAA",
		"....###....",
		"....###....",
		"....###....",
		"GGGG###....",
	])
	var sim := _sim(rows, 2)
	var a: int = sim.add_unit(_def("wuseng", {"hp": 99999.0}), BattleState.TEAM_ALLY, _at(sim, 7, 2))
	var e: int = sim.add_unit(_def("archer", {"attack_range": 8}), BattleState.TEAM_ENEMY, _at(sim, 3, 0))
	check(sim.map.distance(sim.st.cell[a], sim.st.cell[e]) <= 8, "前提：隔着墙在射程内")
	sim.end_on_breach = false
	sim.start()
	_run(sim, 60)
	check_eq(sim.breach_count, 1, "弓手没有停在墙后，一路走到了城门")
	check_eq(sim.st.hp[a], sim.st.hp_max[a], "墙另一边的我方单位没挨打")


func test_dead_unit_frees_its_cell() -> void:
	var sim := _sim(_open_rows(), 2)
	sim.add_unit(_def("wuseng", {"atk": 9999.0}), BattleState.TEAM_ALLY, _at(sim, 7, 10))
	var e: int = sim.add_unit(_def("bandit", {"hp": 1.0}), BattleState.TEAM_ENEMY, _at(sim, 7, 9))
	var c: int = sim.st.cell[e]
	sim.start()
	sim.tick()
	check_eq(sim.st.alive[e], 0, "敌人阵亡")
	check_eq(sim.st.occupant[c], -1, "阵亡后格子空出来")
	check_eq(sim.outcome, BattleSim.Outcome.WIN, "敌人全灭即胜利")


## 同一个种子跑 3 次，结束时的状态哈希必须一致（设计文档 9.6）。
func test_determinism_same_seed() -> void:
	var hashes: Array[int] = []
	for k in 3:
		var sim: BattleSim = DevScenarios.build("B1", 42)
		sim.start()
		_run(sim, 3000)
		hashes.append(sim.state_hash())
	check(hashes[0] == hashes[1] and hashes[1] == hashes[2], "三次哈希一致：%s" % [hashes])
	var other: BattleSim = DevScenarios.build("B1", 43)
	other.start()
	_run(other, 3000)
	check(other.state_hash() != hashes[0], "换种子结果应当不同")
