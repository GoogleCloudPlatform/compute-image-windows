# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

<#
  .SYNOPSIS
    Install (or uninstall) sshd on a Windows GCE instance.
  .PARAMETER Uninstall
    If true, uninstall instead of installing.
  .PARAMETER Installfile
    Name of .msi file to pass to the installer. File should be in the same
    directory as the script.
#>

param (
    [switch] $Uninstall,
    [string] $Installfile
)

# Configuration Data
$start_pattern = '# Start Google Added Lines'
$end_pattern = '# End Google Added Lines'
$akc_path = '"C:/Program Files/Google/Compute Engine/agent/GCEAuthorizedKeysCommand.exe"'
$sshd_config_path = 'C:\ProgramData\ssh\sshd_config'

$sshd_config_text = @"

$start_pattern
AuthorizedKeysCommand $akc_path %u
AuthorizedKeysCommandUser System
PasswordAuthentication no
$end_pattern
"@

function Install-MSI {
  <#
  .SYNOPSIS
    Installs or Uninstalls from a .msi file.
  .PARAMETER Path
    The full path to the .msi file.
  .PARAMETER Uninstall
    If true, uninstall using the .msi instead of installing.
  #>
  param (
    [string] $Path,
    [switch] $Uninstall
  )

  $action = '/i'
  $operation = 'Install'
  if ($Uninstall) {
    $action = '/x'
    $operation = 'Uninstall'
  }

  Write-Output "${operation}ing OpenSSH from: $Path"

  $msi_install = Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "$action $Path /qn" -wait -PassThru
  $msi_exit_code = $msi_install.ExitCode
  if ($msi_exit_code -ne 0) {
    Write-Output "MSI $operation Failed: Exit Code: $msi_exit_code"
    Exit $msi_exit_code
  }
  Write-Output "MSI $operation Succeeded."
}

function Update-SSHDConfig {
  <#
  .SYNOPSIS
    Updates an sshd_config file.
  .DESCRIPTION
    This function removes any lines from the given sshd_config file that are
    between $start_pattern and $end_pattern as defined at the top of the
    script. If $NewContent is provided, it will be added to the end of
    the sshd_config file. In addition, the existing file will be saved
    to the same path with a .bak extention.
  .PARAMETER Path
    The full path to the sshd_config file.
  .PARAMETER NewContent
    If provided, add the contents to the end of the config file.
  #>
  param (
    [string] $Path,
    [string] $NewContent
  )

  Write-Output "Updating $Path"
  $sshd_conf = (Get-Content -Raw $Path)
  $sshd_conf = ($sshd_conf -Replace "$start_pattern[\s\S]*?$end_pattern").TrimEnd()

  if ($NewContent) {
    $sshd_conf = $sshd_conf, $NewContent
  }

  $backup_path = $Path + '.bak'

  if (Test-Path $backup_path) {
    Remove-Item -Path $backup_path
  }

  Write-Output "Saving old sshd_config file to $backup_path"
  Rename-Item -Path $Path -NewName $backup_path

  $sshd_conf | Set-Content $Path
}

$msi_path = Join-Path -Path $PSScriptRoot -ChildPath $Installfile

if ($Uninstall) {
  Install-MSI -Path $msi_path -Uninstall
  Update-SSHDConfig -Path $sshd_config_path
} else {
  Install-MSI -Path $msi_path
  Update-SSHDConfig -Path $sshd_config_path -NewContent $sshd_config_text
  Write-Output 'Restarting sshd'
  Restart-Service sshd
}

