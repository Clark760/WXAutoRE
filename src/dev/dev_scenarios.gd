class_name DevScenarios
extends RefCounted

## M0 用的压测场景（设计文档 10.1 的 B1～B4）。单位和地图暂时写在代码里，M1 起搬进 mods/base。

const NAMES: PackedStringArray = ["B1", "B2", "B3", "B4"]

const DESCRIPTIONS: Dictionary = {
	"B1": "20v20 · 1 路开阔地 · 全体驻守",
	"B2": "50v200 · 3 路 + 中央广场（终局地图）· 全体驻守",
	"B3": "50v200 · 2 路 + 窄口 + 死士密集",
	"B4": "60v240 · 300 单位极限（只记录）",
}

const SHAOLIN: Color = Color("c8a040")
const WUDANG: Color = Color("3a8f84")
const TANGMEN: Color = Color("7a55a8")


static func unit_defs() -> Dictionary:
	var d: Dictionary = {}
	# 我方弟子
	# 数值只为压测时能打出持续鏖战；正式数值在 M3 调
	d["wuseng"] = UnitDef.make("disciple_shaolin_wuseng", "少林武僧", "少", SHAOLIN, {
		"hp": 1500.0, "atk": 55.0, "iat": 20.0, "def_ext": 95.0, "def_int": 60.0,
		"attack_interval": 1.0, "attack_range": 1, "move_interval": 0.45, "crit": 0.05 })
	d["jiantong"] = UnitDef.make("disciple_wudang_jiantong", "武当剑童", "武", WUDANG, {
		"hp": 900.0, "atk": 30.0, "iat": 85.0, "def_ext": 45.0, "def_int": 70.0,
		"attack_interval": 0.8, "attack_range": 1, "move_interval": 0.4, "crit": 0.15 })
	d["tangmen"] = UnitDef.make("disciple_tangmen_dizi", "唐门弟子", "唐", TANGMEN, {
		"hp": 600.0, "atk": 72.0, "iat": 20.0, "def_ext": 30.0, "def_int": 40.0,
		"attack_interval": 1.1, "attack_range": 4, "move_interval": 0.5, "crit": 0.15 })
	# 敌人
	d["bandit"] = UnitDef.make("enemy_bandit", "山贼", "贼", Color("6b5844"), {
		"hp": 320.0, "atk": 34.0, "def_ext": 20.0, "def_int": 15.0,
		"attack_interval": 1.2, "attack_range": 1, "move_interval": 0.55, "alert_radius": 2 })
	d["archer"] = UnitDef.make("enemy_archer", "弓手", "弓", Color("8a6d3b"), {
		"hp": 240.0, "atk": 30.0, "def_ext": 12.0, "def_int": 12.0,
		"attack_interval": 1.5, "attack_range": 4, "move_interval": 0.6, "alert_radius": 2 })
	d["scout"] = UnitDef.make("enemy_bandit_scout", "山贼探子", "探", Color("b5452f"), {
		"hp": 300.0, "atk": 30.0, "def_ext": 15.0, "def_int": 15.0,
		"attack_interval": 1.0, "attack_range": 1, "move_interval": 0.32,
		"alert_radius": 0, "suicider": true })
	d["cultist"] = UnitDef.make("enemy_cultist", "魔教教众", "教", Color("7d2a2a"), {
		"hp": 380.0, "atk": 40.0, "def_ext": 28.0, "def_int": 20.0,
		"attack_interval": 1.1, "attack_range": 1, "move_interval": 0.5, "alert_radius": 2 })
	d["deathsworn"] = UnitDef.make("enemy_cult_deathsworn", "魔教死士", "死", Color("c0392b"), {
		"hp": 520.0, "atk": 42.0, "def_ext": 30.0, "def_int": 25.0,
		"attack_interval": 1.0, "attack_range": 1, "move_interval": 0.32,
		"alert_radius": 0, "suicider": true })
	d["elder"] = UnitDef.make("enemy_cult_elder", "魔教长老", "老", Color("6d1f4f"), {
		"hp": 1600.0, "atk": 20.0, "iat": 70.0, "def_ext": 45.0, "def_int": 60.0,
		"attack_interval": 1.3, "attack_range": 2, "move_interval": 0.6, "alert_radius": 3 })
	d["xuedao"] = UnitDef.make("enemy_boss_xuedao", "血刀护法", "护", Color("3b0f0f"), {
		"hp": 6000.0, "atk": 90.0, "def_ext": 70.0, "def_int": 60.0,
		"attack_interval": 1.0, "attack_range": 1, "move_interval": 0.6, "alert_radius": 3 })
	d["elder"].is_hero = true
	d["xuedao"].is_hero = true
	return d


static func build(scenario: String, seed_value: int) -> BattleSim:
	var defs: Dictionary = unit_defs()
	var rows: PackedStringArray
	var allies: Array = []
	var enemies: Array = []
	match scenario:
		"B1":
			rows = map_b1()
			allies = [[defs["wuseng"], 8], [defs["jiantong"], 6], [defs["tangmen"], 6]]
			enemies = [[defs["bandit"], 14], [defs["archer"], 6]]
		"B2":
			rows = map_b2()
			allies = [[defs["wuseng"], 18], [defs["jiantong"], 14], [defs["tangmen"], 18]]
			enemies = [[defs["xuedao"], 1], [defs["elder"], 4], [defs["cultist"], 135],
				[defs["deathsworn"], 10], [defs["archer"], 50]]
		"B3":
			rows = map_b3()
			allies = [[defs["wuseng"], 18], [defs["jiantong"], 14], [defs["tangmen"], 18]]
			enemies = [[defs["bandit"], 120], [defs["scout"], 40], [defs["archer"], 40]]
		"B4":
			rows = map_b2()
			allies = [[defs["wuseng"], 22], [defs["jiantong"], 18], [defs["tangmen"], 20]]
			enemies = [[defs["cultist"], 160], [defs["deathsworn"], 20], [defs["archer"], 60]]
		_:
			push_error("未知场景 %s" % scenario)
			return null

	var parsed := MapParser.parse(rows)
	if not parsed.ok():
		push_error("场景 %s 的地图有错：%s" % [scenario, "；".join(parsed.errors)])
		return null
	var map: BattleMap = parsed.map
	var total: int = 0
	for g in allies + enemies:
		total += int(g[1])

	var sim := BattleSim.new()
	sim.setup(map, total, seed_value)
	var shuffle := RandomNumberGenerator.new()
	shuffle.seed = seed_value * 7919 + 17
	_place_allies(sim, allies)
	_place_enemies(sim, enemies, shuffle)
	return sim


## 我方：各路平均分；每路里近战站前排、远程站后面，从中间往两边排。
static func _place_allies(sim: BattleSim, groups: Array) -> void:
	var units: Array[UnitDef] = _expand(groups)
	units.sort_custom(func(a: UnitDef, b: UnitDef) -> bool: return a.attack_range < b.attack_range)
	var areas: Array[PackedInt32Array] = sim.map.deploy_areas
	var per_area: Array = []
	for a in areas.size():
		per_area.append([])
	for k in units.size():
		per_area[k % areas.size()].append(units[k])
	for a in areas.size():
		var cells: Array[int] = _ordered_cells(sim.map, areas[a], true)
		var list: Array = per_area[a]
		for k in list.size():
			sim.add_unit(list[k], BattleState.TEAM_ALLY, cells[k])


## 敌方：各路平均分；近战和死士站前面（离我方近），远程站后面。
static func _place_enemies(sim: BattleSim, groups: Array, shuffle: RandomNumberGenerator) -> void:
	var units: Array[UnitDef] = _expand(groups)
	# 先打乱再按射程稳定排序，让同射程的不同兵种混在一起
	for k in range(units.size() - 1, 0, -1):
		var j: int = shuffle.randi_range(0, k)
		var tmp: UnitDef = units[k]
		units[k] = units[j]
		units[j] = tmp
	var melee: Array[UnitDef] = []
	var ranged: Array[UnitDef] = []
	for u in units:
		if u.attack_range >= 2:
			ranged.append(u)
		else:
			melee.append(u)
	var ordered: Array[UnitDef] = melee + ranged
	var areas: Array[PackedInt32Array] = sim.map.spawn_areas
	var per_area: Array = []
	for a in areas.size():
		per_area.append([])
	for k in ordered.size():
		per_area[k % areas.size()].append(ordered[k])
	for a in areas.size():
		var cells: Array[int] = _ordered_cells(sim.map, areas[a], false)
		var list: Array = per_area[a]
		for k in list.size():
			sim.add_unit(list[k], BattleState.TEAM_ENEMY, cells[k])


static func _expand(groups: Array) -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for g in groups:
		for k in int(g[1]):
			out.append(g[0])
	return out


## top_first：我方从最上面一行（离敌人最近）开始排；敌方从最下面一行开始排。每行从中间往两边。
static func _ordered_cells(map: BattleMap, area: PackedInt32Array, top_first: bool) -> Array[int]:
	var sum_x: float = 0.0
	for c in area:
		sum_x += map.cell_q[c] + map.cell_r[c] * 0.5
	var center: float = sum_x / area.size()
	var cells: Array[int] = []
	for c in area:
		cells.append(c)
	cells.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = map.cell_r[a]
		var rb: int = map.cell_r[b]
		if ra != rb:
			return ra < rb if top_first else ra > rb
		var xa: float = absf(map.cell_q[a] + ra * 0.5 - center)
		var xb: float = absf(map.cell_q[b] + rb * 0.5 - center)
		if xa != xb:
			return xa < xb
		return a < b)
	return cells


# ---------- 地图 ----------

static func _rows(spec: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for item in spec:
		for k in int(item[0]):
			out.append(item[1])
	return out


## B1：24×20，1 路开阔地。
static func map_b1() -> PackedStringArray:
	return _rows([
		[5, "E".repeat(24)],
		[8, ".".repeat(24)],
		[5, "A".repeat(24)],
		[1, ".".repeat(24)],
		[1, "#".repeat(10) + "GGGG" + "#".repeat(10)],
	])


## B2：48×34，3 路，中间一段打通成广场（终局地图）。
static func map_b2() -> PackedStringArray:
	var wall: String = "###"
	var lane := func(ch: String) -> String: return ch.repeat(14) + wall + ch.repeat(14) + wall + ch.repeat(14)
	var gate_lane: String = "#####GGGG#####"
	return _rows([
		[7, lane.call("E")],
		[7, lane.call(".")],
		[6, ".".repeat(48)],
		[6, lane.call(".")],
		[6, lane.call("A")],
		[1, lane.call(".")],
		[1, gate_lane + wall + gate_lane + wall + gate_lane],
	])


## B3：48×34，2 路，中间一道两行宽的窄口相连；每路在部署区前收窄成 4 格的卡口。
static func map_b3() -> PackedStringArray:
	var wall: String = "########"
	var lane := func(ch: String) -> String: return ch.repeat(20) + wall + ch.repeat(20)
	var choke: String = "#".repeat(8) + "...." + "#".repeat(8)
	var gate_lane: String = "#".repeat(8) + "GGGG" + "#".repeat(8)
	return _rows([
		[7, lane.call("E")],
		[8, lane.call(".")],
		[2, ".".repeat(48)],
		[4, lane.call(".")],
		[2, choke + wall + choke],
		[1, lane.call(".")],
		[8, lane.call("A")],
		[1, lane.call(".")],
		[1, gate_lane + wall + gate_lane],
	])
