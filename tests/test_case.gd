class_name TestCase
extends RefCounted

## 极简测试基类：方法名以 test_ 开头的都会被 tests/run_all.gd 执行。

var failures: PackedStringArray = PackedStringArray()
var current: String = ""


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s：%s" % [current, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：%s（实际 %s，期望 %s）" % [current, message, str(actual), str(expected)])


func check_contains(errors: PackedStringArray, keyword: String, message: String) -> void:
	for e in errors:
		if e.contains(keyword):
			return
	failures.append("%s：%s（报错里没有\"%s\"：%s）" % [current, message, keyword, "；".join(errors)])
