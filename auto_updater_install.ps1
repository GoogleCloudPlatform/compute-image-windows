$ScheduleService = New-Object -ComObject("Schedule.Service")
$ScheduleService.Connect()

$task = $ScheduleService.NewTask(0)
$task.RegistrationInfo.Description = 'Keeps core Compute Engine packages up to date' 
$task.Settings.Enabled = $true
$task.Settings.AllowDemandStart = $true
$task.Principal.RunLevel = 1

$action = $task.Actions.Create(0)
$action.Path = 'powershell.exe'
$action.Arguments = '-ExecutionPolicy Bypass -NonInteractive -NoProfile -File "C:\Program Files\Google\Compute Engine\tools\auto_updater.ps1"'

# Run task 5 minutes after boot, then every day indefinitely 
$boot_trigger = $task.Triggers.Create(8)
$boot_trigger.Delay = 'PT5M'
$boot_trigger.Repetition.Interval = 'P1D'

$folder = $ScheduleService.GetFolder('\')
$folder.RegisterTaskDefinition('Compute Engine Auto Updater', $task, 6, 'System', $null, 5)
