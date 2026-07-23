$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$releaseDir = Join-Path $root "release"
$flutter = $env:FLUTTER_BIN
$iscc = $env:ISCC_BIN
$supabaseUrl = if ([string]::IsNullOrWhiteSpace($env:SUPABASE_URL)) { "https://yilegxcnokndozhwpwlf.supabase.co" } else { $env:SUPABASE_URL }
$supabasePublishableKey = if ([string]::IsNullOrWhiteSpace($env:SUPABASE_PUBLISHABLE_KEY)) { "sb_publishable_nl-KDIS_lRVL_9nzA2as6Q_AR8rPG8q" } else { $env:SUPABASE_PUBLISHABLE_KEY }
$supabaseProjectRef = if ([string]::IsNullOrWhiteSpace($env:SUPABASE_PROJECT_REF)) { "yilegxcnokndozhwpwlf" } else { $env:SUPABASE_PROJECT_REF }
$taskmasterEnv = if ([string]::IsNullOrWhiteSpace($env:TASKMASTER_ENV)) { "production" } else { $env:TASKMASTER_ENV }
$pubspec = Get-Content -Raw (Join-Path $root "pubspec.yaml")
$versionMatch = [regex]::Match($pubspec, "(?m)^version:\s*([0-9A-Za-z\.\-\+]+)")
$fullVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "0.1.1+2" }
$versionParts = $fullVersion.Split("+", 2)
$appVersion = $versionParts[0]
$buildNumber = if ($versionParts.Length -gt 1) { $versionParts[1] } else { "0" }
$buildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$latestMigration = (Get-ChildItem -Path (Join-Path $root "supabase\migrations") -Filter "*.sql" |
  Sort-Object Name |
  Select-Object -Last 1).BaseName.Split("_", 2)[0]
try {
  $gitCommit = (& git -C $root rev-parse --short HEAD 2>$null)
  if ([string]::IsNullOrWhiteSpace($gitCommit)) {
    $gitCommit = "not-a-git-workspace"
  }
} catch {
  $gitCommit = "not-a-git-workspace"
}
if ($gitCommit -eq "not-a-git-workspace") {
  $gitReady = Join-Path $root "github-ready"
  if (Test-Path (Join-Path $gitReady ".git")) {
    try {
      $gitReadyCommit = (& git -C $gitReady rev-parse --short HEAD 2>$null)
      if (![string]::IsNullOrWhiteSpace($gitReadyCommit)) {
        $gitCommit = $gitReadyCommit
      }
    } catch {
      $gitCommit = "not-a-git-workspace"
    }
  }
}

if ([string]::IsNullOrWhiteSpace($flutter)) {
  $scoopFlutter = Join-Path $env:USERPROFILE "scoop\apps\flutter\current\bin\flutter.bat"
  if (Test-Path $scoopFlutter) {
    $flutter = $scoopFlutter
  } else {
    $flutter = "flutter"
  }
}

if ([string]::IsNullOrWhiteSpace($iscc)) {
  $scoopIscc = Join-Path $env:USERPROFILE "scoop\apps\inno-setup\current\ISCC.exe"
  if (Test-Path $scoopIscc) {
    $iscc = $scoopIscc
  } else {
    $iscc = "iscc"
  }
}

Write-Host "Using Flutter: $flutter"
Write-Host "Using Inno Setup: $iscc"

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
  }
}

Push-Location $root
try {
  New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
  Get-ChildItem -Path $releaseDir -File | Remove-Item -Force

  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts\generate-brand-assets.ps1")
  if ($LASTEXITCODE -ne 0) {
    throw "Brand asset generation failed."
  }
  Invoke-Checked $flutter clean
  Invoke-Checked $flutter pub get
  Invoke-Checked $flutter analyze
  Invoke-Checked $flutter test
  $dartDefines = @(
    "--dart-define=SUPABASE_URL=$supabaseUrl",
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=$supabasePublishableKey",
    "--dart-define=SUPABASE_PROJECT_REF=$supabaseProjectRef",
    "--dart-define=TASKMASTER_ENV=$taskmasterEnv",
    "--dart-define=TASKMASTER_APP_VERSION=$appVersion",
    "--dart-define=TASKMASTER_BUILD_NUMBER=$buildNumber",
    "--dart-define=TASKMASTER_GIT_COMMIT=$gitCommit",
    "--dart-define=TASKMASTER_BUILD_DATE=$buildDate",
    "--dart-define=TASKMASTER_DB_MIGRATION=$latestMigration"
  )
  Invoke-Checked $flutter build windows --release @dartDefines
  Invoke-Checked $flutter build apk --release @dartDefines

  $iss = Join-Path $root "installer\TaskMasterPro.iss"
  Invoke-Checked $iscc $iss

  $apkSource = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
  $apkTarget = Join-Path $releaseDir "TaskMasterPro-android-release.apk"
  Copy-Item -LiteralPath $apkSource -Destination $apkTarget -Force

  $installer = Join-Path $releaseDir "TaskMasterPro-windows-x64-setup.exe"
  if (!(Test-Path $installer)) {
    throw "Windows installer was not created: $installer"
  }
  if (!(Test-Path $apkTarget)) {
    throw "Android APK was not created: $apkTarget"
  }

  Write-Host ""
  Write-Host "Release package complete:"
  Get-ChildItem -Path $releaseDir -File | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
} finally {
  Pop-Location
}
