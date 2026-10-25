class_name AllyAI
extends RefCounted

## 我方驻守行为（设计文档 6.5）。
## - 防区：以部署格为中心、guard_radius 格以内；单位永远不离开防区。
## - 迎战范围：从部署格出发，到最近敌人的路径代价 ≤ 防区半径 + 射程。
## - 选目标：只打射程内的敌人。近战打相邻的（攻击它的人更少 → 血更低）；
##   远程打离城门最近的（城门场的值最小），这是"漏一个就输"的核心。
## - 移动：射程内没有敌人但在迎战范围内时，沿我方动态场往敌人走；迎战范围内没有敌人就回部署格。

const RETARGET_INTERVAL: float = 1.0
const SIDESTEP_COOLDOWN: float = 0.5

const ENEMY: int = BattleState.TEAM_ENEMY

## 只在 BattleSim.tick() 期间有值（见 BattleSim.tick 的说明）。
var sim: BattleSim
var map: BattleMap
var st: BattleState
var buckets: UnitBuckets
var field: DistanceField
var gate_dist: PackedInt32Array

var cell: PackedInt32Array
var home: PackedInt32Array
var target: PackedInt32Array
var alive: PackedByteArray
var team: PackedByteArray
var state: PackedByteArray
var flags: PackedByteArray
var attack_range: PackedInt32Array
var guard_radius: PackedInt32Array
var attackers: PackedInt32Array
var occupant: PackedInt32Array
var hp: PackedFloat32Array
var attack_cd: PackedFloat32Array
var move_cd: PackedFloat32Array
var retarget_cd: PackedFloat32Array
var sidestep_cd: PackedFloat32Array
var blocked_time: PackedFloat32Array
var range_since: PackedFloat32Array
var neighbors: PackedInt32Array
var walk: PackedByteArray


func bind(p_sim: BattleSim) -> void:
	map = p_sim.map
	st = p_sim.st
	buckets = p_sim.buckets
	field = p_sim.ally_field
	gate_dist = p_sim.gate_field.dist
	cell = st.cell
	home = st.home
	target = st.target
	alive = st.alive
	team = st.team
	state = st.state
	flags = st.flags
	attack_range = st.attack_range
	guard_radius = st.guard_radius
	attackers = st.attackers
	occupant = st.occupant
	hp = st.hp
	attack_cd = st.attack_cd
	move_cd = st.move_cd
	retarget_cd = st.retarget_cd
	sidestep_cd = st.sidestep_cd
	blocked_time = st.blocked_time
	range_since = st.range_since
	neighbors = map.neighbors
	walk = map.walk_ally


func step(i: int) -> void:
	var dt: float = BattleSim.TICK
	attack_cd[i] = maxf(attack_cd[i] - dt, 0.0)
	move_cd[i] = maxf(move_cd[i] - dt, 0.0)
	retarget_cd[i] = maxf(retarget_cd[i] - dt, 0.0)
	sidestep_cd[i] = maxf(sidestep_cd[i] - dt, 0.0)

	var c: int = cell[i]
	var rng: int = attack_range[i]

	# 1. 射程内有敌人就打
	var t: int = target[i]
	if t >= 0 and (alive[t] == 0 or map.distance(c, cell[t]) > rng):
		sim.set_target(i, -1)
		t = -1
	if t < 0 or retarget_cd[i] <= 0.0:
		var nt: int = _pick_in_range(i, c, rng)
		if nt >= 0:
			sim.set_target(i, nt)
			t = nt
		retarget_cd[i] = RETARGET_INTERVAL
	if t >= 0:
		if range_since[i] == -1.0 and (flags[i] & BattleState.FLAG_RANGED) != 0:
			range_since[i] = sim.time
		state[i] = BattleState.UnitState.ATTACKING
		blocked_time[i] = 0.0
		if attack_cd[i] <= 0.0:
			sim.attack(i, t)
		return
	range_since[i] = -1.0

	# 2. 迎战范围内有敌人：沿我方动态场往敌人走，但不出防区
	var h: int = home[i]
	var radius: int = guard_radius[i]
	if field.dist[h] <= radius + rng:
		if move_cd[i] > 0.0:
			state[i] = BattleState.UnitState.MOVING
			return
		if _advance_in_zone(i, c, h, radius):
			state[i] = BattleState.UnitState.MOVING
			blocked_time[i] = 0.0
			return
		blocked_time[i] += dt
		state[i] = BattleState.UnitState.BLOCKED
		return

	# 3. 迎战范围内没有敌人：回部署格
	blocked_time[i] = 0.0
	if c == h:
		state[i] = BattleState.UnitState.GUARD
		return
	state[i] = BattleState.UnitState.RETURNING
	if move_cd[i] <= 0.0:
		_step_toward(i, c, h)


## 在射程内选目标；没有返回 -1。
func _pick_in_range(i: int, c: int, rng: int) -> int:
	var best: int = -1
	if rng <= 1:
		# 近战：看 6 个相邻格
		var base: int = c * 6
		for k in 6:
			var n: int = neighbors[base + k]
			if n < 0:
				continue
			var u: int = occupant[n]
			if u < 0 or team[u] != ENEMY:
				continue
			if best < 0 or attackers[u] < attackers[best] \
					or (attackers[u] == attackers[best] and hp[u] < hp[best]):
				best = u
		return best

	# 远程：射程内离城门最近的
	var count: int = buckets.gather(ENEMY, c, rng)
	var res: PackedInt32Array = buckets.result
	var best_gate: int = 1 << 30
	for k in count:
		var u: int = res[k]
		var g: int = gate_dist[cell[u]]
		if best < 0 or g < best_gate \
				or (g == best_gate and (attackers[u] < attackers[best] \
				or (attackers[u] == attackers[best] and hp[u] < hp[best]))):
			best = u
			best_gate = g
	return best


## 沿我方动态场往敌人方向走一格，不离开防区；必要时侧移。
func _advance_in_zone(i: int, c: int, h: int, radius: int) -> bool:
	var d_arr: PackedInt32Array = field.dist
	var cur: int = d_arr[c]
	var best: int = -1
	var best_d: int = cur
	var side: int = -1
	var rot: int = (i + sim.tick_index) % 6
	var base: int = c * 6
	for kk in 6:
		var n: int = neighbors[base + (rot + kk) % 6]
		if n < 0 or walk[n] == 0 or occupant[n] >= 0:
			continue
		if map.distance(h, n) > radius:
			continue
		var dn: int = d_arr[n]
		if dn < best_d:
			best_d = dn
			best = n
		elif dn == cur and side < 0:
			side = n
	if best < 0 and side >= 0 and sidestep_cd[i] <= 0.0:
		best = side
		sidestep_cd[i] = SIDESTEP_COOLDOWN
	if best < 0:
		return false
	sim.move_unit(i, best)
	return true


## 按 Hex 距离朝目标格走一格（回部署格用）。
func _step_toward(i: int, c: int, goal: int) -> bool:
	var cur: int = map.distance(c, goal)
	var best: int = -1
	var best_d: int = cur
	var rot: int = (i + sim.tick_index) % 6
	var base: int = c * 6
	for kk in 6:
		var n: int = neighbors[base + (rot + kk) % 6]
		if n < 0 or walk[n] == 0 or occupant[n] >= 0:
			continue
		var dn: int = map.distance(n, goal)
		if dn < best_d:
			best_d = dn
			best = n
	if best < 0:
		return false
	sim.move_unit(i, best)
	return true
