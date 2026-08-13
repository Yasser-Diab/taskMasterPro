param(
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'release')
)
$stagingDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot '.release-staging')
)
$candidateReleaseDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $stagingDirectory 'release-candidate')
)
$previousReleaseDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $stagingDirectory 'previous-release')
)
$secretDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot '.release-secrets')
)

function Assert-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $prefix = $projectRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
        $prefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to modify a path outside the TaskMaster Pro workspace"
    }
}

function Get-Sha256Hash {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha256.ComputeHash($stream)
        return [System.BitConverter]::ToString($bytes).
            Replace('-', '').
            ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Assert-ReleaseArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    Assert-ProjectPath -Path $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not created at $Path"
    }
    if ((Get-Item -LiteralPath $Path).Length -le 0) {
        throw "$Label is empty at $Path"
    }
}

function Resolve-StagedTool {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    $expected = $Candidates -join "', '"
    throw (
        "$Label is not staged under E:\codingTools. Expected one of: " +
        "'$expected'. Stage the tool there before packaging."
    )
}

Assert-ProjectPath -Path $releaseDirectory
Assert-ProjectPath -Path $stagingDirectory
Assert-ProjectPath -Path $candidateReleaseDirectory
Assert-ProjectPath -Path $previousReleaseDirectory
Assert-ProjectPath -Path $secretDirectory

# Packaging must use the staged toolchain. Do not silently fall back to a
# machine-wide SDK, compiler, or signing tool with an unknown version.
$toolRoot = 'E:\codingTools'
$flutter = Resolve-StagedTool -Label 'Flutter' -Candidates @(
    (Join-Path $toolRoot 'flutter\bin\flutter.bat'),
    (Join-Path $toolRoot 'flutter-3.44.6\bin\flutter.bat')
)
$dart = Resolve-StagedTool -Label 'Dart' -Candidates @(
    (Join-Path $toolRoot 'flutter\bin\dart.bat'),
    (Join-Path $toolRoot 'flutter-3.44.6\bin\dart.bat')
)
$npm = Resolve-StagedTool -Label 'npm' -Candidates @(
    (Join-Path $toolRoot 'node\npm.cmd')
)
$keytool = Resolve-StagedTool -Label 'Java keytool' -Candidates @(
    (Join-Path $toolRoot 'jdk-21\bin\keytool.exe')
)
$innoCompiler = Resolve-StagedTool -Label 'Inno Setup compiler' -Candidates @(
    (Join-Path $toolRoot 'inno-setup\iscc.exe')
)

$javaHome = Join-Path $toolRoot 'jdk-21'
$androidSdkRoot = Join-Path $toolRoot 'android-sdk'
if (-not (Test-Path -LiteralPath $javaHome -PathType Container)) {
    throw "Java home is not staged at $javaHome"
}
if (-not (Test-Path -LiteralPath $androidSdkRoot -PathType Container)) {
    throw "Android SDK is not staged at $androidSdkRoot"
}

$toolPathEntries = @(
    (Split-Path -Parent $flutter),
    (Split-Path -Parent $npm),
    (Split-Path -Parent $keytool),
    (Split-Path -Parent $innoCompiler),
    (Join-Path $toolRoot 'git\cmd'),
    (Join-Path $androidSdkRoot 'platform-tools'),
    (Join-Path $androidSdkRoot 'build-tools\36.0.0')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
$env:Path = (($toolPathEntries + @($env:Path)) -join ';')
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $androidSdkRoot
$env:ANDROID_SDK_ROOT = $androidSdkRoot
$env:PUB_CACHE = Join-Path $toolRoot 'pub-cache'
# Keep TaskMaster Pro's release cache isolated from other staged Android
# projects. A killed build must not corrupt a shared Gradle lock protocol and
# make a later production package fail before compilation starts.
$env:GRADLE_USER_HOME = Join-Path $toolRoot 'gradle-home-taskmasterpro'

# Flutter keeps SDK preferences per Flutter installation.  Pin them here as
# well as in the process environment so a former drive letter cannot override
# the staged release toolchain during `flutter build apk`.
& $flutter config --android-sdk $androidSdkRoot --jdk-dir $javaHome
if ($LASTEXITCODE -ne 0) {
    throw 'Could not configure Flutter to use the staged Android SDK and JDK'
}

$pubspec = Get-Content -Raw -LiteralPath (
    Join-Path $projectRoot 'pubspec.yaml'
)
$versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
)
if (-not $versionMatch.Success) {
    throw 'Could not read the semantic version from pubspec.yaml'
}
$version = $versionMatch.Groups[1].Value

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (
    $candidateReleaseDirectory
) | Out-Null
New-Item -ItemType Directory -Force -Path $secretDirectory | Out-Null

$releaseReadme = Join-Path $releaseDirectory 'README.md'
if (Test-Path -LiteralPath $releaseReadme -PathType Leaf) {
    Copy-Item -LiteralPath $releaseReadme -Destination (
        Join-Path $candidateReleaseDirectory 'README.md'
    )
}

$keyPropertiesPath = Join-Path $projectRoot 'android\key.properties'
$keystorePath = Join-Path $secretDirectory 'taskmaster-pro-release.jks'
if (-not (Test-Path -LiteralPath $keyPropertiesPath)) {
    throw (
        "Android signing configuration is missing at $keyPropertiesPath. " +
        'Refusing to generate a replacement key because it would break the ' +
        'installed-app update lineage.'
    )
}
if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    throw (
        "Android release keystore is missing at $keystorePath. " +
        'Refusing to fall back to a debug or replacement signing key.'
    )
}

Push-Location $projectRoot
try {
    & $npm ci
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }

    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    & $dart run tool\generate_branding_assets.dart
    if ($LASTEXITCODE -ne 0) {
        throw 'branding asset generation failed'
    }

    if (-not $SkipChecks) {
        & $dart format --output=none --set-exit-if-changed .
        if ($LASTEXITCODE -ne 0) {
            throw 'dart format check failed'
        }
        & $flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
        & $flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
    }

    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed' }

    & $flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Android release build failed' }
}
finally {
    Pop-Location
}

$windowsSource = Join-Path (
    Join-Path $projectRoot 'build\windows\x64\runner'
) 'Release'
$windowsStage = Join-Path $stagingDirectory 'windows'
Copy-Item -LiteralPath $windowsSource -Destination $windowsStage -Recurse

$innoScript = Join-Path $projectRoot 'installer\taskmaster-pro.iss'
$installerPackaged = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    & $innoCompiler `
        "/DMyAppVersion=$version" `
        "/DSourceDir=$windowsStage" `
        "/DOutputDir=$candidateReleaseDirectory" `
        $innoScript
    if ($LASTEXITCODE -eq 0) {
        $installerPackaged = $true
        break
    }

    if ($attempt -lt 3) {
        Write-Warning (
            "Windows installer packaging attempt $attempt failed. " +
            'Retrying after the compiler releases temporary resources.'
        )
        Start-Sleep -Seconds 2
    }
}
if (-not $installerPackaged) {
    throw 'Windows installer packaging failed'
}

$windowsName = "TaskMasterPro-$version-Windows-Setup.exe"
$windowsOutput = Join-Path $candidateReleaseDirectory $windowsName
$androidName = "TaskMasterPro-$version-Android.apk"
$androidOutput = Join-Path $candidateReleaseDirectory $androidName
Copy-Item -LiteralPath (
    Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
) -Destination $androidOutput

Assert-ReleaseArtifact -Path $windowsOutput -Label 'Windows installer'
Assert-ReleaseArtifact -Path $androidOutput -Label 'Android APK'

$installers = Get-ChildItem -LiteralPath $candidateReleaseDirectory -File |
    Where-Object { $_.Extension -in @('.exe', '.apk') }
foreach ($installer in $installers) {
    $hash = Get-Sha256Hash -Path $installer.FullName
    "$hash  $($installer.Name)" | Set-Content -LiteralPath (
        "$($installer.FullName).sha256"
    ) -Encoding ascii
}

$manifest = [ordered]@{
    product = 'TaskMaster Pro'
    version = $version
    generatedAt = [DateTime]::UtcNow.ToString('o')
    releasePage = 'https://github.com/Yasser-Diab/taskMasterPro/releases'
    files = @(
        Get-ChildItem -LiteralPath $candidateReleaseDirectory -File |
            Where-Object Name -ne 'README.md' |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    name = $_.Name
                    bytes = $_.Length
                }
            }
    )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (
    Join-Path $candidateReleaseDirectory 'release-manifest.json'
) -Encoding utf8

$hadPreviousRelease = Test-Path -LiteralPath $releaseDirectory
try {
    if ($hadPreviousRelease) {
        Move-Item -LiteralPath $releaseDirectory -Destination (
            $previousReleaseDirectory
        )
    }
    Move-Item -LiteralPath $candidateReleaseDirectory -Destination (
        $releaseDirectory
    )
}
catch {
    if (
        -not (Test-Path -LiteralPath $releaseDirectory) -and
        (Test-Path -LiteralPath $previousReleaseDirectory)
    ) {
        Move-Item -LiteralPath $previousReleaseDirectory -Destination (
            $releaseDirectory
        )
    }
    throw
}

if (Test-Path -LiteralPath $previousReleaseDirectory) {
    Remove-Item -LiteralPath $previousReleaseDirectory -Recurse -Force
}

Assert-ReleaseArtifact -Path (
    Join-Path $releaseDirectory $windowsName
) -Label 'Published Windows installer'
Assert-ReleaseArtifact -Path (
    Join-Path $releaseDirectory $androidName
) -Label 'Published Android APK'

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}

Write-Host "TaskMaster Pro $version release created in $releaseDirectory"
