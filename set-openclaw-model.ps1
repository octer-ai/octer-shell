<#
.SYNOPSIS
  把 OpenClaw 切换到 Octer 自定义大模型（OpenAI 兼容）（Windows / PowerShell 版）。

.DESCRIPTION
  与 set-openclaw-model.sh 等价：往 ~/.openclaw/openclaw.json 写自定义 provider
  （models.providers.octer），选中所选模型为默认，再重启 gateway。
  全程走 openclaw 自带 CLI（config set 带 schema 校验）。

.PARAMETER ApiKey
  Octer 的 API Key（evo_ 开头）。

.PARAMETER Model
  模型名称（可选）：不传则弹交互式菜单让你从支持列表里选（默认 gpt-5.5）；
  也可直接把模型名作为第二个参数传入跳过菜单。

.PARAMETER BaseUrl
  OpenAI 兼容代理地址；不传时使用正式 OClaw 地址。

.EXAMPLE
  .\set-openclaw-model.ps1 evo_xxxxxxxxxxxxxxxx

.EXAMPLE
  .\set-openclaw-model.ps1 evo_xxxxxxxxxxxxxxxx gemini-3-flash-preview

.NOTES
  若系统禁止运行脚本，用：
    powershell -ExecutionPolicy Bypass -File .\set-openclaw-model.ps1 <API_KEY> [MODEL] [BASE_URL]
#>
param(
  [Parameter(Mandatory = $true, Position = 0, HelpMessage = "用法: .\set-openclaw-model.ps1 <API_KEY> [MODEL] [BASE_URL]")]
  [string]$ApiKey,
  [Parameter(Mandatory = $false, Position = 1)]
  [string]$Model = "",
  [Parameter(Mandatory = $false, Position = 2)]
  [string]$BaseUrl = "https://oclaw.octer.ai/v1"
)

$ErrorActionPreference = 'Stop'

# ── 固定部分 ────────────────────────────────────────────
$Provider = "octer"
$BaseUrl  = $BaseUrl.TrimEnd('/')
# ────────────────────────────────────────────────────────

# ── 支持的模型列表（下拉选择用；第一项为默认）─────────────
$Models = @(
  'gpt-5.5',
  'gpt-5.6-sol',
  'gpt-5.6-terra',
  'gpt-5.6-luna',
  'claude-opus-4-8',
  'gemini-3.1-pro-preview',
  'gemini-3-flash-preview',
  'gemini-3.5-flash',
  'deepseek-v4-flash',
  'deepseek-v4-pro',
  'glm-5.2',
  'qwen3.7-plus',
  'qwen3.7-max',
  'qwen3.8-max',
  'MiniMax-M3'
)
$DefaultModel = $Models[0]

# 决定模型：① 传了 -Model 就用它；② 否则交互式弹「下拉」菜单；
# ③ 非交互环境（输入被重定向/CI）回退默认。
function Select-Model([string]$Passed) {
  if ($Passed) {
    if ($Models -notcontains $Passed) {
      Write-Host "! '$Passed' 不在内置列表里，仍按你指定的使用。" -ForegroundColor Yellow
    }
    return $Passed
  }
  if ([Console]::IsInputRedirected) {
    Write-Host "（非交互环境，未传 Model，使用默认 $DefaultModel）"
    return $DefaultModel
  }
  Write-Host "请选择要使用的模型（直接回车用默认 $DefaultModel）："
  for ($i = 0; $i -lt $Models.Count; $i++) {
    $label = $Models[$i]
    if ($label -eq $DefaultModel) { $label = "$label（默认）" }
    Write-Host ("  {0}) {1}" -f ($i + 1), $label)
  }
  $choice = Read-Host ("输入编号 [1-{0}]" -f $Models.Count)
  if ([string]::IsNullOrWhiteSpace($choice)) { return $DefaultModel }
  $n = 0
  if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $Models.Count) {
    return $Models[$n - 1]
  }
  Write-Host "! 无效输入 '$choice'，使用默认 $DefaultModel" -ForegroundColor Yellow
  return $DefaultModel
}

$Model = Select-Model $Model
Write-Host "-> 选定模型: $Model"
$ModelId  = "$Provider/$Model"           # model id 形如 provider/model
# ────────────────────────────────────────────────────────

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd 'openclaw')) {
  Write-Host "X 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）" -ForegroundColor Red
  exit 1
}

# provider 配置 JSON（手拼以避开 PS5.1 的数组解包坑）
# 注册全部支持的模型，让客户端下拉能列出所有模型；models set 再选其中一个为默认。
# 若用户显式传了列表外的模型，也一并注册，保证 models set 能选中它。
$allModels = @($Models)
if ($allModels -notcontains $Model) { $allModels += $Model }
$modelsJson = ($allModels | ForEach-Object { '{"id":"' + $_ + '","name":"' + $_ + '"}' }) -join ','
$json = '{"baseUrl":"' + $BaseUrl + '","apiKey":"' + $ApiKey + '","auth":"api-key","api":"openai-completions","models":[' + $modelsJson + ']}'

Write-Host "~ 写入 provider $Provider（默认 $Model，共 $($allModels.Count) 个模型 @ $BaseUrl）..."
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
Write-Host "   没有 Key? 打开 https://octer.ai/workspace/o/?next=/o -> OClaw 页面复制或重置 API Key"

$hint = @"
若自测卡住/失败，直接 curl 端点看是不是端点本身的问题（PowerShell 用 curl.exe，单行）：
  curl.exe -sS $BaseUrl/chat/completions -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" -d '{"model":"$Model","messages":[{"role":"user","content":"你好"}]}'
"@
Write-Host ""
Write-Host $hint
