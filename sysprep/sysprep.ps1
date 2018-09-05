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
    Sysprep a Windows Image to be used as a GCE Instance.
  .DESCRIPTION
    This powershell script runs some cleanup routines and goes through a
    checklist before performing a sysprep on a windows host the script is being
    executed. This ensure's that the instance is in a clean state before a
    sysprep is initiated.
    Some of the task performed by the scripts are:
      Cleanup temp files
      Cleanup eventviewer
      Cleanup self signed certs (RDP, WinRM)
      Make sure all important files used by GCE instance setup are present.
    A valid sysprep answer file should be specified when the script is called
    or present in the source directory.
    IMPORTANT : Any execution changes in this script should be reflected in the
    appropriate test cases. This script should only be run from the command
    prompt.
  .PARAMETER ans_file
    sysprep answer file.
    Alias unattended
  .PARAMETER scripts_location
    Location of scripts from where they will be executed. This is local to the
    GCE image and scripts are called from this location during sysprep
    operation, the default is c:\. If you change this location make sure you
    also change the <ans_file>.xml file to reflect these changes.
    Alias destination
  .PARAMETER no_shutdown
    Don't shutdown after sysprep completes.
    Alias NoShutdown
  .PARAMETER help
    Print help message which is derived from the script definition.

  #requires -version 3.0
#>
[CmdletBinding()]
param (
  [Parameter(HelpMessage = 'XML answer file for sysprep.exe.')]
  [alias('unattended')]
  $ans_file,

  [Parameter(HelpMessage = 'Destination dir from where scripts are executed.')]
  [alias('destination')]
  $scripts_location = 'C:\Program Files\Google\Compute Engine',

  [Parameter(HelpMessage = 'Location to generate modified answer file. ' +
             'Ignored if an answer file is specified.')]
  [alias('generated')]
  $generated_ans_file = "$env:WinDir\Panther\unattend.xml",

  [Parameter(HelpMessage = "Don't shutdown after sysprep completes.")]
  [alias('NoShutdown')]
  [switch] $no_shutdown=$false,

  [Parameter(HelpMessage = 'Display help message.')]
  [switch] $help=$false
)

# ErrorAction
$ErrorActionPreference = 'Stop'

# Script Default Values
$global:logger = 'GCESysprep'
$script:hostname = [System.Net.Dns]::GetHostName()
$script:psversion = $PSVersionTable.PSVersion.Major
$script:sysprep_dir = "$scripts_location\sysprep"
$script:sysprep_tag = 'C:\Windows\System32\Sysprep\Sysprep_succeeded.tag'

# Check if the help parameter was called.
if ($help) {
  Get-Help $MyInvocation.InvocationName -Detailed
  exit
}

# Import Modules
try {
  Import-Module $PSScriptRoot\gce_base.psm1 -ErrorAction Stop 3> $null
}
catch [System.Management.Automation.ActionPreferenceStopException] {
  Write-Host $_.Exception.GetBaseException().Message
  Write-Host ("Unable to import GCE module from $PSScriptRoot. " +
    'Check error message, or ensure module is present.')
  exit 2
}

# Check if the script is running elevated.
if (-not(_TestAdmin)) {
  $script:show_msgs = $true
  Write-Log 'Script is not running in a elevated prompt.'
  Write-Log 'Re-running as Administrator.'
  $command_definition = $MyInvocation.MyCommand.Definition
  $script_args = @('-ExecutionPolicy', 'Unrestricted', '-File', "`"$command_definition`"")
  foreach ($arg_name in $PSBoundParameters.Keys) {
    $value = $PSBoundParameters[$arg_name]
    $script_args = $script_args + @("-$arg_name", "`"$value`"")
  }

  $new_process = New-Object System.Diagnostics.ProcessStartInfo 'PowerShell'
  $new_process.Arguments = $script_args
  $new_process.WorkingDirectory = $Pwd.Path

  # Indicate that the process should be elevated.
  $new_process.Verb = 'runas'

  # Start the new process.
  [System.Diagnostics.Process]::Start($new_process)

  # Exit from the current, unelevated, process.
  exit
}

Write-Log 'Beginning GCESysprep.'

# Check Unattended.xml file.
if (-not($ans_file)) {
  Write-Log 'No answer file was specified. Using default file.'
  $ans_file = "$script:sysprep_dir\unattended.xml"
}

# Run Sysprep
try {
  # Delete the startup task so it doesn't fire before sysprep completes.
  Invoke-ExternalCommand schtasks /delete /tn GCEStartup /f -ErrorAction SilentlyContinue

  # Do some clean up.
  Clear-TempFolders
  Clear-EventLogs

  # Delete the tag file so we don't think it already succeeded.
  if (Test-Path $script:sysprep_tag) {
    Remove-Item $script:sysprep_tag
  }

  # Run sysprep.
  Invoke-ExternalCommand C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /quit /unattend:$ans_file

  Write-Log 'Waiting for sysprep to complete.'
  while (-not (Test-Path $script:sysprep_tag)) {
    Start-Sleep -Seconds 15
  }

  Write-Log 'Setting new startup command.'
  Set-ItemProperty -Path HKLM:\SYSTEM\Setup -Name CmdLine -Value "`"$PSScriptRoot\windeploy.cmd`""

  Write-Log 'Forgetting persistent disks.'
  # While we are using the PersistAllDeviceInstalls setting to make boot faster on GCE, it's a
  # good idea to forget the disks so that online/offline settings aren't applied to different
  # disks on future VMs.
  $disk_root = 'HKLM:\SYSTEM\CurrentControlSet\Enum\SCSI\Disk&Ven_Google&Prod_PersistentDisk'
  if (Test-Path $disk_root) {
    Remove-Item -Path "$disk_root\*\Device Parameters\Partmgr" -Recurse -Force
  }

  Write-Log 'Clearing self signed certs.'
  @('Cert:\LocalMachine\Remote Desktop', 'Cert:\LocalMachine\My') | ForEach-Object {
    if (Test-Path $_) {
      Get-ChildItem $_ | Where-Object {$_.Subject -eq $_.Issuer} | Remove-Item
    }
  }

  if ($no_shutdown) {
    Write-Log 'GCESysprep complete, not shutting down.'
    exit 0
  }

  Write-Log 'Shutting down.'
  Invoke-ExternalCommand shutdown /s /t 00 /d p:2:4 /f
}
catch {
  _PrintError
  exit 1
}
