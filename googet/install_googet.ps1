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

function Invoke-Icacls {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $global:LASTEXITCODE = 0
    & $icaclsExe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "icacls ($($Arguments -join ' ')) failed with exit code $LASTEXITCODE"
    }
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

$trustedDaclSids = @('S-1-5-32-544', 'S-1-5-18')
$currentProcessUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$systemAffectingDenySids = @('S-1-5-32-544', 'S-1-5-18', 'S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-3-4')
$aclSections = [System.Security.AccessControl.AccessControlSections]::Access -bor
               [System.Security.AccessControl.AccessControlSections]::Owner
$maskReadExecSync = [int]0x001200A9
$maskGenericAll = [int]0x10000000
$maskGenericExecute = [int]0x20000000
$maskGenericRead = [int]::MinValue
$disallowedUnprivilegedMask = -bnot ($maskReadExecSync -bor $maskGenericExecute -bor $maskGenericRead)
$fullControlMask = [int][System.Security.AccessControl.FileSystemRights]::FullControl
$script:localAdminSidsLoaded = $false
$script:localAdminSids = @{}
$script:hasNestedAdminGroup = $false
$script:trustedOwnerCache = @{}

function Initialize-LocalAdminSids {
    if ($script:localAdminSidsLoaded) {
        return
    }
    $script:localAdminSidsLoaded = $true
    try {
        $adminGroupSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $adminGroupName = $adminGroupSid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $group = [ADSI]"WinNT://./$adminGroupName,group"
        foreach ($member in @($group.psbase.Invoke('Members'))) {
            $memberClass = ''
            try {
                $memberClass = [string]$member.GetType().InvokeMember('Class', 'GetProperty', $null, $member, $null)
            }
            catch {}
            if ($memberClass -eq 'Group') {
                $script:hasNestedAdminGroup = $true
            }
            try {
                $sidBytes = $member.GetType().InvokeMember('objectSid', 'GetProperty', $null, $member, $null)
                if ($sidBytes -is [byte[]]) {
                    $memberSid = (New-Object System.Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
                    $script:localAdminSids[$memberSid] = $true
                    continue
                }
            }
            catch {}
            try {
                $adsPath = [string]$member.GetType().InvokeMember('AdsPath', 'GetProperty', $null, $member, $null)
                if ($adsPath -match '^WinNT://(S-\d+-\d+(?:-\d+)+)$') {
                    $script:localAdminSids[$Matches[1]] = $true
                }
            }
            catch {}
        }
    }
    catch {
        Write-Warning "Could not enumerate local Administrators members: $($_.Exception.Message)"
    }
}

function Test-IsTrustedOwnerSid {
    param([string]$Sid)

    if ([string]::IsNullOrEmpty($Sid)) {
        return $false
    }
    if ($trustedDaclSids -contains $Sid -or $Sid -eq $currentProcessUserSid) {
        return $true
    }
    if ($script:trustedOwnerCache.ContainsKey($Sid)) {
        return $script:trustedOwnerCache[$Sid]
    }

    Initialize-LocalAdminSids
    if ($script:localAdminSids.ContainsKey($Sid)) {
        $script:trustedOwnerCache[$Sid] = $true
        return $true
    }

    $isTrusted = $false
    if ($script:hasNestedAdminGroup) {
        try {
            $adEntry = [ADSI]"LDAP://<SID=$Sid>"
            $adEntry.RefreshCache(@('tokenGroups'))
            foreach ($groupSidBytes in $adEntry.Properties['tokenGroups']) {
                if ($groupSidBytes -isnot [byte[]]) {
                    continue
                }
                $groupSid = (New-Object System.Security.Principal.SecurityIdentifier($groupSidBytes, 0)).Value
                if ($script:localAdminSids.ContainsKey($groupSid)) {
                    $isTrusted = $true
                    break
                }
            }
        }
        catch {}
    }

    $script:trustedOwnerCache[$Sid] = $isTrusted
    return $isTrusted
}

function Test-GooGetEntrySecurity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$IsContainer,
        [switch]$RequireProtectedRoot
    )

    $ownerSid = ''
    $untrustedOwner = $false
    $unsafeDacl = $false
    try {
        $acl = if ($IsContainer) {
            [System.IO.Directory]::GetAccessControl($Path, $aclSections)
        }
        else {
            [System.IO.File]::GetAccessControl($Path, $aclSections)
        }
        $recheck = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($recheck.PSIsContainer -ne $IsContainer) -or (($recheck.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Entry attributes changed during inspection: $Path"
        }

        $ownerSid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if (-not (Test-IsTrustedOwnerSid -Sid $ownerSid)) {
            $untrustedOwner = $true
            $unsafeDacl = $true
        }
        if ($RequireProtectedRoot -and -not $acl.AreAccessRulesProtected) {
            $unsafeDacl = $true
        }

        $adminsHasFull = $false
        $systemHasFull = $false
        $rawDacl = (New-Object System.Security.AccessControl.RawSecurityDescriptor($acl.GetSecurityDescriptorSddlForm('Access'))).DiscretionaryAcl
        if ($null -eq $rawDacl) {
            $unsafeDacl = $true
        }
        else {
            foreach ($ace in $rawDacl) {
                $commonAce = $ace -as [System.Security.AccessControl.CommonAce]
                if ($null -eq $commonAce -or ($commonAce.AceType -ne 'AccessAllowed' -and $commonAce.AceType -ne 'AccessDenied')) {
                    $unsafeDacl = $true
                    break
                }
                $sid = $commonAce.SecurityIdentifier.Value
                $mask = [int]$commonAce.AccessMask
                if ($commonAce.AceType -eq 'AccessDenied') {
                    if ($sid -in $systemAffectingDenySids) {
                        $unsafeDacl = $true
                        break
                    }
                    continue
                }
                if (($commonAce.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0) {
                    if ($sid -eq 'S-1-5-32-544' -and ((($mask -band $fullControlMask) -eq $fullControlMask) -or (($mask -band $maskGenericAll) -ne 0))) {
                        $adminsHasFull = $true
                    }
                    elseif ($sid -eq 'S-1-5-18' -and ((($mask -band $fullControlMask) -eq $fullControlMask) -or (($mask -band $maskGenericAll) -ne 0))) {
                        $systemHasFull = $true
                    }
                }
                if ($trustedDaclSids -notcontains $sid -and (($mask -band $disallowedUnprivilegedMask) -ne 0)) {
                    $unsafeDacl = $true
                    break
                }
            }
        }
        if (($RequireProtectedRoot -or $acl.AreAccessRulesProtected) -and (-not $adminsHasFull -or -not $systemHasFull)) {
            $unsafeDacl = $true
        }
    }
    catch [System.UnauthorizedAccessException] {
        $untrustedOwner = $true
        $unsafeDacl = $true
    }

    return [PSCustomObject]@{
        OwnerSid       = $ownerSid
        UntrustedOwner = $untrustedOwner
        UnsafeDacl     = $unsafeDacl
    }
}

$rootItem = Get-Item -LiteralPath $googet_root -Force -ErrorAction SilentlyContinue
$rootExisted = $null -ne $rootItem
if (-not $rootExisted) {
    [System.IO.Directory]::CreateDirectory($googet_root, (New-GooGetRootAcl)) | Out-Null
    Write-Host "Created $googet_root directory."
    $rootItem = Get-Item -LiteralPath $googet_root -Force
}

if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw "Refusing to use $googet_root because it is not a regular directory (attributes: $($rootItem.Attributes))."
}

$rootWasExposed = $false
if ($rootExisted) {
    $rootState = Test-GooGetEntrySecurity -Path $googet_root -IsContainer $true -RequireProtectedRoot
    $rootWasExposed = $rootState.UntrustedOwner -or $rootState.UnsafeDacl
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
Invoke-Icacls @($googet_root, '/setowner', '*S-1-5-32-544', '/L', '/Q')
$rootItem = Get-Item -LiteralPath $googet_root -Force
if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw "Refusing to use $googet_root because it changed to a non-regular directory."
}
[System.IO.Directory]::SetAccessControl($googet_root, (New-GooGetRootAcl))

# When C:\ProgramData\GooGet was previously exposed, remediate pre-existing child
# entries in Root, repos, and cache:
# - Reparse points and unexpected untrusted entries are removed without /T so
#   junctions and hard-linked file security descriptors are never traversed.
# - Untrusted googet.conf and *.repo files are quarantined to *.untrusted so
#   planted repository definitions cannot execute packages on googet update.
# - Remaining trusted/allowlisted entries with unsafe DACLs are reset to inherit.
$allowedRootDirs = @('repos', 'cache', 'third_party_licenses')
$allowedRootFiles = @(
    'googet.exe', 'googet.conf', 'googet.db', 'googet.db-wal', 'googet.db-shm',
    'googet.db-journal', 'googet.state', 'googet.state.bak', 'googet.lock',
    'googet.log', 'googet.log.old', 'license.txt'
)
$fsutilExe = Join-Path $env:SystemRoot 'System32\fsutil.exe'
$normalizedScriptDir = $ScriptDir.TrimEnd('\')
$script:remediationErrors = New-Object System.Collections.Generic.List[string]

function Test-HasMultipleHardLinks {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    if (!(Test-Path -LiteralPath $fsutilExe)) {
        return $false
    }
    $global:LASTEXITCODE = 0
    $links = @(& $fsutilExe hardlink list $FilePath)
    if ($LASTEXITCODE -ne 0) {
        throw "fsutil hardlink list failed on '$FilePath' with exit code $LASTEXITCODE"
    }
    return ($links.Count -gt 1)
}

function Remove-FileLinkSafe {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    try {
        [System.IO.File]::Delete($FilePath)
    }
    catch [System.UnauthorizedAccessException] {
        if (-not (Test-HasMultipleHardLinks -FilePath $FilePath)) {
            [System.IO.File]::SetAttributes($FilePath, [System.IO.FileAttributes]::Normal)
        }
        [System.IO.File]::Delete($FilePath)
    }
}

function Remove-GooGetEntryNoFollow {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)

    $p = $Item.FullName
    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($Item.PSIsContainer) { [System.IO.Directory]::Delete($p) } else { [System.IO.File]::Delete($p) }
        return
    }
    if ($Item.PSIsContainer) {
        Invoke-Icacls @($p, '/setowner', '*S-1-5-32-544', '/L', '/Q')
        Invoke-Icacls @($p, '/reset', '/L', '/Q')
        $recheckDir = Get-Item -LiteralPath $p -Force -ErrorAction Stop
        if (-not $recheckDir.PSIsContainer -or (($recheckDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Directory changed to non-regular entry before child enumeration: $p"
        }
        foreach ($sub in @(Get-ChildItem -LiteralPath $p -Force -ErrorAction Stop)) {
            Remove-GooGetEntryNoFollow -Item $sub
        }
        [System.IO.Directory]::Delete($p)
    }
    else {
        # Delete through the parent directory's DeleteChild right without
        # modifying the file's security descriptor (preserving hard-link targets).
        Remove-FileLinkSafe -FilePath $p
    }
}

function Repair-GooGetChildren {
    param(
        [Parameter(Mandatory = $true)][string]$DirectoryPath,
        [Parameter(Mandatory = $true)][ValidateSet('Root', 'Repos', 'Cache')][string]$Mode
    )

    if (-not [System.IO.Directory]::Exists($DirectoryPath)) {
        $maybeItem = Get-Item -LiteralPath $DirectoryPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $maybeItem) {
            $script:remediationErrors.Add("Refusing to use '$DirectoryPath' because it is not a regular directory.")
        }
        return
    }
    try {
        $dirItem = Get-Item -LiteralPath $DirectoryPath -Force -ErrorAction Stop
        if (-not $dirItem.PSIsContainer -or (($dirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            $script:remediationErrors.Add("Refusing to use '$DirectoryPath' because it is not a regular directory.")
            return
        }
        $children = @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop)
    }
    catch {
        $script:remediationErrors.Add("Failed to enumerate '$DirectoryPath': $($_.Exception.Message)")
        return
    }

    foreach ($child in $children) {
        $childPath = $child.FullName
        try {
            if ($child.Name -match '[\.\s]$') {
                throw "Refusing entry with trailing dot or space: $childPath"
            }
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Warning "Removing unexpected reparse point $childPath"
                Remove-GooGetEntryNoFollow -Item $child
                continue
            }

            $entryState = Test-GooGetEntrySecurity -Path $childPath -IsContainer $child.PSIsContainer
            $untrustedOwner = $entryState.UntrustedOwner
            $unsafeDacl = $entryState.UnsafeDacl

            if (-not $child.PSIsContainer -and ($untrustedOwner -or $unsafeDacl) -and (Test-HasMultipleHardLinks -FilePath $childPath)) {
                Write-Warning "Removing unexpected hard-linked file $childPath"
                Remove-FileLinkSafe -FilePath $childPath
                continue
            }

            if ($untrustedOwner) {
                $nameLower = $child.Name.ToLowerInvariant()
                $normalizedChild = $childPath.TrimEnd('\')
                $protectsScriptDir = $normalizedChild.Equals($normalizedScriptDir, [System.StringComparison]::OrdinalIgnoreCase) -or
                                     $normalizedScriptDir.StartsWith($normalizedChild + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
                                     $normalizedChild.StartsWith($normalizedScriptDir + '\', [System.StringComparison]::OrdinalIgnoreCase)

                if (-not $protectsScriptDir) {
                    $isAllowedShape = if ($Mode -eq 'Root') {
                        if ($child.PSIsContainer) { $allowedRootDirs -contains $nameLower } else { $allowedRootFiles -contains $nameLower }
                    }
                    elseif ($Mode -eq 'Repos') {
                        (-not $child.PSIsContainer) -and $nameLower.EndsWith('.repo')
                    }
                    else {
                        $false
                    }

                    if (-not $isAllowedShape) {
                        Write-Warning "Removing unexpected untrusted entry $childPath"
                        Remove-GooGetEntryNoFollow -Item $child
                        continue
                    }

                    $isSensitiveConfig = (-not $child.PSIsContainer) -and (
                        ($Mode -eq 'Root' -and $nameLower -eq 'googet.conf') -or
                        ($Mode -eq 'Repos' -and $nameLower.EndsWith('.repo')))
                    if ($isSensitiveConfig) {
                        $quarantinePath = "$childPath.untrusted.$([DateTime]::UtcNow.Ticks)"
                        Write-Warning "Quarantining untrusted configuration file $childPath to $quarantinePath"
                        [System.IO.File]::Move($childPath, $quarantinePath)
                        try {
                            Invoke-Icacls @($quarantinePath, '/setowner', '*S-1-5-32-544', '/L', '/Q')
                            Invoke-Icacls @($quarantinePath, '/reset', '/L', '/Q')
                        }
                        catch {
                            Write-Warning "Could not reset permissions on quarantined file ${quarantinePath}: $($_.Exception.Message)"
                        }
                        continue
                    }
                }

                Invoke-Icacls @($childPath, '/setowner', '*S-1-5-32-544', '/L', '/Q')
            }
            if ($unsafeDacl) {
                Invoke-Icacls @($childPath, '/reset', '/L', '/Q')
            }
            if ($Mode -eq 'Cache' -and $child.PSIsContainer) {
                Repair-GooGetChildren -DirectoryPath $childPath -Mode 'Cache'
            }
        }
        catch {
            $script:remediationErrors.Add("Failed to remediate '$childPath': $($_.Exception.Message)")
        }
    }
}

if ($rootWasExposed) {
    Repair-GooGetChildren -DirectoryPath $googet_root -Mode 'Root'
    Repair-GooGetChildren -DirectoryPath (Join-Path $googet_root 'repos') -Mode 'Repos'
    Repair-GooGetChildren -DirectoryPath (Join-Path $googet_root 'cache') -Mode 'Cache'
    if ($script:remediationErrors.Count -gt 0) {
        throw ("Failed to remediate GooGet directory entries: " + ($script:remediationErrors -join '; '))
    }
}
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
