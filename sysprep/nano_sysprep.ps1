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

$script:sysprep_tag = 'C:\Windows\System32\Sysprep\Sysprep_succeeded.tag'
$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'

Import-Module $PSScriptRoot\gce_base.psm1 -ErrorAction Stop

Write-Log 'Running Sysprep.'

# Delete the tag file so we don't think it already succeeded.
if (Test-Path $script:sysprep_tag) {
  Remove-Item $script:sysprep_tag
}

# While we are using the PersistAllDeviceInstalls setting to make boot faster on GCE, it's a
# good idea to forget the disks so that online/offline settings aren't applied to different
# disks on future VMs.
$disk_root = 'HKLM:\SYSTEM\CurrentControlSet\Enum\SCSI\Disk&Ven_Google&Prod_PersistentDisk'
if (Test-Path $disk_root) {
  Remove-Item -Path "$disk_root\*\Device Parameters\Partmgr" -Recurse -Force
}

# Do some clean up.
_ClearTempFolders
_ClearEventLogs

$run_startup_scripts = "powershell.exe -NoProfile -NoLogo -ExecutionPolicy Unrestricted -File '${script:gce_install_dir}\sysprep\nano_instance_setup.ps1' -Specialize"
& schtasks /create /tn GCEStartup /tr $run_startup_scripts /sc onstart /ru System /f

New-Item -Path 'C:\Windows\System32\Sysprep' -Type Directory -ErrorAction Continue
New-Item -Path 'C:\Windows\System32\Sysprep\Sysprep_succeeded.tag' -Type File
Write-Log 'Shutting down.'
Stop-Computer
