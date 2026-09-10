[CmdletBinding()]
param(
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-SdkRoot {
  if ($env:DEVECO_SDK_HOME -and (Test-Path -LiteralPath $env:DEVECO_SDK_HOME)) {
    return (Resolve-Path -LiteralPath $env:DEVECO_SDK_HOME).Path
  }

  $localProperties = Join-Path $projectRoot 'local.properties'
  if (Test-Path -LiteralPath $localProperties) {
    $line = Get-Content -LiteralPath $localProperties |
      Where-Object { $_ -match '^sdk\.dir=' } |
      Select-Object -First 1
    if ($line) {
      $candidate = $line.Substring('sdk.dir='.Length).Replace('\\:', ':').Replace('\\\\', '\')
      if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
      }
    }
  }

  $uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  $studio = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq 'DevEco Studio' -and $_.InstallLocation } |
    Select-Object -First 1
  if ($studio) {
    $candidate = Join-Path $studio.InstallLocation 'sdk'
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  $candidate = Join-Path $env:ProgramFiles 'Huawei\DevEco Studio\sdk'
  if (Test-Path -LiteralPath $candidate) {
    return (Resolve-Path -LiteralPath $candidate).Path
  }
  throw 'DevEco SDK not found. Set DEVECO_SDK_HOME or create local.properties from the example.'
}

$sdkRoot = Resolve-SdkRoot
$studioRoot = Split-Path -Parent $sdkRoot
$ohpm = Join-Path $studioRoot 'tools\ohpm\bin\ohpm.bat'
$hvigor = Join-Path $studioRoot 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path -LiteralPath $hvigor)) {
  throw "hvigorw.bat not found at $hvigor"
}

Push-Location $projectRoot
try {
  if (-not $SkipInstall) {
    if (-not (Test-Path -LiteralPath $ohpm)) {
      throw "ohpm.bat not found at $ohpm"
    }
    & $ohpm install --all --lockfile_stable_order
    if ($LASTEXITCODE -ne 0) {
      throw "ohpm install failed with exit code $LASTEXITCODE"
    }
  }

  $env:DEVECO_SDK_HOME = $sdkRoot
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $buildOutput = & $hvigor assembleHap --mode module -p product=default -p module=entry@default --no-daemon 2>&1
  $buildExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  $buildOutput | ForEach-Object { Write-Host $_ }
  if ($buildExitCode -ne 0) {
    throw "HarmonyOS build failed with exit code $buildExitCode"
  }
  if (($buildOutput | Out-String) -match 'ArkTS:WARN File:') {
    throw 'HarmonyOS build emitted ArkTS warnings. Add a real compatibility path before updating the checks.'
  }
} finally {
  Pop-Location
}
