# Copyright 2015 Google Inc. All Rights Reserved.
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

  #requires -version 3.0
#>

Set-StrictMode -Version Latest

# Default Values
$script:kms_server = 'kms.windows.googlecloud.com'
$script:kms_server_port = 1688

$module = 'C:\Program Files\Google\Compute Engine\gce_base.psm1'
try {
  Import-Module $module -ErrorAction Stop 3> $null
}
catch [System.Management.Automation.ActionPreferenceStopException] {
  Write-Host $_.Exception.GetBaseException().Message
  Write-Host ("Unable to import GCE module from $module. " +
    'Check error message, or ensure module is present.')
  exit 2
}

function Activate-Instance {
  <#
    .SYNOPSIS
      Activate instance via a KMS SERVER.
    .DESCRIPTION
      Tries to Activate Instance with a KMS server. This function checks if the
      instance is already activated and if Yes skips. This Function can be uses
      for instance checkups in the future.
  #>

  # Variables
  [string]$license_key = $null
  [int]$retry_count = 3 # Try activation three times.

  Write-Output 'Checking instance license activation status.'
  if (Verify-ActivationStatus) {
    Write-Output "$global:hostname is already licensed and activated."
    return
  }
  Write-Output "$global:hostname needs to be activated by a KMS Server."
  # Get the LicenseKey.
  $license_key = Get-ProductKmsClientKey
  if (-not $license_key) {
    Write-Output 'Could not get the License Key for the instance. Activation skipped.'
    return
  }
  # Set the KMS server.
  & cscript //nologo $env:windir\system32\slmgr.vbs /skms $script:kms_server
  # Apply the license key to the host.
  & cscript //nologo $env:windir\system32\slmgr.vbs /ipk $license_key

  # Check if the product can be activated.
  $reg_query = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion'
  $get_product_details = (Get-ItemProperty -Path $reg_query -Name ProductName).ProductName
  $known_editions_regex = 'Windows (Web )?Server (2008 R2|2012|2012 R2|2016)'
  if ($get_product_details -notmatch $known_editions_regex) {
    Write-Output ("$get_product_details activations are currently not " +
        'supported on GCE. Activation request will be skipped.')
    return
  }

  # Check if the KMS server is reachable.
  if (-not (_TestTCPPort -host $script:kms_server -port $script:kms_server_port)) {
    Write-Output 'Could not contact activation server. Will retry activation later.'
    return
  }
  # KMS Server is reachable try to activate the server.
  while ($retry_count -gt 0) {
    # Activate the instance.
    Write-Output 'Activating instance...'
    & cscript //nologo $env:windir\system32\slmgr.vbs /ato
    # Helps to avoid activation failures.
    Start-Sleep -Seconds 1
    # Check activation status.
    if (Verify-ActivationStatus) {
      Write-Output 'Activation successful.'
      break
    }
    else {
      Write-Output 'Activation failed.'
      $retry_count = $retry_count - 1
    }
    if ($retry_count -gt 0) {
      Write-Output "Retrying activation. Will try $retry_count more time(s)"
    }
  }
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
      https://technet.microsoft.com/en-us/library/jj612867.aspx has all the
      details.
    .RETURNS
      License Key.
  #>

  # Variables
  $license_key = $null
  $reg_query = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion'

  # Get the product name and set the license key accordingly.
  try {
    $get_product_details = (Get-ItemProperty -Path $reg_query -Name ProductName).ProductName
  }
  catch {
    Write-Host 'Failed to get the product details. Skipping activation.'
    return
  }
  # KMS Client Keys: https://technet.microsoft.com/en-us/jj612867.aspx
  switch ($get_product_details) {
    # Workstations
    # Currently not supported.
    'Windows 7 Professional' {
      $license_key = 'FJ82H-XT6CR-J8D7P-XQJJ2-GPDD4'
    }
    # Currently not supported.
    'Windows 7 Enterprise' {
      $license_key = '33PXH-7Y6KF-2VJC9-XBBR8-HVTHH'
    }
    # Currently not supported.
    'Windows 8 Professional' {
      $license_key = 'NG4HW-VH26C-733KW-K6F98-J8CK4'
    }
    # Currently not supported.
    'Windows 8 Enterprise' {
      $license_key = '32JNW-9KQ84-P47T8-D8GGY-CWCK7'
    }
    # Currently not supported.
    'Windows 8.1 Professional' {
      $license_key = 'GCRJD-8NW9H-F2CDX-CCM8D-9D6T9'
    }
    # Currently not supported.
    'Windows 8.1 Enterprise' {
      $license_key = 'MHF9N-XY6XB-WVXMC-BTDCT-MKKG7'
    }
    # Currently not supported.
    'Windows 10 Professional' {
      $license_key = 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
    }
    'Windows 10 Enterprise' {
      $license_key = 'NPPR9-FWDCX-D2C8J-H872K-2YT43'
    }

    # Servers
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
    'Windows Server 2012 Server Standard' {
      $license_key = 'XC9B7-NBPP2-83J2H-RHMBY-92BT4'
    }
    'Windows Server 2012 Datacenter' {
      $license_key = '48HP8-DN98B-MYWDG-T2DCC-8W83P'
    }
    'Windows Server 2012 R2 Server Standard' {
      $license_key = 'D2N9P-3P6X9-2R39C-7RTCD-MDVJX'
    }
    'Windows Server 2012 R2 Datacenter' {
      $license_key = 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9'
    }
    'Windows Server 2016 Standard' {
      $license_key = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY'
    }
    'Windows Server 2016 Datacenter' {
      $license_key = 'CB7KF-BWN84-R7R2Y-793K2-8XDDG'
    }
    # Default
    default {
      Write-Host ('Unable to determine the correct KMS Client Key for ' +
          $get_product_details + '; no supported matches found for GCE.')
    }
  }
  return $license_key
}

function Verify-ActivationStatus {
  <#
    .SYNOPSIS
      Check if the instance in activated.
    .DESCRIPTION
      Checks if the localcomputer license is active and activated
    .OUTPUTS
      [bool]
  #>

  # Variables
  [bool]$active = $false
  [String]$activation_status = $null
  [String]$status = $null

  # Query slmgr on the local machine.
  try {
    $slmgr_status = & cscript //nologo C:\Windows\system32\slmgr.vbs /dli
  }
  catch {
    return $active
  }
  # Check the output.
  $status = $slmgr_status.Split("`n") | Select-String -Pattern '^License Status:'
  if ($status -match 'Licensed') {
    $active = $true
  }
  return $active
}

Activate-Instance
