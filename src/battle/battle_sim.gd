class_name BattleSim
extends RefCounted

## 战斗模拟：固定 10Hz 逻辑帧（设计文档 6.2）。不依赖任何 Node，可以在 headless 下单独跑和压测。
## 一个逻辑帧：重建空间分桶 → 刷新一张动态距离场（两队错开）→ 逐个单位行动 → 帧末结算死亡 → 城门与胜负检查。

const TICK: float = 0.1
const DEADLOCK_SECONDS: float = 300.0
## 敌方动态场只关心附近的情况，超过这个代价就不再展开。我方迎击场要看全图，不设上限。
const FIELD_LIMIT: int = 16
## 我方迎击场里，每个敌人的初始代价 = 它离城门的步数 ÷ 这个数。离城门越近越优先被拦截。
const THREAT_DIVISOR: int = 2

enum Outcome { RUNNING, WIN, LOSS_BREACH, LOSS_DEADLOCK }

const TEAM_ALLY: int = BattleState.TEAM_ALLY
const TEAM_ENEMY: int = BattleState.TEAM_ENEMY

var st: BattleState = BattleState.new()
var map: BattleMap

## 城门场：整局只算一次。敌人沿它冲城门；我方远程用它判断谁离城门最近。
var gate_field: DistanceField = DistanceField.new()
## 我方迎击场：每格到"最该拦截的敌人"的代价。起点是所有敌人，初始代价按离城门的远近加权；
## 自己人占着的格子加代价，后排会绕到侧面。我方单位迎敌时沿它移动。
var ally_field: DistanceField = DistanceField.new()
## 敌方动态场：每格到最近我方单位的纯走路距离（不加拥挤代价），敌人交战时沿它移动，
## 也用来判断"我方单位是否真的走得到"——隔着墙的不算。
var enemy_field: DistanceField = DistanceField.new()

var buckets: UnitBuckets = UnitBuckets.new()
var ally_ai: AllyAI = AllyAI.new()
var enemy_ai: EnemyAI = EnemyAI.new()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 压测时挂上，平时为空。
var metrics: BattleMetrics = null

var time: float = 0.0
var tick_index: int = 0
var outcome: int = Outcome.RUNNING
## 正式战斗里敌人踏上城门即失败；压测时关掉，只计数，让战斗继续跑完。
var end_on_breach: bool = true
var breach_count: int = 0
## 第一个踏上城门的敌人（失败回放要用）。
var breach_unit: int = -1
var attacks_this_tick: int = 0

var _sources: PackedInt32Array = PackedInt32Array()
var _source_cost: PackedInt32Array = PackedInt32Array()
var _started: bool = false


func setup(p_map: BattleMap, capacity: int, seed_value: int) -> void:
	map = p_map
	st.setup(map, capacity)
	rng.seed = seed_value
	gate_field.setup(map, map.walk_enemy)
	gate_field.build(map.gate_cells, map.gate_cells.size(), st.occupant, st.team, -1)
	ally_field.setup(map, map.walk_ally)
	enemy_field.setup(map, map.walk_enemy)
	_sources.resize(capacity)
	_source_cost.resize(capacity)


func add_unit(d: UnitDef, team: int, cell: int) -> int:
	return st.add_unit(d, team, cell)


## 放完单位以后调用一次：建好分桶和两张动态场，开战第一帧就能直接用。
func start() -> void:
	buckets.setup(map, st)
	ally_ai.bind(self)
	enemy_ai.bind(self)
	buckets.rebuild()
	_build_dynamic_field(TEAM_ALLY)
	_build_dynamic_field(TEAM_ENEMY)
	_started = true


func tick() -> void:
	if outcome != Outcome.RUNNING:
		return
	if not _started:
		start()
	tick_index += 1
	time += TICK
	attacks_this_tick = 0

	buckets.rebuild()
	# 两张动态场错开帧刷新，每帧只算一张
	if (tick_index & 1) == 0:
		_build_dynamic_field(TEAM_ALLY)
	else:
		_build_dynamic_field(TEAM_ENEMY)

	# AI 只在逻辑帧期间持有 sim 的引用，帧结束就断开，避免互相引用导致内存泄漏
	ally_ai.sim = self
	enemy_ai.sim = self
	# 偶数帧正序、奇数帧倒序，避免下标小的单位永远先动
	var n: int = st.unit_count
	var forward: bool = (tick_index & 1) == 0
	var alive: PackedByteArray = st.alive
	var team: PackedByteArray = st.team
	for k in n:
		var i: int = k if forward else n - 1 - k
		if alive[i] == 0:
			continue
		if team[i] == TEAM_ALLY:
			ally_ai.step(i)
		else:
			enemy_ai.step(i)
	ally_ai.sim = null
	enemy_ai.sim = null

	_resolve_deaths()
	_check_end()


func is_running() -> bool:
	return outcome == Outcome.RUNNING


# ---------- 供 AI 调用的基础操作 ----------

func set_target(i: int, t: int) -> void:
	var old: int = st.target[i]
	if old == t:
		return
	if old >= 0:
		st.attackers[old] -= 1
	st.target[i] = t
	if t >= 0:
		st.attackers[t] += 1


func move_unit(i: int, to: int) -> void:
	var from: int = st.cell[i]
	st.occupant[from] = -1
	st.occupant[to] = i
	st.cell[i] = to
	st.move_from[i] = from
	st.move_start[i] = time
	st.move_dur[i] = st.move_interval[i]
	st.move_cd[i] = st.move_interval[i]


## 普攻：伤害 = 攻击 × 100 / (100 + 对应防御) × 随机(0.95～1.05)，暴击 ×1.5（设计文档 6.6）。
func attack(i: int, t: int) -> void:
	var defense: float = st.def_ext[t] if st.damage_type[i] == BattleState.DAMAGE_EXTERNAL else st.def_int[t]
	var dmg: float = st.offense[i] * 100.0 / (100.0 + defense) * rng.randf_range(0.95, 1.05)
	if rng.randf() < st.crit[i]:
		dmg *= 1.5
	st.hp[t] -= dmg
	st.attack_cd[i] = st.attack_interval[i]
	st.hit_time[t] = time
	if st.team[t] == TEAM_ENEMY:
		st.last_attacker[t] = i
		st.provoked_at[t] = time
	attacks_this_tick += 1
	# 远程开火延迟：敌人进入射程到第一次开火
	if st.range_since[i] >= 0.0:
		if metrics != null and st.team[i] == TEAM_ALLY:
			metrics.record_fire_latency(time - st.range_since[i])
		st.range_since[i] = -2.0


## 敌人踏上城门格。
func on_breach(i: int) -> void:
	breach_count += 1
	if breach_unit < 0:
		breach_unit = i
	if not end_on_breach:
		# 压测模式：把它移出战场，战斗继续
		st.hp[i] = -1.0


## 同一阵营 + 同一状态下的稳定哈希，用来验证确定性。
func state_hash() -> int:
	var h: int = 2166136261
	for i in st.unit_count:
		h = ((h ^ st.alive[i]) * 16777619) & 0xFFFFFFFF
		h = ((h ^ st.cell[i]) * 16777619) & 0xFFFFFFFF
		h = ((h ^ int(st.hp[i] * 10.0)) * 16777619) & 0xFFFFFFFF
	h = ((h ^ tick_index) * 16777619) & 0xFFFFFFFF
	return h


# ---------- 内部 ----------

func _build_dynamic_field(mover_team: int) -> void:
	# 我方场的起点是所有敌人，敌方场的起点是所有我方单位
	var source_team: int = TEAM_ENEMY if mover_team == TEAM_ALLY else TEAM_ALLY
	var count: int = 0
	var alive: PackedByteArray = st.alive
	var team: PackedByteArray = st.team
	var cell: PackedInt32Array = st.cell
	var gate_dist: PackedInt32Array = gate_field.dist
	for i in st.unit_count:
		if alive[i] == 1 and team[i] == source_team:
			_sources[count] = cell[i]
			_source_cost[count] = gate_dist[cell[i]] / THREAT_DIVISOR
			count += 1
	if mover_team == TEAM_ALLY:
		ally_field.build(_sources, count, st.occupant, st.team, TEAM_ALLY,
				DistanceField.UNREACHABLE, _source_cost)
	else:
		enemy_field.build(_sources, count, st.occupant, st.team, -1, FIELD_LIMIT)


func _resolve_deaths() -> void:
	for i in st.unit_count:
		if st.alive[i] == 1 and st.hp[i] <= 0.0:
			st.alive[i] = 0
			st.state[i] = BattleState.UnitState.DEAD
			if st.occupant[st.cell[i]] == i:
				st.occupant[st.cell[i]] = -1
			set_target(i, -1)
			st.alive_count[st.team[i]] -= 1


func _check_end() -> void:
	if breach_unit >= 0 and end_on_breach:
		outcome = Outcome.LOSS_BREACH
	elif st.alive_count[TEAM_ENEMY] == 0:
		outcome = Outcome.WIN
	elif time >= DEADLOCK_SECONDS:
		outcome = Outcome.LOSS_DEADLOCK
