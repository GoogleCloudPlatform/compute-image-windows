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

if (Test-Path "$env:ProgramFiles\Google\Compute Engine\sysprep\byol_image") {
  Write-Output 'Image imported into GCE via BYOL workflow, skipping GCE activation'
  exit
}

$byolLicenses = New-Object System.Collections.ArrayList
$byolLicenses.Add('2089835370828997959') # windows-cloud/global/licenses/windows-10-enterprise-byol
$byolLicenses.Add('8727879116868096918') # windows-cloud/global/licenses/windows-10-x64-byol
$byolLicenses.Add('3732182829874353001') # windows-cloud/global/licenses/windows-10-x86-byol
$byolLicenses.Add('5378533650449772437') # windows-cloud/global/licenses/windows-11-x64-byol
$byolLicenses.Add('752112173778412950')  # windows-cloud/global/licenses/windows-7-enterprise-byol
$byolLicenses.Add('5016528181960184510') # windows-cloud/global/licenses/windows-7-x64-byol
$byolLicenses.Add('622639362407469665')  # windows-cloud/global/licenses/windows-7-x86-byol
$byolLicenses.Add('7036859048284197429') # windows-cloud/global/licenses/windows-8-x64-byol
$byolLicenses.Add('3720924436396315642') # windows-cloud/global/licenses/windows-8-x86-byol
$byolLicenses.Add('5366577783322166007') # windows-cloud/global/licenses/windows-81-x64-byol
$byolLicenses.Add('4551215591257167608') # windows-cloud/global/licenses/windows-server-2008-r2-byol
$byolLicenses.Add('5559842820536817947') # windows-cloud/global/licenses/windows-server-2012-byol
$byolLicenses.Add('6738952703547430631') # windows-cloud/global/licenses/windows-server-2012-r2-byol
$byolLicenses.Add('4322823184804632846') # windows-cloud/global/licenses/windows-server-2016-byol
$byolLicenses.Add('6532438499690676691') # windows-cloud/global/licenses/windows-server-2019-byol
$byolLicenses.Add('2808834792899686364') # windows-cloud/global/licenses/windows-server-2022-byol

try {
  $licenseCountOutput = (Invoke-RestMethod -Headers @{'Metadata-Flavor' = 'Google'} -Uri "http://metadata.google.internal/computeMetadata/v1/instance/licenses")
  $licenseCount = [regex]::matches($licenseCountOutput,"/").count
  
  For ($licenseIndex=0; $licenseIndex -lt $licenseCount; $licenseIndex++) {
    $licenseID = (Invoke-RestMethod -Headers @{'Metadata-Flavor' = 'Google'} -Uri "http://metadata.google.internal/computeMetadata/v1/instance/licenses/$licenseIndex/id").ToString()
    if ($byolLicenses.Contains($licenseID)) {
      Write-Output "BYOL license $licenseID found. Aborting setting the KMS server to Google Cloud KMS Server."
      exit
    }
  }
  Write-Output 'No BYOL license detected. Proceeding with activation.'
}
catch {
  Write-Output "Failed to identify if a known BYOL license is attached. Continuing to set the KMS server to Google Cloud KMS Server and activate. Error: $_"
}

$script:kms_server = 'kms.windows.googlecloud.com'
$script:kms_server_port = 1688
$script:hostname = hostname
$reg = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion'
try {
  $script:product_name = (Get-ItemProperty -Path $reg -Name ProductName).ProductName
}
catch {
  Write-Output 'Failed to get the product details. Skipping activation.'
  exit
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

  [string]$license_key = $null
  [int]$retry_count = 3 # Try activation three times.

  Write-Output 'Checking instance license activation status.'
  if (Verify-ActivationStatus) {
    Write-Output "$script:hostname is already licensed and activated."
    return
  }

  Write-Output "$script:hostname needs to be activated by a KMS Server."
  $license_key = Get-ProductKmsClientKey
  if (-not $license_key) {
    Write-Output ("$script:product_name activations are currently not supported on GCE. Activation skipped.")
    return
  }

  # Set the KMS server.
  & cscript //nologo $env:windir\system32\slmgr.vbs /skms $script:kms_server
  # Apply the license key to the host.
  & cscript //nologo $env:windir\system32\slmgr.vbs /ipk $license_key

  if (-not (Test-TCPPort -Address $script:kms_server -Port $script:kms_server_port)) {
    Write-Output 'Could not contact activation server. Will retry activation later.'
    return
  }

  while ($retry_count -gt 0) {
    Write-Output 'Activating instance...'
    & cscript //nologo $env:windir\system32\slmgr.vbs /ato
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
      }
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

  # Server 2008 doesn't store activation status in registry; check slmgr
  if([Environment]::OSVersion.Version.Major -eq 6 -and [Environment]::OSVersion.Version.Minor -le 3)
  {
    try {
      $slmgr_status = & cscript //E:VBScript //nologo $env:windir\system32\slmgr.vbs /dli
    }
    catch {
      $active = $false
    }
    $status = $slmgr_status | Select-String -Pattern '^License Status:'
    # The initial space is to ensure "Unlicensed" does not match.
    if ($status -match ' Licensed') {
      $active = $true
    }
  }
  # All server versions newer than 2008
  else {
    try {
      $activation_status = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\Activation" -Name ProductActivationResult).ProductActivationResult
    }
    catch {
      $active = $false
    }
    # Anything other than 0x0 is a failure.
    if ($activation_status -eq '0') {
      $active = $true
    }
  }
  return $active
}

function Test-TCPPort {
  <#
    .SYNOPSIS
      Test TCP port on remote server
    .DESCRIPTION
      Use .Net Socket connection to connect to remote host and check if port is
      open.
    .PARAMETER host
      Remote host you want to check TCP port for.
    .PARAMETER port
      TCP port number you want to check.
    .RETURNS
      Return bool. $true if server is reachable at tcp port $false is not.
  #>
  param (
   [string]$Address,
   [int]$Port
  )

  $status = $false
  $socket = New-Object Net.Sockets.TcpClient
  $connection = $socket.BeginConnect($Address, $Port, $null, $null)
  $wait = $connection.AsyncWaitHandle.WaitOne(3000, $false)
  if (!$wait) {
    # Connection failed, timeout reached.
    $socket.Close()
  }
  else {
    $socket.EndConnect($connection) | Out-Null
    if (!$?) {
      Write-Host $error[0]
    }
    else {
      $status = $true
    }
    $socket.Close()
  }
  return $status
}

Activate-Instance
