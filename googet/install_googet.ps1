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
$icaclsExe = Join-Path $env:SystemRoot 'System32\icacls.exe'
if (!(Test-Path -LiteralPath $icaclsExe)) {
    throw "icacls executable not found at $icaclsExe"
}

# === Check Windows Version ===
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$SourceGooGetExe = ""
if ($IsWin2012Legacy) {
    Write-Host "Detected Windows version $Major.$Minor. Installing legacy GooGet."
    $SourceGooGetExe = Join-Path $ScriptDir "legacy_bin/googet/legacy_win2012/googet.exe"
}
else {
    Write-Host "Detected modern Windows version. Installing latest GooGet."
    $SourceGooGetExe = Join-Path $ScriptDir "googet.exe"
}

if (!(Test-Path -LiteralPath $SourceGooGetExe)) {
    throw "Required GooGet executable not found at $SourceGooGetExe"
}
# === End Windows version check ===

# Build a protected DACL using well-known SIDs:
#   S-1-5-32-544 = BUILTIN\Administrators
#   S-1-5-18     = NT AUTHORITY\SYSTEM
#   S-1-5-32-545 = BUILTIN\Users
function New-GooGetRootAcl {
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
               [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $noProp = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')),
        [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, $noProp, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')),
        [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, $noProp, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')),
        [System.Security.AccessControl.FileSystemRights]::ReadAndExecute, $inherit, $noProp, $allow)))
    return $acl
}

$rootItem = Get-Item -LiteralPath $googet_root -Force -ErrorAction SilentlyContinue
if ($null -eq $rootItem) {
    [System.IO.Directory]::CreateDirectory($googet_root, (New-GooGetRootAcl)) | Out-Null
    Write-Host "Created $googet_root directory."
    $rootItem = Get-Item -LiteralPath $googet_root -Force
}

if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw "Refusing to use $googet_root because it is not a regular directory (attributes: $($rootItem.Attributes))."
}

$TargetGooGetExe = Join-Path $googet_root "googet.exe"
$targetItem = Get-Item -LiteralPath $TargetGooGetExe -Force -ErrorAction SilentlyContinue
if ($null -ne $targetItem) {
    if ($targetItem.PSIsContainer -or (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing to overwrite unexpected entry at $TargetGooGetExe (attributes: $($targetItem.Attributes))."
    }
    [System.IO.File]::SetAttributes($TargetGooGetExe, [System.IO.FileAttributes]::Normal)
    [System.IO.File]::Delete($TargetGooGetExe)
}
Write-Host "Copying $SourceGooGetExe to $TargetGooGetExe"
Copy-Item -LiteralPath $SourceGooGetExe -Destination $TargetGooGetExe -Force

Write-Host "Setting permissions on $googet_root"
$global:LASTEXITCODE = 0
& $icaclsExe $googet_root '/setowner' '*S-1-5-32-544' '/L' '/Q'
if ($LASTEXITCODE -ne 0) {
    throw "icacls /setowner failed on '$googet_root' with exit code $LASTEXITCODE"
}
$rootItem = Get-Item -LiteralPath $googet_root -Force
if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw "Refusing to use $googet_root because it changed to a non-regular directory."
}
[System.IO.Directory]::SetAccessControl($googet_root, (New-GooGetRootAcl))
Write-Host "Permissions set successfully."

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

Write-Host "GooGet installation complete. Please restart your shell session or system for PATH changes to take full effect."
