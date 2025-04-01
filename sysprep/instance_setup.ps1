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
    Setup GCE instance.

  .DESCRIPTION
    This powershell script setups a GCE instance post sysprep.
    Some of the task performed by the scripts are:
      Change the hostname to match the GCE hostname
      Activate the GCE instance
#>

#requires -version 3.0

[CmdletBinding()]
param (
  [Parameter(HelpMessage = 'Sysprep specialize phase.')]
  [switch] $specialize=$false
)

Set-StrictMode -Version Latest

$global:logger = 'GCEInstanceSetup'
$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'
$script:gce_base_loc = "$script:gce_install_dir\sysprep\gce_base.psm1"
$script:activate_instance_script_loc = "$script:gce_install_dir\sysprep\activate_instance.ps1"
$script:setupcomplete_loc = "$env:WinDir\Setup\Scripts\SetupComplete.cmd"
$script:write_to_serial = $false

$script:metadata_script_loc = "$script:gce_install_dir\metadata_scripts\GCEMetadataScripts.exe"
$script:compatRunner = "$script:gce_install_dir\metadata_scripts\GCECompatMetadataScripts.exe"
$script:runnerV2 = "$script:gce_install_dir\agent\GCEMetadataScriptRunner.exe"

if (Test-Path $script:runnerV2) {
  $script:metadata_script_loc = $script:runnerV2
}

if (Test-Path $script:compatRunner) {
  $script:metadata_script_loc = $script:compatRunner
}

try {
  Import-Module $script:gce_base_loc -ErrorAction Stop 3> $null
}
catch [System.Management.Automation.ActionPreferenceStopException] {
  Write-Host $_.Exception.GetBaseException().Message
  Write-Host ("Unable to import GCE module $script:gce_base_loc. " +
      'Check error message, or ensure module is present.')
  exit 2
}

function Write-GuestAttributes {
  param (
    [Parameter(Mandatory=$true)]
    $Key,
    [Parameter(Mandatory=$true)]
    $Property
  )

  $request_url = '/computeMetadata/v1/instance/guest-attributes/'
  $url = "http://$global:metadata_server$request_url$Key"

  $client = _GetWebClient
  $client.Headers.Add('Metadata-Flavor', 'Google')
  $client.UploadString($url, 'PUT', $Property)
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
    if (-not (Test-Connection -Count 1 169.254.169.254 -ErrorAction SilentlyContinue)) {
      Write-Log 'Not running in a Google Compute Engine VM.' -error
      return
    }
  }

  $count = 1
  do {
    $hostname_parts = (Get-Metadata -property 'hostname') -split '\.'
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
  # Change computer name to match GCE hostname.
  # This will take effect after reboot.
  try {
    (Get-WmiObject Win32_ComputerSystem).Rename($new_hostname)
    Write-Log "Renamed from $global:hostname to $new_hostname."
    $global:hostname = $new_hostname
  }
  catch {
    Write-Log 'Unable to change hostname.'
    Write-LogError
  }
}

function Change-InstanceProperties {
  <#
    .SYNOPSIS
      Apply GCE specific changes.
    .DESCRIPTION
      Apply GCE specific changes to this instance.
  #>

  # Set all Adapters to get IP from DHCP.
  $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
  $nics | Invoke-CimMethod -Name EnableDHCP
  # A null argument sets this to just use DHCP
  $nics | Invoke-CimMethod -Name SetDNSServerSearchOrder -Arguments @{DNSServerSearchOrder=$null}
  Write-Log 'All networks set to DHCP.'

  # Find which interface type is being used
  $netkvm = Get-CimInstance Win32_NetworkAdapter -filter "ServiceName='netkvm'"
  $gvnic = Get-CimInstance Win32_NetworkAdapter -filter "ServiceName='gvnic'"
  if ($netkvm -ne $null) {
    $interface = $netkvm
    Write-Log 'VirtIO network adapter detected.'
  }
  elseif ($gvnic -ne $null) {
    $interface = $gvnic
    Write-Log 'gVNIC network adapter detected.'
    
    $gvnicVersion = "0.0"
    $gvnicDriver = "$env:SystemRoot\System32\drivers\gvnic.sys"
    if (Test-Path $gvnicDriver) {
      $gvnicVersion = (Get-Item $gvnicDriver).VersionInfo.FileVersion
    }
    
    # Disable IPv4 Large Send Offload (LSO) on Win 10, 11, and server 2022.
    $productMajorVersion = [Environment]::OSVersion.Version.Major
    $productMinorVersion = [Environment]::OSVersion.Version.Minor
    $productBuildNumber = [Environment]::OSVersion.Version.Build
    $productType = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name 'ProductType').ProductType
  
    $isWin10ClientOrLater = ($productMajorVersion -eq 10 -and $productMinorVersion -eq 0 -and $productBuildNumber -ge 10240 -and $productType -notmatch 'server')
    $isWinServer2022OrLater = ($productMajorVersion -eq 10 -and $productMinorVersion -eq 0 -and $productBuildNumber -gt 17763 -and $productType -match 'server')
    if (($isWin10ClientOrLater -or $isWinServer2022OrLater) -and $gvnicVersion -lt 2.0 ) {
      Write-Log 'Disabling GVNIC IPv4 Large Send Offload (LSO)'
      Set-NetAdapterAdvancedProperty -InterfaceDescription 'Google Ethernet Adapter' -RegistryKeyword '*LSOV2Ipv4' -RegistryValue 0

      Write-Log 'Disabling GVNIC IPv6 Large Send Offload (LSO)'
      Set-NetAdapterAdvancedProperty -InterfaceDescription 'Google Ethernet Adapter' -RegistryKeyword '*LSOV2Ipv6' -RegistryValue 0
    }
  }
  else {
    Write-Log 'Error retrieving network adapter, no gVNIC or VirtIO network adapter found.'
  }

  if ($interface -ne $null) {
    $interface | ForEach-Object {
      if ([System.Environment]::OSVersion.Version.Build -ge 10240) {
        Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -NlMtuBytes 1460
        Write-Log "MTU set to 1460 for IPv4 and IPv6 using PowerShell for interface $($_.InterfaceIndex) - $($_.Name). Build $([System.Environment]::OSVersion.Version.Build)"
      }
      else {
        Invoke-ExternalCommand netsh interface ipv4 set interface $_.NetConnectionID mtu=1460 | Out-Null
        Invoke-ExternalCommand netsh interface ipv6 set interface $_.NetConnectionID mtu=1460 | Out-Null
        Write-Log "MTU set to 1460 for IPv4 and IPv6 using netsh for interface $($_.NetConnectionID) - $($_.Name)."
      }
    }
  
    Invoke-ExternalCommand route /p add 169.254.169.254 mask 255.255.255.255 0.0.0.0 if $interface[0].InterfaceIndex metric 1 -ErrorAction SilentlyContinue
    Write-Log "Added persistent route to metadata netblock to $($interface.ServiceName) adapter."
  }
  else {
    Write-Log 'Error identifying network adapter as gVNIC or VirtIO, unable to set MTU and route to metadata server.'
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

  if (Get-Command Import-PfxCertificate -ErrorAction SilentlyContinue) {
    $tempDir = "${env:TEMP}\cert"
    New-Item $tempDir -Type Directory
    Invoke-ExternalCommand $script:gce_install_dir\tools\certgen.exe -outDir $tempDir -hostname $global:hostname

    if (-not (Test-Path "${tempDir}\cert.p12")) {
      Write-Log 'Error creating cert, unable to setup WinRM'
      return
    }
    $cert = Import-PfxCertificate -FilePath $tempDir\cert.p12 -CertStoreLocation cert:\LocalMachine\My
    Remove-Item $tempDir -Recurse
  }
  else {
    # SHA1 self signed cert using hostname as the SubjectKey and name installed to LocalMachine\My store
    # with enhanced key usage object identifiers of Server Authentication and Client Authentication.
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa386968(v=vs.85).aspx
    $eku = '1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2'
    & $script:gce_install_dir\tools\makecert.exe -r -a SHA1 -sk "${global:hostname}" -n "CN=${global:hostname}" -ss My -sr LocalMachine -eku $eku
    $cert = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object {$_.Subject -eq "CN=${global:hostname}"} | Select-Object -First 1
  }

  $xml = @"
<p:Listener xmlns:p="http://schemas.microsoft.com/wbem/wsman/1/config/listener.xsd">
<p:Enabled>True</p:Enabled>
<p:URLPrefix>wsman</p:URLPrefix>
<p:CertificateThumbPrint>$($cert.Thumbprint)</p:CertificateThumbPrint>
</p:Listener>
"@

  try {
    Write-Log 'Waiting for WinRM to be running...'
    $svcTimeout = '00:02:00'
    $svc = Get-Service -name "WinRM"
    $svc.WaitForStatus('Running',$svcTimeout)
  }
  catch {
    Write-Log 'Error - Could not start WinRM service'
    return
  }

  $sess = (New-Object -ComObject 'WSMAN.Automation').CreateSession()
  try {
    $sess.Create('winrm/config/listener?Address=*+Transport=HTTPS', $xml)
  }
  catch {
    $sess.Put('winrm/config/listener?Address=*+Transport=HTTPS', $xml)
  }

  Restart-Service WinRM
  Write-Log 'Setup of WinRM complete.'
}

function Write-Certs {
  $rdp_cert = Get-ChildItem 'Cert:\LocalMachine\Remote Desktop\' | Where-Object {$_.Subject -eq "CN=${global:hostname}"} | Select-Object -First 1
  $winrm_cert = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object {$_.Subject -eq "CN=${global:hostname}"} | Select-Object -First 1
  Write-Log "WinRM certificate details: Subject: $($winrm_cert.Subject), Thumbprint: $($winrm_cert.Thumbprint)"
  Write-Log "RDP certificate details: Subject: $($winrm_cert.Subject), Thumbprint: $($rdp_cert.Thumbprint)"

  # We ignore any errors as guest attributes may not be enabled.
  Write-GuestAttributes -Key 'hostkeys/winrm' -Property $winrm_cert.Thumbprint -ErrorAction SilentlyContinue
  Write-GuestAttributes -Key 'hostkeys/rdp' -Property $rdp_cert.Thumbprint -ErrorAction SilentlyContinue
}

# Check if COM1 exists.
if (-not ($global:write_to_serial)) {
  Write-Log 'COM1 does not exist on this machine. Logs will not be written to GCE console.'
}

Write-Log 'Enable google_osconfig_agent during the specialize configuration pass.'
Set-Service google_osconfig_agent -StartupType Automatic -Verbose -ErrorAction Continue

if ($specialize) {
  Write-Log 'Starting sysprep specialize phase.'

  Change-InstanceProperties
  Change-InstanceName
  Configure-WinRM

  try {
    Write-Log "Launching specialize phase scripts from $script:metadata_script_loc"
    # Call startup script during sysprep specialize phase.
    & $script:metadata_script_loc 'specialize'
  }
  catch {
    Write-LogError
  }

  Write-Log 'Finished with sysprep specialize phase, restarting...'
}
else {
  Write-Certs

  if (Test-Path $script:setupcomplete_loc) {
    Remove-Item -Path $script:setupcomplete_loc -Force
  }

  & $script:activate_instance_script_loc | ForEach-Object {
    Write-Log $_
  }
  
  Invoke-ExternalCommand schtasks /change /tn GCEStartup /enable -ErrorAction SilentlyContinue
  Invoke-ExternalCommand schtasks /run /tn GCEStartup
  Write-Log "Instance setup finished. $global:hostname is ready to use." -important
}
