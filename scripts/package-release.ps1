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

Assert-ProjectPath -Path $releaseDirectory
Assert-ProjectPath -Path $stagingDirectory
Assert-ProjectPath -Path $secretDirectory

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

New-Item -ItemType Directory -Force -Path $releaseDirectory | Out-Null
Get-ChildItem -LiteralPath $releaseDirectory -File |
    Where-Object Name -ne 'README.md' |
    ForEach-Object {
        Assert-ProjectPath -Path $_.FullName
        Remove-Item -LiteralPath $_.FullName -Force
    }

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $secretDirectory | Out-Null

$keyPropertiesPath = Join-Path $projectRoot 'android\key.properties'
$keystorePath = Join-Path $secretDirectory 'taskmaster-pro-release.jks'
if (-not (Test-Path -LiteralPath $keyPropertiesPath)) {
    $bytes = New-Object byte[] 36
    $randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomGenerator.GetBytes($bytes)
    }
    finally {
        $randomGenerator.Dispose()
    }
    $password = [Convert]::ToBase64String($bytes)
    $password = $password.Replace('+', '-').Replace('/', '_').TrimEnd('=')

    & keytool -genkeypair -v `
        -keystore $keystorePath `
        -storepass $password `
        -keypass $password `
        -alias taskmasterpro `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -dname 'CN=Y. A. Diab, OU=TaskMaster Pro, O=TaskMaster Pro, L=Cairo, C=EG'
    if ($LASTEXITCODE -ne 0) {
        throw 'Android release key generation failed'
    }

    @(
        "storePassword=$password"
        "keyPassword=$password"
        'keyAlias=taskmasterpro'
        "storeFile=$($keystorePath.Replace('\', '\\'))"
    ) | Set-Content -LiteralPath $keyPropertiesPath -Encoding ascii
}

Push-Location $projectRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    if (-not $SkipChecks) {
        & flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
    }

    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed' }

    & flutter build apk --release
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

$innoCompiler = (Get-Command iscc.exe -ErrorAction Stop).Source
$innoScript = Join-Path $projectRoot 'installer\taskmaster-pro.iss'
$installerPackaged = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    & $innoCompiler `
        "/DMyAppVersion=$version" `
        "/DSourceDir=$windowsStage" `
        "/DOutputDir=$releaseDirectory" `
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

$androidName = "TaskMaster-Pro-Android-$version.apk"
$androidOutput = Join-Path $releaseDirectory $androidName
Copy-Item -LiteralPath (
    Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
) -Destination $androidOutput

$installers = Get-ChildItem -LiteralPath $releaseDirectory -File |
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
        Get-ChildItem -LiteralPath $releaseDirectory -File |
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
    Join-Path $releaseDirectory 'release-manifest.json'
) -Encoding utf8

if (Test-Path -LiteralPath $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}

Write-Host "TaskMaster Pro $version release created in $releaseDirectory"
