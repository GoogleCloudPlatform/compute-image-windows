#  Copyright 2025 Google Inc. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http:#www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# Get OS Version
$OSVersion = [System.Environment]::OSVersion.Version
$Major = $OSVersion.Major
$Minor = $OSVersion.Minor

# Windows Server 2008 is 6.0
# Windows Server 2008 R2 is 6.1
# Windows Server 2012 is 6.2
# Windows Server 2012 R2 is 6.3
$IsWin2012Legacy = $Major -eq 6

$googet_root = "${env:ProgramData}\GooGet"
$machine_env = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'

if (!(Test-Path $googet_root)) {
    New-Item -ItemType Directory -Path $googet_root -Force
    Write-Host "Created $googet_root directory."
}

# === Check Windows Version ===
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path # Directory of the running script

$SourceGooGetExe = ""
if ($IsWin2012Legacy) {
    Write-Host "Detected Windows version $Major.$Minor. Installing legacy GooGet."
    $SourceGooGetExe = Join-Path $PSScriptRoot "legacy_bin/googet/legacy_win2012/googet.exe"
}
else {
    Write-Host "Detected modern Windows version. Installing latest GooGet."
    $SourceGooGetExe = Join-Path $PSScriptRoot "googet.exe"
}

if (!(Test-Path $SourceGooGetExe)) {
    Write-Error "Required GooGet executable not found at $SourceGooGetExe"
    exit 1
}

$TargetGooGetExe = Join-Path $googet_root "googet.exe"
Write-Host "Copying $SourceGooGetExe to $TargetGooGetExe"
Copy-Item -Path $SourceGooGetExe -Destination $TargetGooGetExe -Force
# === End Windows version check ===

if (!((Get-ItemProperty $machine_env -ErrorAction SilentlyContinue).GooGetRoot -eq $googet_root)) {
  Set-ItemProperty $machine_env -Name 'GooGetRoot' -Value $googet_root
  Write-Host "GooGetRoot environment variable set."
}

$path = (Get-ItemProperty $machine_env -ErrorAction SilentlyContinue).Path
if ($path -notlike "*${googet_root}*") {
  $newPath = $path + ";${googet_root}"
  Set-ItemProperty $machine_env -Name 'Path' -Value $newPath
  Write-Host "GooGetRoot added to PATH."
}

# Set permissions on GooGet root
Write-Host "Setting permissions on $googet_root"
$icaclsArgs = @($googet_root, '/grant:r', 'Administrators:(OI)(CI)F', '/grant:r', 'SYSTEM:(OI)(CI)F', '/grant:r', 'Users:(OI)(CI)RX', '/inheritance:r')
$process = Start-Process icacls.exe -ArgumentList $icaclsArgs -Wait -NoNewWindow -PassThru
if ($process.ExitCode -ne 0) {
    Write-Warning "icacls failed with exit code $($process.ExitCode)"
} else {
    Write-Host "Permissions set successfully."
}

Write-Host "GooGet installation complete. Please restart your shell session or system for PATH changes to take full effect."
