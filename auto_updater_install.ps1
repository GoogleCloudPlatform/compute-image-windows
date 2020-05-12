#  Copyright 2017 Google Inc. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

$ScheduleService = New-Object -ComObject('Schedule.Service')
$ScheduleService.Connect()

$task = $ScheduleService.NewTask(0)
$task.RegistrationInfo.Description = 'Keeps core Compute Engine packages up to date'
$task.Settings.Enabled = $false
$task.Settings.AllowDemandStart = $true
$task.Principal.RunLevel = 1

$action = $task.Actions.Create(0)
$action.Path = 'powershell.exe'
$action.Arguments = "-ExecutionPolicy Bypass -NonInteractive -NoProfile -File `"${env:ProgramFiles}\Google\Compute Engine\tools\auto_updater.ps1`""

# Run task 5 minutes after boot, then every day indefinitely
$boot_trigger = $task.Triggers.Create(8)
$boot_trigger.Delay = 'PT5M'
$boot_trigger.Repetition.Interval = 'P1D'

$folder = $ScheduleService.GetFolder('\')
$folder.RegisterTaskDefinition('Compute Engine Auto Updater', $task, 6, 'System', $null, 5)
