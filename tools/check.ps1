param(
    [string]$GodotExe = "",
    [switch]$Windowed
)

# WXAutoRE 一键检查（设计文档 10.4）：
#   1. headless 导入项目
#   2. 跑全部测试（tests/run_all.gd）
#   3. 跑 B1～B3 压测并对照阈值（tests/bench/run_bench.gd）
#   4. 加 -Windowed 时再跑一次窗口压测（会弹出游戏窗口，约 90 秒）
# 用法：powershell -ExecutionPolicy Bypass -File tools\check.ps1 [-GodotExe 路径] [-Windowed]

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Find-Godot {
    param([string]$Manual)
    $candidates = @($Manual, $env:GODOT_EXE, "C:\Godot\Godot_console.exe", "C:\Godot\godot_console.exe")
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command godot_console -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "找不到 Godot。请用 -GodotExe 指定，或设置环境变量 GODOT_EXE。"
}

function Invoke-Step {
    param([string]$Name, [string[]]$GodotArgs)
    Write-Host "[检查] $Name"
    & $script:godot @GodotArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name 未通过（退出码 $LASTEXITCODE）" }
}

$script:godot = Find-Godot $GodotExe
Write-Host "[检查] Godot：$script:godot"

Invoke-Step "导入项目" @("--headless", "--path", $root, "--import")
Invoke-Step "全部测试" @("--headless", "--path", $root, "--script", "res://tests/run_all.gd")
Invoke-Step "压测 B1～B3" @("--headless", "--path", $root, "--script", "res://tests/bench/run_bench.gd", "--", "B1", "B2", "B3")
if ($Windowed) {
    Invoke-Step "窗口压测 B2" @("--path", $root, "--", "--scenario=B2", "--bench")
}

Write-Host "[检查] 全部通过"
