# Copyright 2017 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

<#
  .SYNOPSIS
    Activates a GCE instance.
#>

#requires -version 3

Set-StrictMode -Version Latest

$script:kms_server = 'kms.windows.googlecloud.com'
$script:kms_server_port = 1688

try {
  $script:product_name = (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion' -Name ProductName).ProductName
}
catch {
  Write-Output 'Failed to get the product details. Skipping activation.'
  exit
}

function Get-ProductKmsClientKey {
  <#
    .SYNOPSIS
      Gets the correct KMS Client license Key for the OS.
    .DESCRIPTION
      Queries registry to get the correct product name and applies the correct
      KMS client key to it.
    .NOTES
      Please add new license keys as we support more product versions.
      See https://technet.microsoft.com/en-us/library/jj612867.aspx.
    .RETURNS
      License Key.
  #>

  $license_key = $null

  switch ($script:product_name) {
    # Workstations
    <#  Currently not supported.
    'Windows 7 Professional' {
      $license_key = 'FJ82H-XT6CR-J8D7P-XQJJ2-GPDD4'
    }
    'Windows 7 Enterprise' {
      $license_key = '33PXH-7Y6KF-2VJC9-XBBR8-HVTHH'
    }
    'Windows 8 Professional' {
      $license_key = 'NG4HW-VH26C-733KW-K6F98-J8CK4'
    }
    'Windows 8 Enterprise' {
      $license_key = '32JNW-9KQ84-P47T8-D8GGY-CWCK7'
    }
    'Windows 8.1 Professional' {
      $license_key = 'GCRJD-8NW9H-F2CDX-CCM8D-9D6T9'
    }
    'Windows 8.1 Enterprise' {
      $license_key = 'MHF9N-XY6XB-WVXMC-BTDCT-MKKG7'
    }
    'Windows 10 Professional' {
      $license_key = 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
    }
    'Windows 10 Enterprise' {
      $license_key = 'NPPR9-FWDCX-D2C8J-H872K-2YT43'
    }
    #>

    # Servers
    'Windows Server (R) 2008 Standard' {
      $license_key = 'TM24T-X9RMF-VWXK6-X8JC9-BFGM2'
    }
    'Windows Server (R) 2008 Datacenter' {
      $license_key = '7M67G-PC374-GR742-YH8V4-TCBY3'
    }
    'Windows Server (R) 2008 Enterprise' {
      $license_key = 'YQGMW-MPWTJ-34KDK-48M3W-X4Q6V'
    }

    'Windows Server 2008 R2 Datacenter' {
      $license_key = '74YFP-3QFB3-KQT8W-PMXWJ-7M648'
    }
    'Windows Server 2008 R2 Standard' {
      $license_key = 'YC6KT-GKW9T-YTKYR-T4X34-R7VHC'
    }
    'Windows Server 2008 R2 Enterprise' {
      $license_key = '489J6-VHDMP-X63PK-3K798-CPX3Y'
    }
    'Windows Server 2008 R2 Web' {
      $license_key = '6TPJF-RBVHG-WBW2R-86QPH-6RTM4'
    }

    'Windows Server 2012 Standard' {
      $license_key = 'XC9B7-NBPP2-83J2H-RHMBY-92BT4'
    }
    'Windows Server 2012 Datacenter' {
      $license_key = '48HP8-DN98B-MYWDG-T2DCC-8W83P'
    }

    'Windows Server 2012 R2 Standard' {
      $license_key = 'D2N9P-3P6X9-2R39C-7RTCD-MDVJX'
    }
    'Windows Server 2012 R2 Datacenter' {
      $license_key = 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9'
    }
    'Windows Server 2012 R2 Essentials' {
      $license_key = 'KNC87-3J2TX-XB4WP-VCPJV-M4FWM'
    }

    'Windows Server 2016 Standard' {
      $license_key = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY'
    }
    'Windows Server 2016 Datacenter' {
      $license_key = 'CB7KF-BWN84-R7R2Y-793K2-8XDDG'
    }
    'Windows Server 2016 Essentials' {
      $license_key = 'JCKRF-N37P4-C2D82-9YXRT-4M63B'
    }

    'Windows Server 2019 Standard' {
      $license_key = 'N69G4-B89J2-4G8F4-WWYCC-J464C'
    }
    'Windows Server 2019 Datacenter' {
      $license_key = 'WMDGN-G9PQG-XVVXX-R3X43-63DFG'
    }
    'Windows Server 2019 Essentials' {
      $license_key = 'WVDHN-86M7X-466P6-VHXV7-YY726'
    }

    'Windows Server 2022 Datacenter' {
      $license_key = 'WX4NM-KYWYW-QJJR4-XV3QB-6VM33'
    }
    'Windows Server 2022 Standard' {
      $license_key = 'VDYBN-27WPP-V4HQT-9VMD4-VMK7H'
    }

    'Windows Server 2025 Datacenter' {
      $license_key = 'D764K-2NDRG-47T6Q-P8T8W-YP6DF'
    }
    'Windows Server 2025 Standard' {
      $license_key = 'TVRH6-WHNXV-R9WG3-9XRFY-MY832'
    }

    'Windows Server Standard' {
      $license_key = 'N2KJX-J94YW-TQVFB-DG9YT-724CC'
    }
    'Windows Server Datacenter' {
      $license_key = '6NMRW-2C8FM-D24W7-TQWMY-CWH2D'
    }
  }
  return $license_key
}

function Verify-ActivationStatus {
  <#
    .SYNOPSIS
      Check if the instance is activated.
    .OUTPUTS
      [bool] Is the instance activated.
  #>

  [bool]$active = $false
  [String]$activation_status = $null
  [String]$status = $null

  # Server 2008/2012R2 don't store activation status in registry; check slmgr
  if([Environment]::OSVersion.Version.Major -eq 6 -and [Environment]::OSVersion.Version.Minor -le 3)
  {
    try {
      $slmgr_status = & cscript //E:VBScript //nologo $env:windir\system32\slmgr.vbs /dli
    }
    catch {
      Write-Host "Error getting slmgr license status output."
    }
    $status = $slmgr_status | Select-String -Pattern '^License Status:'
    # The initial space is to ensure "Unlicensed" does not match.
    if ($status -match ' Licensed') {
      $active = $true
    }
  }
  # All server versions newer than 2012R2
  else {
    try {
      $activation_status = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\Activation" -Name ProductActivationResult).ProductActivationResult
    }
    catch {
      Write-Host "Error retrieving last activation result registry key."
    }
    # Anything other than 0x0 is a failure.
    if ($activation_status -eq '0') {
      $active = $true
    }
  }
  return $active
}

if (Test-Path "$env:ProgramFiles\Google\Compute Engine\sysprep\byol_image") {
  Write-Output 'Image imported into GCE via BYOL workflow, skipping GCE activation'
  exit
}

# Verify the instance has a Windows Pay as you go (PAYG) GCE License.
$paygLicenses = New-Object System.Collections.ArrayList
$paygLicenses.Add('7142647615590922601') | out-null # windows-cloud/global/licenses/windows-server-2025-dc
$paygLicenses.Add('4079807029871201927') | out-null # windows-cloud/global/licenses/windows-server-2022-dc
$paygLicenses.Add('3389558045860892917') | out-null # windows-cloud/global/licenses/windows-server-2019-dc
$paygLicenses.Add('1000213') | out-null             # windows-cloud/global/licenses/windows-server-2016-dc
$paygLicenses.Add('1000017') | out-null             # windows-cloud/global/licenses/windows-server-2012-r2-dc
$paygLicenses.Add('1000015') | out-null             # windows-cloud/global/licenses/windows-server-2012-dc
$paygLicenses.Add('1000000') | out-null             # windows-cloud/global/licenses/windows-server-2008-r2-dc
$paygLicenses.Add('1000502') | out-null             # windows-cloud/global/licenses/windows-server-2008-dc
$paygLicenses.Add('5507061839551517143') | out-null # windows-cloud/global/licenses/windows-server-2000
$paygLicenses.Add('5030842449011296880') | out-null # windows-cloud/global/licenses/windows-server-2003

$paygLicenses.Add('5194306116883728686') | out-null # windows-cloud/global/licenses/windows-server-1709-dc
$paygLicenses.Add('6476660300603799873') | out-null # windows-cloud/global/licenses/windows-server-1803-dc
$paygLicenses.Add('8597854123084943473') | out-null # windows-cloud/global/licenses/windows-server-1809-dc
$paygLicenses.Add('5980382382909462329') | out-null # windows-cloud/global/licenses/windows-server-1903-dc
$paygLicenses.Add('1413572828508235433') | out-null # windows-cloud/global/licenses/windows-server-1909-dc
$paygLicenses.Add('6710259852346942597') | out-null # windows-cloud/global/licenses/windows-server-2004-dc
$paygLicenses.Add('8578754948912497438') | out-null # windows-cloud/global/licenses/windows-server-20h2-dc
$paygLicenses.Add('7248135684629163401') | out-null # windows-cloud/global/licenses/windows-server-21h1-dc

$paygLicenses.Add('1656378918552316916') | out-null # windows-cloud/global/licenses/windows-server-2008
$paygLicenses.Add('3284763237085719542') | out-null # windows-cloud/global/licenses/windows-server-2008-r2
$paygLicenses.Add('7695108898142923768') | out-null # windows-cloud/global/licenses/windows-server-2012
$paygLicenses.Add('7798417859637521376') | out-null # windows-cloud/global/licenses/windows-server-2012-r2
$paygLicenses.Add('4819555115818134498') | out-null # windows-cloud/global/licenses/windows-server-2016
$paygLicenses.Add('1000214') | out-null             # windows-cloud/global/licenses/windows-server-2016-nano
$paygLicenses.Add('4874454843789519845') | out-null # windows-cloud/global/licenses/windows-server-2019
$paygLicenses.Add('6107784707477449232') | out-null # windows-cloud/global/licenses/windows-server-2022
$paygLicenses.Add('973054079889996136') | out-null  # windows-cloud/global/licenses/windows-server-2025

$paygLicensePresent = $false

try {
  $licenseCountOutput = (Invoke-RestMethod -Headers @{'Metadata-Flavor' = 'Google'} -Uri "http://metadata.google.internal/computeMetadata/v1/instance/licenses")
  $licenseCount = [regex]::matches($licenseCountOutput,"/").count
  
  For ($licenseIndex=0; $licenseIndex -lt $licenseCount; $licenseIndex++) {
    $licenseID = (Invoke-RestMethod -Headers @{'Metadata-Flavor' = 'Google'} -Uri "http://metadata.google.internal/computeMetadata/v1/instance/licenses/$licenseIndex/id").ToString()
    if ($paygLicenses.Contains($licenseID)) {
      Write-Output "Microsoft Windows PAYG license $licenseID found."
      $paygLicensePresent = $true
    }
  }
  if (-not $paygLicensePresent) {
    Write-Output 'Microsoft Windows PAYG license not found, skipping GCE activation'
    exit
  }
}
catch {
  Write-Output "Failed to identify if a Microsoft Windows PAYG license is attached. Error: $_"
  exit
}

[string]$license_key = $null
[int]$retry_count = 2 # Retry activation two additional times.

$license_key = Get-ProductKmsClientKey
if (-not $license_key) {
  Write-Output ("$script:product_name activations are currently not supported on GCE. Activation skipped.")
}

# Set the KMS server.
& $env:windir\system32\cscript.exe //nologo $env:windir\system32\slmgr.vbs /skms $script:kms_server | ForEach-Object {
  Write-Output $_
}
# Apply the license key to the host.
& $env:windir\system32\cscript.exe //nologo $env:windir\system32\slmgr.vbs /ipk $license_key  | ForEach-Object {
  Write-Output $_
}

Write-Output 'Activating instance...'
& $env:windir\system32\cscript.exe //nologo $env:windir\system32\slmgr.vbs /ato  | ForEach-Object {
  Write-Output $_
}

while ($retry_count -gt 0) {
  # Helps to avoid activation failures.
  Start-Sleep -Seconds 1

  if (Verify-ActivationStatus) {
    Write-Output 'Activation successful.'
    break
  }
  else {
    $retry_count = $retry_count - 1
    if ($retry_count -eq 0) {
      Write-Output 'Activation failed. Max activation retry count reached: Giving up.'
    }
    else {
      Write-Output "Activation failed. Will try $retry_count more time(s)."
      & $env:windir\system32\cscript.exe //nologo $env:windir\system32\slmgr.vbs /ato | ForEach-Object {
        Write-Output $_
      }
    }
  }
}
