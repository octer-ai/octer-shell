<#
.SYNOPSIS
  清除 OpenClaw 里的 Octer 自定义大模型配置，恢复默认（Windows / PowerShell 版）。

.DESCRIPTION
  与 clear-openclaw-model.sh 等价：改 ~/.openclaw/openclaw.json，在 model.baseURL 命中 octer 时
  删掉 model.* 里的 octer 相关项，备份后 openclaw gateway restart。
  占位说明同 set 脚本：本机未装 openclaw，确切 config key 以实际 schema 为准；
  若不是 model.*（如 providers.octer.* / llm.*），只改下面的 key 判断即可。

.EXAMPLE
  .\clear-openclaw-model.ps1

.NOTES
  若系统禁止运行脚本，用：
    powershell -ExecutionPolicy Bypass -File .\clear-openclaw-model.ps1
#>
$ErrorActionPreference = 'Stop'

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd 'openclaw')) {
  Write-Host "X 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）" -ForegroundColor Red
  exit 1
}

$cfg = if ($env:OPENCLAW_CONFIG) { $env:OPENCLAW_CONFIG } else { Join-Path $HOME ".openclaw/openclaw.json" }
Write-Host "config: $cfg"

if (Test-Path $cfg) {
  Copy-Item $cfg "$cfg.bak.$(Get-Date -Format yyyyMMddHHmmss)" -Force
  $json = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($json.model) {
    $blob = "$($json.model.baseURL)$($json.model.base_url)$($json.model.provider)".ToLower()
    if ($blob -match 'octer') {
      foreach ($k in 'provider', 'baseURL', 'base_url', 'apiKey', 'api_key', 'model') {
        if ($json.model.PSObject.Properties.Name -contains $k) { $json.model.PSObject.Properties.Remove($k) }
      }
      Write-Host "OK openclaw.json 已清除 model.* 里的 Octer 配置" -ForegroundColor Green
    } else {
      Write-Host "i model.* 未指向 octer，未改动"
    }
  } else {
    Write-Host "i 未发现 model.* 配置，跳过"
  }
  ($json | ConvertTo-Json -Depth 20) | Set-Content $cfg -Encoding UTF8
} else {
  Write-Host "! 未找到 $cfg，跳过 config 清理" -ForegroundColor Yellow
}

Write-Host "~ 重启 openclaw gateway..."
try { & openclaw gateway restart } catch {}

Write-Host "-- 当前配置 --"
try { & openclaw config get model } catch {}

Write-Host ""
Write-Host "OK 清除完成。重新选模型: openclaw onboard（或 openclaw setup）" -ForegroundColor Green
Write-Host "   想恢复 Octer 模型，重新跑 .\set-openclaw-model.ps1 <API_KEY>"
