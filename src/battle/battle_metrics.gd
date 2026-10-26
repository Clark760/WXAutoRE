class_name BattleMetrics
extends RefCounted

## 压测与验收用的统计（设计文档 10.1）。每个逻辑帧结束后调用 sample()。
## 闲置：我方——还有要去打的敌人（迎击：全图有走得到的敌人；驻守：防区附近有敌人），
## 却既没在打、也走不动，超过 2 秒；敌方——冲不动也没在交战，超过 2 秒。
## 防区越界只统计驻守模式的单位。

const IDLE_SECONDS: float = 2.0

var ticks: int = 0
var ally_unit_ticks: int = 0
var ally_idle_ticks: int = 0
var enemy_unit_ticks: int = 0
var enemy_idle_ticks: int = 0
var guard_violations: int = 0
var fire_samples: int = 0
var fire_within_1s: int = 0
var fire_latency_sum: float = 0.0
var fire_latency_max: float = 0.0
## 第一次"全线接敌"的逻辑帧：单帧攻击次数达到总人数的 8%。
var contact_tick: int = -1
var contact_threshold: int = 5


func setup(sim: BattleSim) -> void:
	contact_threshold = maxi(5, int(sim.st.unit_count * 0.08))


func sample(sim: BattleSim) -> void:
	ticks += 1
	var st: BattleState = sim.st
	var blocked: int = BattleState.UnitState.BLOCKED
	for i in st.unit_count:
		if st.alive[i] == 0:
			continue
		var idle: bool = st.state[i] == blocked and st.blocked_time[i] >= IDLE_SECONDS
		if st.team[i] == BattleState.TEAM_ALLY:
			ally_unit_ticks += 1
			if idle:
				ally_idle_ticks += 1
			if st.mode[i] == BattleState.MODE_GUARD \
					and sim.map.distance(st.home[i], st.cell[i]) > st.guard_radius[i]:
				guard_violations += 1
		else:
			enemy_unit_ticks += 1
			if idle:
				enemy_idle_ticks += 1
	if contact_tick < 0 and sim.attacks_this_tick >= contact_threshold:
		contact_tick = sim.tick_index


func record_fire_latency(seconds: float) -> void:
	fire_samples += 1
	fire_latency_sum += seconds
	fire_latency_max = maxf(fire_latency_max, seconds)
	if seconds <= 1.0 + 0.0001:
		fire_within_1s += 1


func ally_idle_ratio() -> float:
	return float(ally_idle_ticks) / maxf(1.0, float(ally_unit_ticks))


func enemy_idle_ratio() -> float:
	return float(enemy_idle_ticks) / maxf(1.0, float(enemy_unit_ticks))


func fire_within_1s_ratio() -> float:
	if fire_samples == 0:
		return 1.0
	return float(fire_within_1s) / float(fire_samples)
