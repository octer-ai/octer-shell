<#
.SYNOPSIS
  配置 Hermes Agent 使用 Octer 自定义大模型，并选中它（Windows / PowerShell 版）。

.DESCRIPTION
  与 set-hermes-model.sh 等价的 Windows 实现。
  关键：Hermes 取凭证时只认「命名的 custom provider」(custom_providers 列表条目)，
  光设 model.* 会报 "No LLM provider configured"。本脚本按 hermes 自己 _save_custom_provider
  的结构，往 config.yaml 写 custom_providers 列表条目 + model 块。

.PARAMETER ApiKey
  Octer 的 API Key（evo_ 开头）。

.PARAMETER Model
  模型名称（可选，缺省 gemini-3-flash-preview）。

.EXAMPLE
  .\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx

.EXAMPLE
  .\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx gemini-3-flash-preview

.NOTES
  若系统禁止运行脚本，用：
    powershell -ExecutionPolicy Bypass -File .\set-hermes-model.ps1 <API_KEY> [MODEL]
#>
param(
  [Parameter(Mandatory = $true, Position = 0, HelpMessage = "用法: .\set-hermes-model.ps1 <API_KEY> [MODEL]")]
  [string]$ApiKey,
  [Parameter(Mandatory = $false, Position = 1)]
  [string]$Model = "gemini-3-flash-preview"
)

$ErrorActionPreference = 'Stop'

# ── 固定部分 ────────────────────────────────────────────
$NAME      = "Octer"
$BASE_URL  = "https://oclaw.octer.ai/v1"  # 接口地址（正式）
$MODEL     = $Model                       # 模型名称（可用第二个参数覆盖）
$MAX_TOKENS = "65536"
# ────────────────────────────────────────────────────────

function Test-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Cmd 'hermes')) {
  Write-Host "X 未找到 hermes CLI（需在装了 hermes 的机器执行）" -ForegroundColor Red
  exit 1
}

$CFG = ((& hermes config path) | Out-String).Trim()
Write-Host "config: $CFG"
if (Test-Path -LiteralPath $CFG) {
  $stamp = Get-Date -Format 'yyyyMMddHHmmss'
  Copy-Item -LiteralPath $CFG -Destination "$CFG.bak.$stamp" -Force
}

# 选一个带 pyyaml 的 python（系统 python 常常没装；hermes 自己的 venv 一定有）。
$HERMES_HOME = if ($CFG) { Split-Path -Parent $CFG } else { Join-Path $env:USERPROFILE '.hermes' }

# 候选解释器：每项是一个「可执行 + 前置参数」组合
$candidates = @(
  @{ Exe = (Join-Path $HERMES_HOME 'hermes-agent\venv\Scripts\python.exe'); Pre = @() },
  @{ Exe = 'py';      Pre = @('-3') },
  @{ Exe = 'python';  Pre = @() },
  @{ Exe = 'python3'; Pre = @() }
)

function Test-PyYaml($exe, $pre) {
  try {
    if ($exe -ne 'py' -and $exe -notmatch '[\\/]' -and -not (Test-Cmd $exe)) { return $false }
    if ($exe -match '[\\/]' -and -not (Test-Path -LiteralPath $exe)) { return $false }
    & $exe @pre -c "import yaml" 2>$null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}

$PY = $null; $PYPRE = @()
foreach ($c in $candidates) {
  if (Test-PyYaml $c.Exe $c.Pre) { $PY = $c.Exe; $PYPRE = $c.Pre; break }
}

if (-not $PY) {
  # 兜底：给系统 python 装 pyyaml（--user，无需管理员）
  Write-Host "! 未找到带 pyyaml 的 python，尝试 pip 安装..." -ForegroundColor Yellow
  foreach ($c in @(@{Exe='py';Pre=@('-3')}, @{Exe='python';Pre=@()}, @{Exe='python3';Pre=@()})) {
    if ($c.Exe -eq 'py' -or (Test-Cmd $c.Exe)) {
      try { & $c.Exe @($c.Pre) -m pip install --user pyyaml 2>$null | Out-Null } catch {}
      if (Test-PyYaml $c.Exe $c.Pre) { $PY = $c.Exe; $PYPRE = $c.Pre; break }
    }
  }
}

if (-not $PY) {
  Write-Host "X 仍找不到带 pyyaml 的 python。手动装一个再重试，例如: py -3 -m pip install pyyaml" -ForegroundColor Red
  exit 1
}
Write-Host ("python: " + ($PY + ' ' + ($PYPRE -join ' ')).Trim())

# provider slug = 名字归一化（小写、空格转 -），custom provider 解析按它匹配
$SLUG = ($NAME.ToLower() -replace ' ', '-')

# ── 与 .sh 版完全一致的 python 改写逻辑（写临时 .py，UTF-8 无 BOM）──
$pyCode = @'
import os, sys, yaml
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
except FileNotFoundError:
    cfg = {}

NAME = os.environ["NAME"]
SLUG = os.environ["SLUG"]
BASE = os.environ["BASE_URL"].rstrip("/")
KEY  = os.environ["API_KEY"]
MODEL = os.environ["MODEL"]
MAXT = int(os.environ["MAX_TOKENS"])

# 1) custom_providers 列表条目（按 base_url 去重，命中则更新）
cps = cfg.get("custom_providers")
if not isinstance(cps, list):
    cps = []
entry = None
for e in cps:
    if isinstance(e, dict) and str(e.get("base_url", "")).rstrip("/") == BASE:
        entry = e; break
if entry is None:
    entry = {}
    cps.append(entry)
entry.update({"name": NAME, "base_url": BASE, "api_key": KEY, "model": MODEL})
cfg["custom_providers"] = cps

# 2) model 块：选中该 custom 端点
m = cfg.get("model")
if not isinstance(m, dict):
    m = {}
m.update({
    "provider": SLUG,        # 关键：按 provider slug 匹配命名 custom provider，而非字面量 "custom"
    "base_url": BASE,
    "default": MODEL,
    "api_key": KEY,
    "max_tokens": MAXT,
})
cfg["model"] = m

# 3) Octer 不支持 fast 模式 —— 关闭 reasoning
a = cfg.get("agent")
if not isinstance(a, dict):
    a = {}
a["reasoning_effort"] = "none"
cfg["agent"] = a

with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)
print("OK config.yaml 已写入 custom_providers[Octer] + model 块")
'@

$pyFile = Join-Path $env:TEMP 'octer_hermes_cfg.py'
[System.IO.File]::WriteAllText($pyFile, $pyCode, (New-Object System.Text.UTF8Encoding $false))

$env:NAME       = $NAME
$env:SLUG       = $SLUG
$env:BASE_URL   = $BASE_URL
$env:API_KEY    = $ApiKey
$env:MODEL      = $MODEL
$env:MAX_TOKENS = $MAX_TOKENS

& $PY @PYPRE $pyFile $CFG
if ($LASTEXITCODE -ne 0) { Write-Host "X 写入 config.yaml 失败" -ForegroundColor Red; exit 1 }

Remove-Item -LiteralPath $pyFile -ErrorAction SilentlyContinue

Write-Host "OK 已配置并选中: $NAME -> $MODEL @ $BASE_URL（已关闭 fast/reasoning）" -ForegroundColor Green

# ── 启用：启动/刷新 gateway 让新模型生效 ─────────────────
Write-Host "~ 启动 hermes gateway..."
& hermes gateway start
& hermes gateway status

Write-Host "-- 当前配置 --"
(& hermes config show) | Select-String -Pattern 'Model:|provider|reasoning'

# ── 自测（最多等 60s）──────────────────────────────────
Write-Host ""
Write-Host '* 自测(最多等 60s): hermes -z "你好"'
$job = Start-Job -ScriptBlock { & hermes -z "你好" 2>&1 }
if (Wait-Job $job -Timeout 60) {
  Receive-Job $job
} else {
  Stop-Job $job
  Write-Host "! 自测超时/失败。配置已写好；卡住多半是端点没响应，手动排查见下方提示。" -ForegroundColor Yellow
}
Remove-Job $job -Force -ErrorAction SilentlyContinue

Write-Host ""
$hint = @"
若 hermes -z 一直卡住，直接 curl 端点看是不是端点本身的问题（PowerShell 里用 curl.exe，单行）：
  curl.exe -sS $BASE_URL/chat/completions -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" -d '{"model":"$MODEL","messages":[{"role":"user","content":"你好"}]}'
"@
Write-Host $hint
