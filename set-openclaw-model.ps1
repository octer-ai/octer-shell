<#
.SYNOPSIS
  把 OpenClaw 切换到 Octer 自定义大模型（OpenAI 兼容）（Windows / PowerShell 版）。

.DESCRIPTION
  与 set-openclaw-model.sh 等价：往 ~/.openclaw/openclaw.json 写自定义 provider
  （models.providers.octer），选中 octer/Octer-1.0-lite 为默认，再重启 gateway。
  全程走 openclaw 自带 CLI（config set 带 schema 校验）。

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
$Provider = "octer"
$BaseUrl  = "https://octer.ai/api/llm"   # 接口地址（OpenAI 兼容）
$Model    = "Octer-1.0-lite"             # 模型名称
$ModelId  = "$Provider/$Model"           # model id 形如 provider/model
# ────────────────────────────────────────────────────────

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd 'openclaw')) {
  Write-Host "X 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）" -ForegroundColor Red
  exit 1
}

# provider 配置 JSON（手拼以保证单元素 models 数组形状，避开 PS5.1 的数组解包坑）
$json = '{"baseUrl":"' + $BaseUrl + '","apiKey":"' + $ApiKey + '","auth":"api-key","api":"openai-completions","models":[{"id":"' + $Model + '","name":"' + $Model + '"}]}'

Write-Host "~ 写入 provider $Provider（$Model @ $BaseUrl）..."
& openclaw config set "models.providers.$Provider" $json --strict-json --merge

Write-Host "~ 选中默认模型 $ModelId..."
& openclaw models set $ModelId

Write-Host "~ 重启 gateway 让变更生效..."
& openclaw gateway restart

Write-Host "-- 当前模型状态 --"
try { & openclaw models status } catch {}

Write-Host ""
Write-Host "OK 已把 OpenClaw 切到: $ModelId @ $BaseUrl" -ForegroundColor Green
Write-Host "   没有 Key? 在 https://octer.ai/workspace -> Me -> Settings -> API Keys 创建"
