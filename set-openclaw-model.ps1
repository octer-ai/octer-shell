<#
.SYNOPSIS
  把 OpenClaw 切换到 Octer 自定义大模型（OpenAI 兼容）（Windows / PowerShell 版）。

.DESCRIPTION
  与 set-openclaw-model.sh 等价：往 ~/.openclaw/openclaw.json 写自定义 provider
  （models.providers.octer），选中 octer/gpt-5.5（默认模型，可用第二个参数覆盖）为默认，再重启 gateway。
  全程走 openclaw 自带 CLI（config set 带 schema 校验）。

.PARAMETER ApiKey
  Octer 的 API Key（evo_ 开头）。

.PARAMETER Model
  模型名称（可选，缺省 gpt-5.5）。

.EXAMPLE
  .\set-openclaw-model.ps1 evo_xxxxxxxxxxxxxxxx

.EXAMPLE
  .\set-openclaw-model.ps1 evo_xxxxxxxxxxxxxxxx gpt-5.5

.NOTES
  若系统禁止运行脚本，用：
    powershell -ExecutionPolicy Bypass -File .\set-openclaw-model.ps1 <API_KEY> [MODEL]
#>
param(
  [Parameter(Mandatory = $true, Position = 0, HelpMessage = "用法: .\set-openclaw-model.ps1 <API_KEY> [MODEL]")]
  [string]$ApiKey,
  [Parameter(Mandatory = $false, Position = 1)]
  [string]$Model = "gpt-5.5"
)

$ErrorActionPreference = 'Stop'

# ── 固定部分 ────────────────────────────────────────────
$Provider = "octer"
$BaseUrl  = "https://oclaw.octer.ai/v1"  # 接口地址（OpenAI 兼容）
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

# ── 自测（最多等 60s，不通过不影响配置）──────────────────
Write-Host ""
Write-Host '* 自测(最多等 60s): openclaw agent --agent main -m "你好"'
$job = Start-Job -ScriptBlock { & openclaw agent --agent main -m "你好" 2>&1 }
if (Wait-Job $job -Timeout 60) {
  Receive-Job $job
} else {
  Stop-Job $job
  Write-Host '! 自测未通过(不影响配置)。手动验证: openclaw agent --agent main -m "你好" 或 openclaw chat' -ForegroundColor Yellow
}
Remove-Job $job -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "OK 已把 OpenClaw 切到: $ModelId @ $BaseUrl" -ForegroundColor Green
Write-Host "   没有 Key? 在 https://octer.ai/workspace -> Me -> Settings -> API Keys 创建"

$hint = @"
若自测卡住/失败，直接 curl 端点看是不是端点本身的问题（PowerShell 用 curl.exe，单行）：
  curl.exe -sS $BaseUrl/chat/completions -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" -d '{"model":"$Model","messages":[{"role":"user","content":"你好"}]}'
"@
Write-Host ""
Write-Host $hint
