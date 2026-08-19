<#
.SYNOPSIS
  Configure Hermes Agent to use the Octer Chat Completions API.
.DESCRIPTION
  Writes one canonical custom:octer provider, stores the API key in Hermes'
  .env file, reloads the Gateway, and runs a 60-second end-to-end self-test.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$ApiKey,
  [Parameter(Mandatory = $false, Position = 1)]
  [string]$Model = "",
  [Parameter(Mandatory = $false, Position = 2)]
  [string]$BaseUrl = "https://oclaw.octer.ai/v1"
)

$ErrorActionPreference = 'Stop'

if ($ApiKey -notmatch '^evo_[A-Za-z0-9]{26,}$') {
  Write-Error 'API Key 必须以 evo_ 开头，且长度至少 30 个字符'
  exit 2
}

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

function Select-OcterModel([string]$Passed) {
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
  $number = 0
  if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $Models.Count) {
    return $Models[$number - 1]
  }
  Write-Host "! 无效输入 '$choice'，使用默认 $DefaultModel" -ForegroundColor Yellow
  return $DefaultModel
}

function Test-Command($Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'hermes')) {
  Write-Error '未找到 hermes CLI（需在装了 Hermes 的机器执行）'
  exit 1
}

$SelectedModel = Select-OcterModel $Model
Write-Host "-> 选定模型: $SelectedModel"

$Helper = Join-Path $PSScriptRoot 'hermes_config.py'
if (-not (Test-Path -LiteralPath $Helper)) {
  $HelperUrl = if ($env:OCTER_HERMES_CONFIG_URL) {
    $env:OCTER_HERMES_CONFIG_URL
  } else {
    'https://raw.githubusercontent.com/octer-ai/octer-shell/refs/heads/master/hermes_config.py'
  }
  $Helper = Join-Path ([IO.Path]::GetTempPath()) ("octer-hermes-config-{0}.py" -f [guid]::NewGuid())
  Write-Host 'v 下载共享配置器...'
  Invoke-WebRequest -UseBasicParsing -Uri $HelperUrl -OutFile $Helper
}

$ConfigPath = ((& hermes config path) | Out-String).Trim()
$EnvPath = ((& hermes config env-path) | Out-String).Trim()
$HermesHome = Split-Path -Parent $ConfigPath
$HermesBin = (Get-Command hermes).Source
Write-Host "config: $ConfigPath"
Write-Host "env:    $EnvPath"

$Candidates = @(
  @{ Exe = (Join-Path $HermesHome 'hermes-agent\venv\Scripts\python.exe'); Pre = @() },
  @{ Exe = 'py'; Pre = @('-3') },
  @{ Exe = 'python'; Pre = @() },
  @{ Exe = 'python3'; Pre = @() }
)

function Test-PyYaml($Exe, $Pre) {
  try {
    if ($Exe -match '[\\/]' -and -not (Test-Path -LiteralPath $Exe)) { return $false }
    if ($Exe -notmatch '[\\/]' -and $Exe -ne 'py' -and -not (Test-Command $Exe)) { return $false }
    & $Exe @Pre -c 'import yaml' 2>$null
    return $LASTEXITCODE -eq 0
  } catch { return $false }
}

$Python = $null
$PythonPrefix = @()
foreach ($Candidate in $Candidates) {
  if (Test-PyYaml $Candidate.Exe $Candidate.Pre) {
    $Python = $Candidate.Exe
    $PythonPrefix = $Candidate.Pre
    break
  }
}
if (-not $Python) {
  Write-Error '找不到带 PyYAML 的 Python；请先修复 Hermes 自带 venv'
  exit 1
}
Write-Host ("python: " + ($Python + ' ' + ($PythonPrefix -join ' ')).Trim())

& $Python @PythonPrefix -c 'import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])' $Helper
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$ModelsCsv = $Models -join ','
$ApiKey | & $Python @PythonPrefix $Helper set `
  --config $ConfigPath `
  --env $EnvPath `
  --base-url $BaseUrl `
  --model $SelectedModel `
  --models-csv $ModelsCsv `
  --max-tokens 65536
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$PluginManifest = Join-Path $HermesHome 'plugins\platforms\octer\plugin.yaml'
if (Test-Path -LiteralPath $PluginManifest) {
  Write-Host '~ 检查已安装的 Octer 平台插件...'
  & hermes plugins doctor platforms/octer
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & hermes plugins enable platforms/octer
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host '~ 完整重载 Hermes Gateway...'
& hermes gateway stop
& hermes gateway start
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& hermes gateway status
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '-- 当前配置 --'
(& hermes config show) | Select-String -Pattern 'Model:|provider|reasoning'

Write-Host ''
Write-Host '* 自测（最多 60s）: hermes -z "请只回复 OK"'
& $Python @PythonPrefix $Helper self-test --hermes-bin $HermesBin --timeout 60
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'OK Hermes + Octer Chat Completions API 自测通过' -ForegroundColor Green
