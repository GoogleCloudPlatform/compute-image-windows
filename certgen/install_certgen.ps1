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

# Windows Server 2012 is 6.2
# Windows Server 2012 R2 is 6.3
$IsWin2012Legacy = ($Major -eq 6 -and ($Minor -eq 0 -or $Minor -eq 3))

# $PSScriptRoot is the directory where the script is running, inside the expanded GooGet package.
$PackageRoot = $PSScriptRoot

$InstallDir = "$env:ProgramFiles\Google\Compute Engine\tools"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force
}

$TargetExePath = Join-Path $InstallDir "certgen.exe"

if ($IsWin2012Legacy) {
    Write-Host "Detected Windows version $Major.$Minor. Installing legacy certgen due to Go compatibility."
    $SourceExe = Join-Path $PackageRoot "legacy_bin/certgen/legacy_win2012/certgen.exe"
}
else {
    Write-Host "Detected modern Windows version. Installing current certgen."
    $SourceExe = Join-Path $PackageRoot "certgen.exe"
}

Write-Host "Copying $SourceExe to $TargetExePath"
Copy-Item -Path $SourceExe -Destination $TargetExePath -Force

Write-Host "Certgen installation complete."
