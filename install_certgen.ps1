#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Get OS Version
$OSVersion = [System.Environment]::OSVersion.Version
$Major = $OSVersion.Major
$Minor = $OSVersion.Minor

# Windows Server 2008 is 6.0
# Windows Server 2008 R2 is 6.1
$IsWin2008Legacy = ($Major -eq 6 -and ($Minor -eq 0 -or $Minor -eq 1))

# $PSScriptRoot is the directory where the script is running, inside the expanded GooGet package.
$PackageRoot = $PSScriptRoot

$InstallDir = "$env:ProgramFiles\Google\Compute Engine\tools"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force
}

$TargetExePath = Join-Path $InstallDir "certgen.exe"

if ($IsWin2008Legacy) {
    Write-Host "Detected Windows version $Major.$Minor. Installing legacy certgen due to Go compatibility."
    $SourceExe = Join-Path $PackageRoot "last_known_good\win_ver_6_1\certgen.exe"
}
else {
    Write-Host "Detected modern Windows version. Installing current certgen."
    $SourceExe = Join-Path $PackageRoot "certgen.exe"
}

Write-Host "Copying $SourceExe to $TargetExePath"
Copy-Item -Path $SourceExe -Destination $TargetExePath -Force

Write-Host "Certgen installation complete."
