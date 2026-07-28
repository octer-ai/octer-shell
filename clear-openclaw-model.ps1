<#
.SYNOPSIS
  清除 OpenClaw 里的 Octer 自定义模型 provider，恢复到默认（Windows / PowerShell 版）。

.DESCRIPTION
  与 clear-openclaw-model.sh 等价：openclaw config unset models.providers.octer-beta，再重启 gateway。

.EXAMPLE
  .\clear-openclaw-model.ps1

.NOTES
  若系统禁止运行脚本，用：
    powershell -ExecutionPolicy Bypass -File .\clear-openclaw-model.ps1
#>

$ErrorActionPreference = 'Stop'

$Provider = "octer-beta"

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd 'openclaw')) {
  Write-Host "X 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）" -ForegroundColor Red
  exit 1
}

Write-Host "~ 删除 provider models.providers.$Provider..."
try { & openclaw config unset "models.providers.$Provider" } catch { Write-Host "i 未发现该 provider（可能已清除）" }

Write-Host "~ 重启 gateway 让变更生效..."
try { & openclaw gateway restart } catch {}

Write-Host "-- 当前模型状态 --"
try { & openclaw models status } catch {}

Write-Host ""
Write-Host "OK 清除完成。若默认模型原来指向 $Provider，请重新选: openclaw models set <model>（或 openclaw onboard）" -ForegroundColor Green
Write-Host "   想恢复 Octer 模型，重新跑 .\set-openclaw-model.ps1 <API_KEY>"
