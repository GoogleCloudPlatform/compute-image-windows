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
$script:gce_base_loc = "$script:gce_install_dir\sysprep\gce_base.psm1"
$script:instance_setup_script_loc = "$script:gce_install_dir\sysprep\instance_setup.ps1"
$script:activate_instance_script_loc = "$script:gce_install_dir\sysprep\activate_instance.ps1"
$script:metadata_script_loc = "$script:gce_install_dir\metadata_scripts\GCEMetadataScripts.exe"
$script:setupscripts_dir_loc = "$env:WinDir\Setup\Scripts"
$script:setupcomplete_loc = "$script:setupscripts_dir_loc\SetupComplete.cmd"
$script:show_msgs = $false
$script:write_to_serial = $false

# Import Modules
try {
  Import-Module $script:gce_base_loc -ErrorAction Stop
}
catch [System.Management.Automation.ActionPreferenceStopException] {
  Write-Host $_.Exception.GetBaseException().Message
  Write-Host ("Unable to import GCE module $script:gce_base_loc. " +
      'Check error message, or ensure module is present.')
  exit 2
}


# Functions
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
  # Change computer name to match GCE hostname.
  # This will take effect after reboot.
  try {
    (Get-WmiObject Win32_ComputerSystem).Rename($new_hostname)
    Write-Log "Renamed from $global:hostname to $new_hostname."
    $global:hostname = $new_hostname
  }
  catch {
    Write-Log 'Unable to change hostname.'
    _PrintError
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
  $nics = Get-WMIObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq 'TRUE'}
  foreach($nic in $nics) {
    $nic.EnableDHCP()
    $nic.SetDNSServerSearchOrder()
  }

  $netkvm = Get-WmiObject Win32_NetworkAdapter -filter "ServiceName = 'netkvm'"

  # Set MTU to 1430.
  _RunExternalCMD netsh interface ipv4 set interface $netkvm.NetConnectionID mtu=1430
  Write-Log 'MTU set to 1430.'

  # Adding persistent route to metadata netblock via netkvm adapter.
  _RunExternalCMD route /p add 169.254.0.0 mask 255.255.0.0 0.0.0.0 if $netkvm.InterfaceIndex metric 1 -ErrorAction SilentlyContinue
  Write-Log 'Added persistent route to metadata netblock via netkvm adapter.'

  # Set minimum password length.
  _RunExternalCMD net accounts /MINPWLEN:8

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
    _RunExternalCMD netsh advfirewall firewall set rule group='remote desktop' new enable=Yes
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
  try {
    $cert = New-SelfSignedCertificate -DnsName "$(hostname)" -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)
  }
  catch {
    # SHA1 self signed cert using hostname as the SubjectKey and name installed to LocalMachine\My store
    # with enhanced key usage object identifiers of Server Authentication and Client Authentication.
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa386968(v=vs.85).aspx
    $eku = '1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2'
    & $script:gce_install_dir\tools\makecert.exe -r -a SHA1 -sk "$(hostname)" -n "CN=$(hostname)" -ss My -sr LocalMachine -eku $eku
    $cert = Get-ChildItem Cert:\LocalMachine\my | Where-Object {$_.Subject -eq "CN=$(hostname)"} | Select-Object -First 1
  }
  # Configure winrm HTTPS transport using the created cert.
  $config = '@{Hostname="'+ $(hostname) + '";CertificateThumbprint="' + $cert.Thumbprint + '";Port="5986"}'
  _RunExternalCMD winrm create winrm/config/listener?Address=*+Transport=HTTPS $config -ErrorAction SilentlyContinue
  if ($LASTEXITCODE -ne 0) {
    # Listener has already been setup, we need to edit it in place.
    _RunExternalCMD winrm set winrm/config/listener?Address=*+Transport=HTTPS $config
  }
  # Open the firewall.
  $rule = 'Windows Remote Management (HTTPS-In)'
  _RunExternalCMD netsh advfirewall firewall add rule profile=any name=$rule dir=in localport=5986 protocol=TCP action=allow

  Restart-Service WinRM
  Write-Log 'Setup of WinRM complete.'
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
    Write-Log 'Setting random password for Administrator account.'
    $password = _GenerateRandomPassword
    _RunExternalCMD net user Administrator $password
    _RunExternalCMD net user Administrator /ACTIVE:NO
    Write-Log 'Disabled Administrator account.'
  }
  catch {
    _PrintError
    Write-Log 'Failed to disable Administrator account.' -error
  }
}


$create_process_source = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using System.IO;

namespace CreateProcess
{
  public class Win32
  {
    const UInt32 INFINITE = 0xFFFFFFFF;
    const UInt32 WAIT_FAILED = 0xFFFFFFFF;

    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFO
    {
      public Int32 cb;
      public String lpReserved;
      public String lpDesktop;
      public String lpTitle;
      public Int32 dwX;
      public Int32 dwY;
      public Int32 dwXSize;
      public Int32 dwYSize;
      public Int32 dwXCountChars;
      public Int32 dwYCountChars;
      public Int32 dwFillAttribute;
      public Int32 dwFlags;
      public Int16 wShowWindow;
      public Int16 cbReserved2;
      public IntPtr lpReserved2;
      public IntPtr hStdInput;
      public IntPtr hStdOutput;
      public IntPtr hStdError;        
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
      public IntPtr hProcess;
      public IntPtr hThread;
      public Int32 dwProcessId;
      public Int32 dwThreadId;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern Boolean LogonUser
    (
      String lpszUserName,
      String lpszDomain,
      String lpszPassword,
      Int32 dwLogonType,
      Int32 dwLogonProvider,
      out IntPtr phToken
    );

    [DllImport("advapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern Boolean CreateProcessAsUser
    (
      IntPtr hToken,
      String lpApplicationName,
      String lpCommandLine,
      IntPtr lpProcessAttributes,
      IntPtr lpThreadAttributes,
      Boolean bInheritHandles,
      Int32 dwCreationFlags,
      IntPtr lpEnvironment,
      String lpCurrentDirectory,
      ref STARTUPINFO lpStartupInfo,
      out PROCESS_INFORMATION lpProcessInformation
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern UInt32 WaitForSingleObject
    (
      IntPtr hHandle,
      UInt32 dwMilliseconds
    );

    [DllImport("kernel32", SetLastError=true)]
    public static extern Boolean CloseHandle (IntPtr handle);

    public static void CreateProcessAsUser(string strCommand, string strDomain, string strName, string strPassword)
    {
      PROCESS_INFORMATION processInfo = new PROCESS_INFORMATION();
      STARTUPINFO startInfo = new STARTUPINFO();
      Boolean bResult = false;
      IntPtr hToken = IntPtr.Zero;
      UInt32 uiResultWait = WAIT_FAILED;

      try
      {
        // Logon user
        bResult = Win32.LogonUser(
          strName,
          strDomain,
          strPassword,
          2,
          0,
          out hToken
        );
        if (!bResult) { 
          throw new Exception("Logon error"); 
        }

        // Create process
        startInfo.cb = Marshal.SizeOf(startInfo);

        bResult = Win32.CreateProcessAsUser(
          hToken,
          null,
          strCommand,
          IntPtr.Zero,
          IntPtr.Zero,
          false,
          0,
          IntPtr.Zero,
          null,
          ref startInfo,
          out processInfo
        );
        if (!bResult) {
          throw new Exception("CreateProcessAsUser error"); 
        }

        // Wait for process to end
        uiResultWait = WaitForSingleObject(processInfo.hProcess, INFINITE);
        if (uiResultWait == WAIT_FAILED) { 
          throw new Exception("WaitForSingleObject error");
        }
      }
      finally
      {
        CloseHandle(hToken);
        CloseHandle(processInfo.hProcess);
        CloseHandle(processInfo.hThread);
      }
    }
  }
}
'@


function Set-SQLServerName {
  <#
    .SYNOPSIS
      Set SQL @@SERVERNAME to match hostname
    .DESCRIPTION
      Set SQL @@SERVERNAME to match hostname if SQL Server is installed, otherwise return
  #>

  if (-not (Get-Command 'sqlcmd.exe' -ErrorAction SilentlyContinue)) {
    return
  }
  Write-Log "Setting SQL servername to $global:hostname"
  # We have to do this as SYSTEM has no access to the SQL DB.
  # Disable-Administrator runs after this step.
  $password = 'P@ssw0rd!'
  & net user Administrator $password
  & net user Administrator /ACTIVE:YES

  try {
    # We have to call CreateProcessAsUser as this script runs as SYSTEM.
    Add-Type -TypeDefinition $create_process_source -Language CSharp
    $cmd = "sqlcmd.exe -S. -E -Q `"IF @@servername = '$global:hostname' RETURN; exec sp_dropserver @@servername; exec sp_addserver '$global:hostname', local`""
    [CreateProcess.Win32]::CreateProcessAsUser($cmd, '.', 'Administrator', $password)
  } catch {
    _PrintError
  }
}


# Check if COM1 exists.
if (-not ($global:write_to_serial)) {
  Write-Log 'COM1 does not exist on this machine. Logs will not be written to GCE console.' -warning
}

# Check the args.
if ($specialize) {
  Write-Log 'Starting sysprep specialize phase.'

  Change-InstanceProperties
  Change-InstanceName
  Set-SQLServerName

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
  $activate_job = Start-Job -FilePath $script:activate_instance_script_loc 
  Disable-Administrator
  Enable-RemoteDesktop
  Configure-WinRM
  
  Wait-Job $activate_job | Receive-Job | ForEach-Object {
    Write-Log $_
  }

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
