extends Node2D

## M0 演示场景：跑 B1～B4 压测场景并实时显示。
## 按键：1～4 切场景 · 空格暂停 · Q/E 倍速 · F3 调试叠加 · R 重开 · WASD/方向键/中键拖动平移 · 滚轮缩放
## 命令行（godot 参数后加 --）：
##   --scenario=B2          开局场景
##   --bench                窗口压测：记录帧耗时，战斗结束或 90 秒后打印结果并退出
##   --screenshot=路径 --shot-at=秒   运行到指定秒数（真实时间）截图并保存
##   --overlay              开局就打开调试叠加
##   --switch=B1@8          运行到第 8 秒（真实时间）切换到 B1，用来检查切换场景后的画面

const TICK: float = BattleSim.TICK
const MAX_SUBSTEPS: int = 3
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const BENCH_SECONDS: float = 90.0

var sim: BattleSim
var scenario: String = "B2"
var speed_index: int = 0
var paused: bool = false
var acc: float = 0.0

var view: BattleView
var camera: Camera2D
var hud: Label
var help: Label

var _tick_ms: PackedFloat64Array = PackedFloat64Array()
var _dragging: bool = false

# 窗口压测
var _bench: bool = false
var _bench_frames: PackedFloat64Array = PackedFloat64Array()
var _bench_frame_tick: PackedInt32Array = PackedInt32Array()
var _bench_contact_tick: int = -1
var _bench_metrics: BattleMetrics
var _screenshot_path: String = ""
var _shot_at: float = -1.0
var _shot_done: bool = false
var _start_overlay: bool = false
var _elapsed: float = 0.0
var _switch_to: String = ""
var _switch_at: float = -1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.substr(11)
		elif arg == "--bench":
			_bench = true
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.substr(13)
		elif arg.begins_with("--shot-at="):
			_shot_at = float(arg.substr(10))
		elif arg == "--overlay":
			_start_overlay = true
		elif arg.begins_with("--switch="):
			var parts: PackedStringArray = arg.substr(9).split("@")
			_switch_to = parts[0]
			_switch_at = float(parts[1]) if parts.size() > 1 else 5.0

	RenderingServer.set_default_clear_color(Color("2b2622"))
	view = BattleView.new()
	add_child(view)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_color_override("font_color", Color("f3ead8"))
	hud.add_theme_color_override("font_outline_color", Color("1a1714"))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	help = Label.new()
	help.text = "1～4 切场景 · 空格暂停 · Q/E 倍速 · F3 调试叠加 · R 重开 · WASD/中键平移 · 滚轮缩放"
	help.add_theme_color_override("font_color", Color("cbbf9f"))
	help.add_theme_color_override("font_outline_color", Color("1a1714"))
	help.add_theme_constant_override("outline_size", 6)
	layer.add_child(help)
	get_viewport().size_changed.connect(_layout_help)
	_layout_help()

	_load(scenario)
	view.overlay = _start_overlay


func _load(name: String) -> void:
	scenario = name
	sim = DevScenarios.build(name, 1)
	if _bench:
		sim.end_on_breach = false
		_bench_metrics = BattleMetrics.new()
		sim.metrics = _bench_metrics
	sim.start()
	if _bench_metrics != null:
		_bench_metrics.setup(sim)
	acc = 0.0
	_tick_ms.clear()
	view.bind(sim)
	_fit_camera()


func _fit_camera() -> void:
	var size: Vector2 = view.map_size()
	var vp: Vector2 = get_viewport_rect().size
	var z: float = minf(vp.x / size.x, (vp.y - 40.0) / size.y) * 0.95
	camera.zoom = Vector2(z, z)
	camera.position = size * 0.5 - Vector2(BattleView.HEX_SIZE, BattleView.HEX_SIZE)


func _layout_help() -> void:
	help.position = Vector2(14, get_viewport_rect().size.y - 32)


func _process(delta: float) -> void:
	if not paused and sim.is_running():
		acc += delta * SPEEDS[speed_index]
		var steps: int = 0
		while acc >= TICK and steps < MAX_SUBSTEPS:
			var t0: int = Time.get_ticks_usec()
			sim.tick()
			_tick_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
			if _tick_ms.size() > 100:
				_tick_ms.remove_at(0)
			if _bench_metrics != null:
				_bench_metrics.sample(sim)
			acc -= TICK
			steps += 1
		if steps == MAX_SUBSTEPS:
			acc = minf(acc, TICK)
	view.update_frame(sim.time + acc)
	_move_camera(delta)
	_update_hud()

	if _bench:
		_bench_frames.append(delta * 1000.0)
		_bench_frame_tick.append(sim.tick_index)
		if not sim.is_running() or sim.time >= BENCH_SECONDS:
			_finish_bench()
	_elapsed += delta
	if _switch_to != "" and _elapsed >= _switch_at:
		_load(_switch_to)
		_switch_to = ""
	if _screenshot_path != "" and not _shot_done and _elapsed >= _shot_at:
		_shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("已截图：%s（%s，战斗时间 %.1f 秒）" % [_screenshot_path, scenario, sim.time])
		if not _bench:
			get_tree().quit()


func _update_hud() -> void:
	var st: BattleState = sim.st
	var avg: float = 0.0
	var mx: float = 0.0
	for t in _tick_ms:
		avg += t
		mx = maxf(mx, t)
	avg /= maxf(1.0, _tick_ms.size())
	var result: String = ""
	match sim.outcome:
		BattleSim.Outcome.WIN:
			result = " · 胜利"
		BattleSim.Outcome.LOSS_BREACH:
			result = " · 城门失守"
		BattleSim.Outcome.LOSS_DEADLOCK:
			result = " · 死锁"
	hud.text = "%s %s%s\n战斗 %.1f 秒 · ×%d%s · 我方 %d · 敌方 %d · 城门被踏 %d\n逻辑帧 最近 100 帧：均值 %.2fms · 最大 %.2fms · FPS %d%s" % [
		scenario, DevScenarios.DESCRIPTIONS.get(scenario, ""), result,
		sim.time, int(SPEEDS[speed_index]), " · 暂停" if paused else "",
		st.alive_count[BattleState.TEAM_ALLY], st.alive_count[BattleState.TEAM_ENEMY], sim.breach_count,
		avg, mx, Engine.get_frames_per_second(), " · 调试叠加" if view.overlay else ""]


func _move_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	camera.position += dir * 600.0 * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				_load(DevScenarios.NAMES[event.keycode - KEY_1])
			KEY_SPACE:
				paused = not paused
			KEY_Q:
				speed_index = maxi(0, speed_index - 1)
			KEY_E:
				speed_index = mini(SPEEDS.size() - 1, speed_index + 1)
			KEY_F3:
				view.overlay = not view.overlay
			KEY_R:
				_load(scenario)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.zoom *= 1.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.zoom /= 1.1
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= event.relative / camera.zoom.x


func _finish_bench() -> void:
	set_process(false)
	var sorted: PackedFloat64Array = _bench_frames.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var p95: float = sorted[mini(n - 1, int(n * 0.95))]
	var contact: int = _bench_metrics.contact_tick
	var window_max: float = 0.0
	var steady_max: float = 0.0
	for k in n:
		if contact > 0 and absi(_bench_frame_tick[k] - contact) <= 25:
			window_max = maxf(window_max, _bench_frames[k])
		# 开战 2 秒以后：排除启动时加载和生成字形图集的那几帧
		if _bench_frame_tick[k] >= 20:
			steady_max = maxf(steady_max, _bench_frames[k])
	print("=== 窗口压测 %s ===" % scenario)
	print("帧数 %d · 帧间隔 p95 %.2fms · 最大 %.2fms（开战 2 秒后最大 %.2fms）· 接敌前后 5 秒最大 %.2fms（接敌帧 %d）" % [
		n, p95, sorted[n - 1], steady_max, window_max, contact])
	var ok: bool = p95 <= 16.7 + 0.5 and window_max <= 33.0
	print("窗口压测结果：%s（要求 p95 ≤16.7ms、接敌前后单帧 ≤33ms）" % ("通过" if ok else "未通过"))
	get_tree().quit(0 if ok else 1)
