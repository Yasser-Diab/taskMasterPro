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
        throw "Refusing to modify a path outside the DayVector workspace"
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
$jarsigner = Resolve-StagedTool -Label 'Java jarsigner' -Candidates @(
    (Join-Path $toolRoot 'jdk-21\bin\jarsigner.exe')
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
# Keep DayVector's release cache isolated from other staged Android
# projects. A killed build must not corrupt a shared Gradle lock protocol and
# make a later production package fail before compilation starts.
$env:GRADLE_USER_HOME = Join-Path $toolRoot 'gradle-home-dayvector'

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
$buildNumber = $versionMatch.Groups[2].Value
$displayVersion = "$version+$buildNumber"

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
        # Third-party Windows plugin overrides intentionally include their
        # upstream example apps, which are not release dependencies. Analyze
        # DayVector's application, tests, and build tools directly.
        & $flutter analyze lib test tool
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
        & $flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
    }

    # CMake caches the executable target in generated install scripts. A
    # product rename must regenerate that directory or plugin install rules can
    # keep pointing at the previous target even though source metadata is new.
    $windowsGeneratedBuild = Join-Path $projectRoot 'build\windows'
    Assert-ProjectPath -Path $windowsGeneratedBuild
    if (Test-Path -LiteralPath $windowsGeneratedBuild) {
        Remove-Item -LiteralPath $windowsGeneratedBuild -Recurse -Force
    }

    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed' }

    $windowsBuild = Join-Path (
        Join-Path $projectRoot 'build\windows\x64\runner\Release'
    ) 'dayvector.exe'
    Assert-ReleaseArtifact -Path $windowsBuild -Label 'Windows build'
    $builtProductVersion = (
        Get-Item -LiteralPath $windowsBuild
    ).VersionInfo.ProductVersion
    if ($builtProductVersion -ne $displayVersion) {
        throw (
            "Windows build version mismatch. Expected $displayVersion but " +
            "compiled $builtProductVersion. Refusing to package a stale build."
        )
    }

    $supabaseConfig = Get-Content -Raw -LiteralPath (
        Join-Path $projectRoot 'lib\core\config\supabase_config.dart'
    )
    $projectRefMatch = [regex]::Match(
        $supabaseConfig,
        "static const projectRef = '([^']+)'"
    )
    $authCallbackMatch = [regex]::Match(
        $supabaseConfig,
        "static const authCallback = '([^']+)'"
    )
    if (-not $projectRefMatch.Success -or -not $authCallbackMatch.Success) {
        throw 'Could not read the release backend identity from SupabaseConfig'
    }
    $learningConfig = Get-Content -Raw -LiteralPath (
        Join-Path $projectRoot `
            'lib\core\learning\application_system_learning.dart'
    )
    $learningProjectRefMatch = [regex]::Match(
        $learningConfig,
        "static const projectRef = '([^']+)'"
    )
    $learningKeyMatch = [regex]::Match(
        $learningConfig,
        "defaultValue:\s*'(sb_publishable_[^']+)'"
    )
    if (-not $learningProjectRefMatch.Success -or
        -not $learningKeyMatch.Success) {
        throw (
            'Anonymous application learning is not configured for release. ' +
            'Refusing to package a silently disabled build.'
        )
    }
    $windowsAppSnapshot = Join-Path (
        Join-Path $projectRoot 'build\windows\x64\runner\Release\data'
    ) 'app.so'
    Assert-ReleaseArtifact -Path $windowsAppSnapshot -Label 'Windows app snapshot'
    $snapshotText = [System.Text.Encoding]::ASCII.GetString(
        [System.IO.File]::ReadAllBytes($windowsAppSnapshot)
    )
    foreach ($expectedIdentity in @(
        $projectRefMatch.Groups[1].Value,
        $authCallbackMatch.Groups[1].Value,
        $learningProjectRefMatch.Groups[1].Value,
        $learningKeyMatch.Groups[1].Value
    )) {
        if (-not $snapshotText.Contains($expectedIdentity)) {
            throw (
                "Windows app snapshot is missing $expectedIdentity. " +
                'Refusing to package a stale backend or authentication build.'
            )
        }
    }

    & $flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Android release build failed' }
    & $flutter build appbundle --release
    if ($LASTEXITCODE -ne 0) { throw 'Android App Bundle build failed' }
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
        "/DMyAppDisplayVersion=$displayVersion" `
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

$windowsName = "DayVector-$version-Windows-Setup.exe"
$windowsOutput = Join-Path $candidateReleaseDirectory $windowsName
$androidName = "DayVector-$version-Android.apk"
$androidOutput = Join-Path $candidateReleaseDirectory $androidName
$androidBundleName = "DayVector-$version-Android.aab"
$androidBundleOutput = Join-Path (
    $candidateReleaseDirectory
) $androidBundleName
Copy-Item -LiteralPath (
    Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
) -Destination $androidOutput
Copy-Item -LiteralPath (
    Join-Path $projectRoot 'build\app\outputs\bundle\release\app-release.aab'
) -Destination $androidBundleOutput

Assert-ReleaseArtifact -Path $windowsOutput -Label 'Windows installer'
Assert-ReleaseArtifact -Path $androidOutput -Label 'Android APK'
Assert-ReleaseArtifact -Path $androidBundleOutput -Label 'Android App Bundle'

& $jarsigner -verify $androidBundleOutput
if ($LASTEXITCODE -ne 0) {
    throw 'Android App Bundle signature verification failed'
}

$installers = Get-ChildItem -LiteralPath $candidateReleaseDirectory -File |
    Where-Object { $_.Extension -in @('.exe', '.apk', '.aab') }
foreach ($installer in $installers) {
    $hash = Get-Sha256Hash -Path $installer.FullName
    "$hash  $($installer.Name)" | Set-Content -LiteralPath (
        "$($installer.FullName).sha256"
    ) -Encoding ascii
}

$manifest = [ordered]@{
    product = 'DayVector'
    version = $version
    buildNumber = [int]$buildNumber
    displayVersion = $displayVersion
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
Assert-ReleaseArtifact -Path (
    Join-Path $releaseDirectory $androidBundleName
) -Label 'Published Android App Bundle'

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}

Write-Host "DayVector $version release created in $releaseDirectory"
