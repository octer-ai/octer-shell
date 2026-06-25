<#
.SYNOPSIS
  把 OpenClaw 切换到 Octer 自定义大模型（OpenAI 兼容）（Windows / PowerShell 版）。

.DESCRIPTION
  与 set-openclaw-model.sh 等价。占位说明：本机未安装 openclaw，其「自定义模型」的
  确切 config key 尚未最终确认，下面 model.* 按 Hermes 模式推测；若实际 schema 不同
  （例如 providers.octer.* / llm.*），只改这几行 config set 即可。

.PARAMETER ApiKey
  Octer 的 API Key（evo_ 开头）。

.EXAMPLE
  .\set-openclaw-model.ps1 evo_xxxxxxxxxxxxxxxx

.NOTES
  若系统禁止运行脚本，用：
    powershell -ExecutionPolicy Bypass -File .\set-openclaw-model.ps1 <API_KEY>
#>
param(
  [Parameter(Mandatory = $true, Position = 0, HelpMessage = "用法: .\set-openclaw-model.ps1 <API_KEY>")]
  [string]$ApiKey
)

$ErrorActionPreference = 'Stop'

# ── 固定部分 ────────────────────────────────────────────
$Slug    = "octer"
$BaseUrl = "https://octer.ai/api/llm"   # 接口地址（OpenAI 兼容）
$Model   = "Octer-1.0-lite"             # 模型名称
# ────────────────────────────────────────────────────────

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd 'openclaw')) {
  Write-Host "X 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）" -ForegroundColor Red
  exit 1
}

Write-Host "~ 写入自定义模型配置..."
& openclaw config set model.provider $Slug
& openclaw config set model.baseURL  $BaseUrl
& openclaw config set model.apiKey   $ApiKey
& openclaw config set model.model    $Model

Write-Host "~ 重启 gateway 让变更生效..."
& openclaw gateway restart

Write-Host "-- 当前配置 --"
try { & openclaw config get model } catch {}

Write-Host ""
Write-Host "OK 已把 OpenClaw 切到: $Slug -> $Model @ $BaseUrl" -ForegroundColor Green
Write-Host "   没有 Key? 在 https://octer.ai/workspace -> Me -> Settings -> API Keys 创建"
