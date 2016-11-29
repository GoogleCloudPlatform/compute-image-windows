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

[CmdletBinding()]
param (
  [Parameter(HelpMessage = 'Sysprep specialize phase.')]
  [switch] $Specialize=$false
)

Set-StrictMode -Version Latest

$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'
$script:hostname = $(hostname)

function Fetch-FromMetaData {
  param (
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [string] $property,
    [switch] $project_only = $false
  )

  $request_url = 'metadata.google.internal/computeMetadata/v1/instance/'
  if ($project_only) {
    $request_url = 'metadata.google.internal/computeMetadata/v1/project/'
  }

  $url = "http://$request_url$property"

  $client = New-Object System.Net.Http.HttpClient
  $request = New-Object System.Net.Http.HttpRequestMessage -ArgumentList @([System.Net.Http.HttpMethod]::Get, $url)
  $request.Headers.Add('Metadata-Flavor', 'Google')
  $responseMsg = $client.SendAsync($request)
  $responseMsg.Wait()

  $response = $responseMsg.Result
  if ($response.IsSuccessStatusCode) {
    $contentMsg = $responseMsg.Result.Content.ReadAsStringAsync()
    return ($contentMsg.Result).Trim()
  }
  else {
    Write-Log "Non success status code $($response.StatusCode)"
  }
}

function Write-Log {
  param (
    [parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
      [String]$msg
  )
  $timestamp = $(Get-Date)
  & "$script:gce_install_dir\tools\WriteToSerial.exe" 'COM1' "$timestamp  $msg`n"
}

function Change-InstanceName {
  Write-Log 'Getting hostname from metadata server.'
  $count = 1
  do {
    $hostname_parts = (Fetch-FromMetaData -Property 'hostname') -split '\.'
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
  Write-Log "Changing hostname from ${script:hostname} to $new_hostname."
  # Change computer name to match GCE hostname.
  # This will take effect after reboot.
  try {
    Rename-Computer $new_hostname -Force
    Write-Log "Renamed from ${script:hostname} to $new_hostname."
    $script:hostname = $new_hostname
  }
  catch {
    Write-Log 'Unable to change hostname.'
  }
}

function Change-InstanceProperties {
  # Set MTU to 1430.
  Get-NetAdapter | ForEach-Object {netsh interface ipv4 set interface $_.InterfaceIndex mtu=1430}
  Write-Log 'MTU set to 1430.'

  # Adding persistent route to metadata netblock via netkvm adapter.
  & route /p add 169.254.0.0 mask 255.255.0.0 0.0.0.0 if (Get-NetAdapter | Select-Object -First 1).InterfaceIndex metric 1
  Write-Log 'Added persistent route to metadata netblock via netkvm adapter.'

  # Enable access to Windows administrative file share.
  Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Force
}

function Configure-WinRM {
  $tempDir = "${env:TEMP}\cert"
  New-Item $tempDir -Type Directory

  & $script:gce_install_dir\tools\certgen.exe -outDir $tempDir

  if (-not (Test-Path "${tempDir}\cert.p12")) {
    Write-Log 'Error creating cert, unable to setup WinRM'
    return
  }

  $cert = Import-PfxCertificate -FilePath $tempDir\cert.p12 -CertStoreLocation cert:\LocalMachine\My

  $xml = @"
<p:Listener xmlns:p="http://schemas.microsoft.com/wbem/wsman/1/config/listener.xsd">
<p:Enabled>True</p:Enabled>
<p:URLPrefix>wsman</p:URLPrefix>
<p:CertificateThumbPrint>$($cert.Thumbprint)</p:CertificateThumbPrint>
</p:Listener>
"@

  $sess = (New-Object -ComObject 'WSMAN.Automation').CreateSession()
  try {
    $sess.Create('winrm/config/listener?Address=*+Transport=HTTPS', $xml)
  }
  catch {
    $sess.Put('winrm/config/listener?Address=*+Transport=HTTPS', $xml)
  }

  $rule = 'Windows Remote Management (HTTPS-In)'
  & netsh advfirewall firewall add rule profile=any name=$rule dir=in localport=5986 protocol=TCP action=allow
  Restart-Service WinRM
  Remove-Item $tempDir -Recurse
  Write-Log 'Setup of WinRM complete.'
}

# Check the args.
if ($specialize) {
  Change-InstanceProperties
  Change-InstanceName

  # Call startup script during sysprep specialize phase.
  & "${script:gce_install_dir}\metadata_scripts\GCEMetadataScripts.exe" 'specialize'

  $run_startup_scripts = "powershell.exe -NoProfile -NoLogo -ExecutionPolicy Unrestricted -File '${script:gce_install_dir}\sysprep\nano_instance_setup.ps1'"
  & schtasks /create /tn GCEStartup /tr $run_startup_scripts /sc onstart /ru System /f

  Restart-Computer
  exit
}

Configure-WinRM

# Schedule startup script.
Write-Log 'Adding startup scripts from metadata server.'
$run_startup_scripts = "${script:gce_install_dir}\metadata_scripts\run_startup_scripts.cmd"
& schtasks /create /tn GCEStartup /tr $run_startup_scripts /sc onstart /ru System /f
&  "${script:gce_install_dir}\metadata_scripts\run_startup_scripts.cmd"

Write-Log "Instance setup finished. ${script:hostname} is ready to use."

