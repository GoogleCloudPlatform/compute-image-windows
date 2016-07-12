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
    Setup GCE instance.

  .DESCRIPTION
    This powershell script setups a GCE instance during and post sysprep.
    Some of the task performed by the scripts are:
      Change the hostname to match the GCE hostname
      Disable default Administrator user
      Cleanup eventviewer
      Cleanup temp files
      Activate the GCE instance
      Set up the administrative username and password
  .EXAMPLE
    instance_setup.ps1
  .EXAMPLE
    instance_setup.ps1 -specialize
  .EXAMPLE
    instance_setup.ps1 -test

  #requires -version 3.0
#>
[CmdletBinding()]
param (
  [Parameter(HelpMessage = 'Sysprep specialize phase.')]
  [switch] $specialize=$false
)

Set-StrictMode -Version Latest

# Default Values
$script:disable_built_in_user = $false
$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'
$script:kms_server = 'kms.windows.googlecloud.com'
$script:kms_server_port = 1688
$script:instance_setup_script_loc = "$script:gce_install_dir\sysprep\instance_setup.ps1"
$script:metadata_script_loc = "$script:gce_install_dir\agent\GCEMetadataScripts.exe"
$script:setupscripts_dir_loc = "$env:WinDir\Setup\Scripts"
$script:setupcomplete_loc = "$script:setupscripts_dir_loc\SetupComplete.cmd"
$script:show_msgs = $false
$script:write_to_serial = $false

# Import Modules
try {
  Import-Module $PSScriptRoot\gce_base.psm1 -ErrorAction Stop
}
catch [System.Management.Automation.ActionPreferenceStopException] {
  Write-Host $_.Exception.GetBaseException().Message
  Write-Host ("Unable to import GCE module from $PSScriptRoot. " +
      'Check error message, or ensure module is present.')
  exit 2
}


# Functions
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

  Write-Log 'Checking instance license activation status.'
  if (Verify-ActivationStatus) {
    Write-Log "$global:hostname is already licensed and activated."
    return
  }
  Write-Log "$global:hostname needs to be activated by a KMS Server."
  # Get the LicenseKey.
  $license_key = Get-ProductKmsClientKey
  if (-not $license_key) {
    Write-Log 'Could not get the License Key for the instance. Activation skipped.'
    return
  }
  # Set the KMS server.
  _RunExternalCMD cscript //nologo $env:windir\system32\slmgr.vbs /skms $script:kms_server
  # Apply the license key to the host.
  _RunExternalCMD cscript //nologo $env:windir\system32\slmgr.vbs /ipk $license_key

  # Check if the product can be activated.
  $reg_query = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion'
  $get_product_details = (Get-ItemProperty -Path $reg_query -Name ProductName).ProductName
  $known_editions_regex = "Windows (Web )?Server (2008 R2|2012|2012 R2)"
  if ($get_product_details -notmatch $known_editions_regex) {
    Write-Log ("$get_product_details activations are currently not " +
        'supported on GCE. Activation request will be skipped.')
    return
  }

  # Check if the KMS server is reachable.
  if (_TestTCPPort -host $script:kms_server -port $script:kms_server_port) {
    # KMS Server is reachable try to activate the server.
    while ($retry_count -lt 0) {
      # Activate the instance.
      Write-Log 'Activating instance ...'
      _RunExternalCMD cscript //nologo $env:windir\system32\slmgr.vbs /ato
      # Helps to avoid activation failures.
      Start-Sleep -Seconds 1
      # Check activation status.
      if (Verify-ActivationStatus) {
        Write-Log 'Activation successful.' -important
        break
      }
      else {
        Write-Log 'Activation failed.'
        $retry_count = $retry_count - 1
      }
      if ($retry_count -gt 0) {
        Write-Log "Retrying activation. Will try $retry_count more time(s)"
      }
    }
  }
  else {
    Write-Log 'Could not contact activation server. Will retry activation later.'
  }
}


function Change-InstanceName {
  <#
    .SYNOPSIS
      Changes the machine name for GCE Instance
    .DESCRIPTION
      If metadata server is reachable get the instance name for the machine and
      rename.
  #>

  Write-Log 'Getting hostname from metadata server.'

  if ((Get-CimInstance Win32_BIOS).Manufacturer -cne 'Google') {
    Write-Log 'Not running in a Google Compute Engine VM.' -error
    return
  }

  $count = 1
  do {
    $hostname_parts = (_FetchFromMetaData -property 'hostname') -split '\.'
    if ($hostname_parts.Length -le 1) {
      Write-Log "Waiting for metadata server, attempt $count."
      Start-Sleep -Seconds 1
    }
    if ($count++ -ge 60) {
      Write-Log 'There is likely a problem with the network.' -error
      return
    }
  }
  while ($hostname_parts.Length -le 1)
  
  $new_hostname = $hostname_parts[0]
  Write-Log "Changing hostname from $global:hostname to $new_hostname."
  try {
    Rename-Computer -NewName $new_hostname -ErrorAction Stop
  }
  catch {
    _PrintError
    return
  }
  Write-Log "Renamed from $global:hostname to $new_hostname."
  $global:hostname = $new_hostname
}


function Change-InstanceProperties {
  <#
    .SYNOPSIS
      Apply GCE specific changes.
    .DESCRIPTION
      Apply GCE specific changes to this instance.
  #>

  # Set all Adapters to get IP from DHCP.
  $nics = Get-WMIObject Win32_NetworkAdapterConfiguration | where{$_.IPEnabled -eq "TRUE"}
  foreach($nic in $nics) {
    $nic.EnableDHCP()
    $nic.SetDNSServerSearchOrder()
  }

  $netkvm = Get-WmiObject Win32_NetworkAdapter -filter "ServiceName = 'netkvm'"

  # Set MTU to 1430.
  _RunExternalCMD netsh interface ipv4 set interface $netkvm.NetConnectionID mtu=1430
  Write-Log 'MTU set to 1430.'

  # Adding persistent route to metadata netblock via netkvm adapter.
  _RunExternalCMD route /p add 169.254.0.0 mask 255.255.0.0 0.0.0.0 if $netkvm.InterfaceIndex metric 1
  Write-Log 'Added persistent route to metadata netblock via netkvm adapter.'

  # Set minimum password length.
  _RunExternalCMD net accounts /MINPWLEN:8

  # Enable automatic update.
  try {
    Write-Log 'Enabling automatic updates.'
    $updates_setting = (New-Object -com 'Microsoft.Update.AutoUpdate').Settings
    $updates_setting.NotificationLevel = 4
    $updates_setting.Save()
  }
  catch {
    _PrintError
  }

  # Enable access to Windows administrative file share.
  Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
      -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Force
}


function Enable-RemoteDesktop {
  <#
    .SYNOPSIS
      Enable RDP on the instance.
    .DESCRIPTION
      Modify the Terminal Server registry properties and restart Terminal
      services.
  #>

  $ts_path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
  if (-not (Test-Path $ts_path)) {
    return
  }
  # Enable remote desktop.
  Set-ItemProperty -Path $ts_path -Name 'fDenyTSConnections' -Value 0 -Force
  Write-Log 'Enabled remote desktop.'

  # Disable Ctrl + Alt + Del.
  Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
      -Name 'DisableCAD' -Value 1 -Force
  Write-Log 'Disabled Ctrl + Alt + Del.'

  # Restart Terminal Service service via cmdlets.
  try {
    # Enable firewall rule.
    Write-Log 'Enable RDP firewall rules.'
    _RunExternalCMD netsh advfirewall firewall set rule group="remote desktop" new enable=Yes
    # Restart services.
    Write-Log 'Restarting Terminal Service services, to enable RDP.'
    Restart-Service UmRdpService,TermService -Force | Out-Null
    Write-Log 'Enabled Remote Desktop.'
  }
  catch {
    _PrintError
    Write-Log ("Can't restart Terminal Service on $global:hostname. " +
        'Try restarting this instance from the Cloud Console.')
  }
}


function Configure-WinRM {
  <#
    .SYNOPSIS
      Setup WinRM on the instance.
    .DESCRIPTION
      Create a self signed cert to use with a HTTPS WinRM endpoint and restart the WinRM service.
  #>

  Write-Log 'Configuring WinRM...'
  # We're using makecert here because New-SelfSignedCertificate isn't full featured in anything 
  # less than Win10/Server 2016, makecert is installed during imaging on non 2016 machines.
  if (Test-Path $env:windir\makecert.exe) {
    # SHA1 self signed cert using hostname as the SubjectKey and name installed to LocalMachine\My store
    # with enhanced key usage object identifiers of Server Authentication and Client Authentication.
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa386968(v=vs.85).aspx
    $eku = "1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2"
    _RunExternalCMD $env:windir\makecert.exe -r -a SHA1 -sk "$(hostname)" -n "CN=$(hostname)" -ss My -sr LocalMachine -eku $eku
    $cert = Get-ChildItem Cert:\LocalMachine\my | Where-Object {$_.Subject -eq "CN=$(hostname)"}
  }
  else {
    $cert = New-SelfSignedCertificate -DnsName "$(hostname)" -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)
  }
  
  # Configure winrm HTTPS transport using the created cert.
  $config = '@{Hostname="'+ $(hostname) + '";CertificateThumbprint="' + $cert.Thumbprint + '";port="5986"}'
  _RunExternalCMD winrm create winrm/config/listener?Address=*+Transport=HTTPS $config
  # Open the firewall.
  $rule = "Windows Remote Management (HTTPS-In)"
  _RunExternalCMD netsh advfirewall firewall add rule profile=any name=$rule dir=in localport=5986 protocol=TCP action=allow
  
  Restart-Service WinRM
  Write-Log 'Setup of WinRM complete.'
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
    _PrintError
    Write-Log 'Failed to get the product details. Skipping activation.'
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
    # Default
    default {
      Write-Log ('Unable to determine the correct KMS Client Key for ' +
          $get_product_details + '; no supported matches found for GCE.')
    }
  }
  return $license_key
}


function Disable-Administrator {
  <#
    .SYNOPSIS
      Disables the default Administrator user.
    .DESCRIPTION
      This function gives the built-in "Administrator" account a random password
      and disables it.
  #>
  try {
    Write-Log "Setting random password for Administrator account."
    $password = _GenerateRandomPassword
    _RunExternalCMD net user Administrator $password
    _RunExternalCMD net user Administrator /ACTIVE:NO
    Write-Log "Disabled Administrator account."
  }
  catch {
    _PrintError
    Write-Log "Failed to disable Administrator account." -error
  }
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
    $slmgr_status = _RunExternalCMD cscript //nologo C:\Windows\system32\slmgr.vbs /dli
  }
  catch {
    _PrintError
    return $active
  }
  # Check the output.
  $status = $slmgr_status.Split("`n") | Select-String -Pattern '^License Status:'
  Write-Log "Activation status - $status"
  if ($status -match "Licensed") {
    $active = $true
  }
  return $active
}


# Check if COM1 exists.
if (-not ($global:write_to_serial)) {
  Write-Log 'COM1 does not exist on this machine. Logs will not be written to GCE console.' -warning
}

# Check the args.
if ($specialize) {
  Write-Log 'Starting sysprep specialize phase.'

  Change-InstanceName
  Change-InstanceProperties

  # Create setupcomplete.cmd to launch second half of instance setup.
  # When Windows setup completes (after the sysprep OOBE phase), it looks
  # for the file SetupComplete.cmd and automatically runs it; we
  # will use it to launch this script a second time without the -specialize
  # flag to run the second half of instance setup.
  if (-not (Test-Path $script:setupscripts_dir_loc)) {
    New-Item -ItemType Directory -Path $script:setupscripts_dir_loc
  }
  @"
$PSHome\powershell.exe -NoProfile -NoLogo -ExecutionPolicy Unrestricted -File "$script:instance_setup_script_loc"
"@ | Set-Content -Path $script:setupcomplete_loc -Force

  try {
    # Call startup script during sysprep specialize phase.
    _RunExternalCMD $script:metadata_script_loc 'specialize'
  }
  catch {
    _PrintError
  }

  Write-Log 'Finished with sysprep specialize phase, restarting...'
}
else {
  Disable-Administrator
  Activate-Instance
  Enable-RemoteDesktop
  Configure-WinRM
  
  # Schedule startup script.
  Write-Log 'Adding startup scripts from metadata server.'
  $run_startup_scripts = "$script:gce_install_dir\metadata_scripts\run_startup_scripts.cmd"
  _RunExternalCMD schtasks /create /tn GCEStartup /tr "'$run_startup_scripts'" /sc onstart /ru System /f
  _RunExternalCMD schtasks /run /tn GCEStartup
  
  Write-Log "Instance setup finished. $global:hostname is ready to use." -important

  if (Test-Path $script:setupcomplete_loc) {
    Remove-Item -Path $script:setupcomplete_loc -Force
  }
}
