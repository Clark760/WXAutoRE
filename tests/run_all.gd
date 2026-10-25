extends SceneTree

## 跑全部单元测试和场景测试：godot --headless --path . --script res://tests/run_all.gd
## 任一测试失败，退出码为 1。

const DIRS: PackedStringArray = ["res://tests/unit", "res://tests/scenario"]


func _initialize() -> void:
	var total: int = 0
	var failed: int = 0
	for dir in DIRS:
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		files.sort()
		for file in files:
			if not file.ends_with(".gd"):
				continue
			var script: Script = load(dir + "/" + file)
			var suite: TestCase = script.new()
			for m in suite.get_method_list():
				var method: String = m["name"]
				if not method.begins_with("test_"):
					continue
				suite.current = method
				var before: int = suite.failures.size()
				suite.call(method)
				total += 1
				if suite.failures.size() > before:
					failed += 1
					print("✗ %s · %s" % [file.get_basename(), method])
					for k in range(before, suite.failures.size()):
						print("    " + suite.failures[k])
				else:
					print("✓ %s · %s" % [file.get_basename(), method])
	print("测试：%d 个，失败 %d 个" % [total, failed])
	quit(1 if failed > 0 else 0)
