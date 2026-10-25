extends SceneTree

## 压测：headless 跑 B1～B4，输出逻辑帧耗时、闲置率、远程开火延迟等，并按设计文档 10.1 的阈值判定。
## 用法：godot --headless --path . --script res://tests/bench/run_bench.gd -- B1 B2 [--seed=1]
## 不带场景名时跑全部。任一有阈值的场景不达标，退出码为 1。

const MAX_SECONDS: float = 300.0

## 设计文档 10.1。B4 只记录不判定。
const THRESHOLDS: Dictionary = {
	"B1": {"ally_idle": 0.05},
	"B2": {"avg_ms": 4.0, "p99_ms": 8.0, "max_ms": 12.0, "ally_idle": 0.10, "fire_1s": 0.95, "guard": 0},
	"B3": {"avg_ms": 4.0, "p99_ms": 8.0, "max_ms": 12.0},
}


func _initialize() -> void:
	var names: Array[String] = []
	var seed_value: int = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		else:
			names.append(arg)
	if names.is_empty():
		for n in DevScenarios.NAMES:
			names.append(n)

	var failed: bool = false
	for name in names:
		var report: Dictionary = run_one(name, seed_value)
		if report.is_empty():
			failed = true
			continue
		print_report(name, report)
		if not check(name, report):
			failed = true
	print("压测结果：%s" % ("未通过" if failed else "通过"))
	quit(1 if failed else 0)


func run_one(name: String, seed_value: int) -> Dictionary:
	var sim: BattleSim = DevScenarios.build(name, seed_value)
	if sim == null:
		return {}
	sim.end_on_breach = false
	var metrics := BattleMetrics.new()
	sim.metrics = metrics
	var t0: int = Time.get_ticks_usec()
	sim.start()
	var start_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	metrics.setup(sim)

	var times := PackedFloat64Array()
	var max_ticks: int = int(MAX_SECONDS / BattleSim.TICK)
	while sim.is_running() and sim.tick_index < max_ticks:
		var a: int = Time.get_ticks_usec()
		sim.tick()
		times.append((Time.get_ticks_usec() - a) / 1000.0)
		metrics.sample(sim)

	var sorted: PackedFloat64Array = times.duplicate()
	sorted.sort()
	var total: float = 0.0
	for t in times:
		total += t
	var count: int = maxi(1, times.size())
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))] if sorted.size() > 0 else 0.0
	# "全线接敌"前后 5 秒（各 25 个逻辑帧）内的最大逻辑帧
	var contact_max: float = 0.0
	if metrics.contact_tick > 0:
		for k in range(maxi(0, metrics.contact_tick - 26), mini(times.size(), metrics.contact_tick + 25)):
			contact_max = maxf(contact_max, times[k])

	var outcome_text: String = {
		BattleSim.Outcome.RUNNING: "未结束",
		BattleSim.Outcome.WIN: "敌人全部消失",
		BattleSim.Outcome.LOSS_BREACH: "城门失守",
		BattleSim.Outcome.LOSS_DEADLOCK: "死锁（300 秒未结束）",
	}[sim.outcome]
	if sim.outcome == BattleSim.Outcome.RUNNING and sim.tick_index >= max_ticks:
		outcome_text = "死锁（300 秒未结束）"

	return {
		"units": sim.st.unit_count,
		"start_ms": start_ms,
		"ticks": times.size(),
		"seconds": sim.time,
		"avg_ms": total / count,
		"p99_ms": p99,
		"max_ms": sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0,
		"contact_tick": metrics.contact_tick,
		"contact_max_ms": contact_max,
		"ally_idle": metrics.ally_idle_ratio(),
		"enemy_idle": metrics.enemy_idle_ratio(),
		"fire_1s": metrics.fire_within_1s_ratio(),
		"fire_samples": metrics.fire_samples,
		"fire_avg_s": metrics.fire_latency_sum / maxf(1.0, metrics.fire_samples),
		"guard": metrics.guard_violations,
		"breaches": sim.breach_count,
		"ally_alive": sim.st.alive_count[BattleState.TEAM_ALLY],
		"enemy_alive": sim.st.alive_count[BattleState.TEAM_ENEMY],
		"outcome": outcome_text,
		"deadlock": outcome_text.begins_with("死锁"),
		"hash": sim.state_hash(),
	}


func print_report(name: String, r: Dictionary) -> void:
	print("=== %s %s ===" % [name, DevScenarios.DESCRIPTIONS.get(name, "")])
	print("单位 %d · 战斗 %.1f 秒（%d 帧）· 结果：%s · 城门被踏 %d 次 · 剩余 我方 %d / 敌方 %d" % [
		r.units, r.seconds, r.ticks, r.outcome, r.breaches, r.ally_alive, r.enemy_alive])
	print("逻辑帧：均值 %.3fms · p99 %.3fms · 最大 %.3fms · 开战准备 %.1fms · 接敌前后 5 秒最大 %.3fms（接敌帧 %d）" % [
		r.avg_ms, r.p99_ms, r.max_ms, r.start_ms, r.contact_max_ms, r.contact_tick])
	print("索敌：我方闲置率 %.1f%% · 敌方闲置率 %.1f%% · 远程 1 秒内开火 %.1f%%（%d 次，平均 %.2f 秒）· 越出防区 %d 帧" % [
		r.ally_idle * 100.0, r.enemy_idle * 100.0, r.fire_1s * 100.0, r.fire_samples, r.fire_avg_s, r.guard])
	print("状态哈希 %d" % r.hash)


func check(name: String, r: Dictionary) -> bool:
	var ok: bool = true
	if r.deadlock and name != "B4":
		print("  ✗ 出现死锁")
		ok = false
	var limits: Dictionary = THRESHOLDS.get(name, {})
	for key in limits:
		var limit = limits[key]
		var value = r[key]
		var pass_check: bool = value >= limit if key == "fire_1s" else value <= limit
		if not pass_check:
			print("  ✗ %s = %s，要求 %s %s" % [key, str(value), "≥" if key == "fire_1s" else "≤", str(limit)])
			ok = false
	if ok and not limits.is_empty():
		print("  ✓ 达标")
	return ok
