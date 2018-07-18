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
    GCE Base Modules.
  .DESCRIPTION
    Base modules needed for GCE Powershell scripts to run scripts to run.

  #requires -version 3.0
#>

# Default Values
$global:write_to_serial = $false
$global:metadata_server = 'metadata.google.internal'
$global:hostname = [System.Net.Dns]::GetHostName()
$global:log_file = $null

# Functions
function _AddToPath {
 <#
    .SYNOPSIS
      Adds GCE tool dir to SYSTEM PATH
    .DESCRIPTION
      This is a helper function which adds location to path
  #>
  param (
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('path')]
      $path_to_add
  )

  # Check if folder exists on the file system.
  if (!(Test-Path $path_to_add)) {
    Write-Log "$path_to_add does not exist, cannot be added to $env:PATH."
    return
  }

  try {
    $path_reg_key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $current_path = (Get-ItemProperty $path_reg_key).Path
    $check_path = ($current_path).split(';') | ? {$_ -like $path_to_add}
  }
  catch {
    Write-Log 'Could not read path from the registry.'
    _PrintError
  }
  # See if the folder is already in the path.
  if ($check_path) {
    Write-Log 'Folder already in system path.'
  }
  else {
    try {
      Write-Log "Adding $path_to_add to SYSTEM path."
      $new_path = $current_path + ';' + $path_to_add
      $env:Path = $new_path
      Set-ItemProperty $path_reg_key -name 'Path' -value $new_path
    }
    catch {
      Write-Log 'Failed to add to SYSTEM path.'
      _PrintError
    }
  }
}


function Clear-EventLogs {
  <#
    .SYNOPSIS
      Clear all eventlog enteries.
    .DESCRIPTION
      This uses the Get-Eventlog and Clear-EventLog powershell functions to
      clean the eventlogs for a machine.
  #>

  Write-Log 'Clearing events in EventViewer.'
  Get-WinEvent -ListLog * |
    Where-Object {($_.IsEnabled -eq 'True') -and ($_.RecordCount -gt 0)} |
    ForEach-Object {
      try{[System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)}catch{}
    }
}


function Clear-TempFolders {
  <#
    .SYNOPSIS
      Delete all files from temp folder location.
    .DESCRIPTION
      This function calls an array variable which contain location of all the
      temp files and folder which needs to be cleared out. We use the
      Remove-Item routine to delete the files in the temp directories.
  #>

  # Array of files and folder that need to be deleted.
  @("C:\Windows\Temp\*", "C:\Windows\Prefetch\*",
    "C:\Documents and Settings\*\Local Settings\temp\*\*",
    "C:\Users\*\Appdata\Local\Temp\*\*",
    "C:\Users\*\Appdata\Local\Microsoft\Internet Explorer\*",
    "C:\Users\*\Appdata\LocalLow\Temp\*\*",
    "C:\Users\*\Appdata\LocalLow\Microsoft\Internet Explorer\*") | ForEach-Object {
    if (Test-Path $_) {
      Remove-Item $_ -recurse -force -ErrorAction SilentlyContinue
    }
  }
}


function Get-MetaData {
  <#
    .SYNOPSIS
      Get attributes from GCE instances metadata.
    .DESCRIPTION
      Use Net.WebClient to fetch data from metadata server.
    .PARAMETER property
      Name of instance metadata property we want to fetch.
    .PARAMETER filename
      Name of file to save metadata contents to.  If left out, returns contents.
    .EXAMPLE
      $hostname = _FetchFromMetaData -property 'hostname'
      Get-MetaData -property 'startup-script' -file 'script.bat'
  #>
  param (
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    $property,
    $filename = $null,
    [switch] $project_only = $false,
    [switch] $instance_only = $false
  )

  $request_url = '/computeMetadata/v1/instance/'
  if ($project_only) {
    $request_url = '/computeMetadata/v1/project/'
  }

  $url = "http://$global:metadata_server$request_url$property"

  try {
    $client = _GetWebClient
    #Header
    $client.Headers.Add('Metadata-Flavor', 'Google')
    # Get Data
    if ($filename) {
      $client.DownloadFile($url, $filename)
      return
    }
    else {
      return ($client.DownloadString($url)).Trim()
    }
  }
  catch [System.Net.WebException] {
    if ($project_only -or $instance_only) {
      Write-Log "$property value is not set or metadata server is not reachable."
    }
    else {
      return (_FetchFromMetaData -project_only -property $property -filename $filename)
    }
  }
  catch {
    Write-Log "Unknown error in reading $url."
    _PrintError
  }
}


function _GenerateRandomPassword {
  <#
    .SYNOPSIS
      Generates random password which meet windows complexity requirements.
    .DESCRIPTION
      This function generates a password to be set on built-in account before
      it is disabled.
    .OUTPUTS
      Returns String
    .EXAMPLE
      _GeneratePassword
  #>

  # Define length of the password. Maximum and minimum.
  [int] $pass_min = 20
  [int] $pass_max = 35
  [string] $random_password = $null

  # Random password length should help prevent masking attacks.
  $password_length = Get-Random -Minimum $pass_min -Maximum $pass_max

  # Choose a set of ASCII characters we'll use to generate new passwords from.
  $ascii_char_set = $null
  for ($x=33; $x -le 126; $x++) {
    $ascii_char_set+=,[char][byte]$x
  }

  # Generate random set of characters.
  for ($loop=1; $loop -le $password_length; $loop++) {
    $random_password += ($ascii_char_set | Get-Random)
  }
  return $random_password
}


function _GetCOMPorts  {
  <#
    .SYNOPSIS
      Get available serial ports. Check if a port exists, if yes returns $true
    .DESCRIPTION
      This function is used to check if a port exists on this machine.
    .PARAMETER $portname
      Name of the port you want to check if it exists.
    .OUTPUTS
      [boolean]
    .EXAMPLE
      _GetCOMPorts
  #>

  param (
    [parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
      [String]$portname
  )

  $exists = $false
  try {
    # Read available COM ports.
    $com_ports = [System.IO.Ports.SerialPort]::getportnames()
    if ($com_ports -match $portname) {
      $exists = $true
    }
  }
  catch {
    _PrintError
  }
  return $exists
}


function _GetWebClient {
  <#
    .SYNOPSIS
      Get Net.WebClient object.
    .DESCRIPTION
      Generata Webclient object for clients to use.
    .EXAMPLE
      $hostname = _GetWebClient
  #>
  $client = $null
  try {
    # WebClient to return.
    $client = New-Object Net.WebClient
  }
  catch [System.Net.WebException] {
    Write-Log 'Could not generate a WebClient object.'
    _PrintError
  }
  return $client
}


function _PrintError {
  <#
    .SYNOPSIS
      Prints Error Messages
    .DESCRIPTION
      This is a helper function which prints out error messages in catch
    .OUTPUTS
      Error message found during execution is printed out to the console.
    .EXAMPLE
      _PrintError
  #>

  # See all error objects.
  $error_obj = Get-Variable -Name Error -Scope 2 -ErrorAction SilentlyContinue
  if ($error_obj) {
    try {
      $message = $($error_obj.Value.Exception[0].Message)
      $line_no = $($error_obj.Value.InvocationInfo[0].ScriptLineNumber)
      $line_info = $($error_obj.Value.InvocationInfo[0].Line)
      $hresult = $($error_obj.Value.Exception[0].HResult)
      $calling_script = $($error_obj.Value.InvocationInfo[0].ScriptName)

      # Format error string
      if ($error_obj.Value.Exception[0].InnerException) {
        $inner_msg = $error_obj.Value.Exception[0].InnerException.Message
        $errmsg = "$inner_msg  : $message {Line: $line_no : $line_info, HResult: $hresult, Script: $calling_script}"
      }
      else {
        $errmsg = "$message {Line: $line_no : $line_info, HResult: $hresult, Script: $calling_script}"
      }
      # Write message to output.
      Write-Log $errmsg -error
    }
    catch {
      Write-Log $_.Exception.GetBaseException().Message -error
    }
  }

  # Clear out the error.
  $error.Clear() | Out-Null
}


function Invoke-ExternalCommand {
  <#
    .SYNOPSIS
      Run External Command.
    .DESCRIPTION
      This function calls an external command outside of the powershell script and logs the output.
    .PARAMETER Executable
      Executable that needs to be run.
    .PARAMETER Arguments
      Arguments for the executable. Default is NULL.
    .EXAMPLE
      Invoke-ExternalCommand dir c:\
  #>
 [CmdletBinding(SupportsShouldProcess=$true)]
  param (
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
      [string]$Executable,
    [Parameter(ValueFromRemainingArguments=$true,
               ValueFromPipelineByPropertyName=$true)]
      $Arguments = $null
  )
  Write-Log "Running '$Executable' with arguments '$Arguments'"
  $out = &$Executable $Arguments 2>&1 | Out-String
  if ($out.Trim()) {
    $out.Trim().Split("`n") | ForEach-Object {
      Write-Log "--> $_"
    }
  }
}


function _TestAdmin {
  <#
    .SYNOPSIS
      Checks if the current Powershell instance is running with
      elevated privileges or not.
    .OUTPUTS
      System.Boolean
      True if the current Powershell is elevated, false if not.
  #>
  try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    return $principal.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator )
  }
  catch {
    Write-Log 'Failed to determine if the current user has elevated privileges.'
    _PrintError
  }
}


function _TestTCPPort {
  <#
    .SYNOPSIS
      Test TCP port on remote server
    .DESCRIPTION
      Use .Net Socket connection to connect to remote host and check if port is
      open.
    .PARAMETER remote_host
      Remote host you want to check TCP port for.
    .PARAMETER port_number
      TCP port number you want to check.
    .PARAMETER timeout
      Time you want to wait for.
    .RETURNS
      Return bool. $true if server is reachable at tcp port $false is not.
    .EXAMPLE
      _TestTCPPort -host 127.0.0.1 -port 80
  #>
  param (
   [Alias('host')]
    [string]$remote_host,
   [Alias('port')]
    [int]$port_number,
   [int]$timeout = 3000
  )

  $status = $false
  try {
    # Create a TCP Client.
    $socket = New-Object Net.Sockets.TcpClient
    # Use the TCP Client to connect to remote host port.
    $connection = $socket.BeginConnect($remote_host, $port_number, $null, $null)
    # Set the wait time
    $wait = $connection.AsyncWaitHandle.WaitOne($timeout, $false)
    if (!$wait) {
      # Connection failed, timeout reached.
      $socket.Close()
    }
    else {
      # Close the connection and report the error if there is one.
      $socket.EndConnect($connection) | Out-Null
      if (!$?) {
        Write-Log $error[0]
      }
      else {
        $status = $true
      }
      $socket.Close()
    }
  }
  catch {
    _PrintError
  }
  return $status
}


function Write-SerialPort {
  <#
    .SYNOPSIS
      Sending data to serial port.
    .DESCRIPTION
      Use this function to send data to serial port.
    .PARAMETER portname
      Name of port. The port to use (for example, COM1).
    .PARAMETER baud_rate
      The baud rate.
    .PARAMETER parity
      Specifies the parity bit for a SerialPort object.
      None: No parity check occurs (default).
      Odd: Sets the parity bit so that the count of bits set is an odd number.
      Even: Sets the parity bit so that the count of bits set is an even number.
      Mark: Leaves the parity bit set to 1.
      Space: Leaves the parity bit set to 0.
    .PARAMETER data_bits
      The data bits value.
    .PARAMETER stop_bits
      Specifies the number of stop bits used on the SerialPort object.
      None: No stop bits are used. This value is Currently not supported by the
            stop_bits.
      One:  One stop bit is used (default).
      Two:  Two stop bits are used.
      OnePointFive: 1.5 stop bits are used.
    .PARAMETER data
      Data to be sent to serial port.
    .PARAMETER wait_for_respond
      Wait for result of data sent.
    .PARAMETER close
      Remote close connection.
    .EXAMPLE
      Send data to serial port and exit.
      Write-SerialPort -portname COM1 -data 'Hello World'
    .EXAMPLE
      Send data to serial port and wait for respond.
      Write-SerialPort -portname COM1 -data 'dir C:\' -wait_for_respond
  #>
  [CmdletBinding(supportsshouldprocess=$true)]
  param (
    [parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
      [string]$portname,
    [Int]$baud_rate = 9600,
    [ValidateSet('None', 'Odd', 'Even', 'Mark', 'Space')]
      [string]$parity = 'None',
    [int]$data_bits = 8,
    [ValidateSet('None', 'One', 'Even', 'Two', 'OnePointFive')]
      [string]$stop_bits = 'One',
    [string]$data,
    [Switch]$wait_for_respond,
    [Switch]$close
  )

  if ($psCmdlet.shouldProcess($portname , 'Write data to local serial port')) {
    if ($close) {
      $data = 'close'
      $wait_for_respond = $false
    }
    try {
      # Define a new object to read serial ports.
      $port = New-Object System.IO.Ports.SerialPort $portname, $baud_rate, `
                          $parity, $data_bits, $stop_bits
      $port.Open()
      # Write to the serial port.
      $port.WriteLine($data)
      # If wait_for_resond is specified.
      if ($wait_for_respond) {
        $result = $port.ReadLine()
        $result.Replace("#^#","`n")
      }
      $port.Close()
    }
    catch {
      _PrintError
    }
  }
}


function Write-Log {
  <#
    .SYNOPSIS
      Generate Log for the script.
    .DESCRIPTION
      Generate log messages, if COM1 port found write output to COM1 also.
    .PARAMETER $msg
      Message that needs to be logged
    .PARAMETER $is_important
      Surround the message with a line of hyphens.
    .PARAMETER $is_error
      Mark messages as Error in red text.
    .PARAMETER $is_warning
      Mark messages as Warning in yellow text.
  #>
  param (
    [parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
      [String]$msg,
    [Alias('important')]
    [Switch] $is_important,
    [Alias('error')]
    [Switch] $is_error,
    [Alias('warning')]
    [Switch] $is_warning
  )
  $timestamp = $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')
  if (-not ($global:logger)) {
    $global:logger = ''
  }
  try {
    # Add a boundary around an important message.
    if ($is_important) {
      $boundary = '-' * 60
      $timestampped_msg = @"
${timestamp} ${global:logger}: ${boundary}
${timestamp} ${global:logger}: ${msg}
${timestamp} ${global:logger}: ${boundary}
"@
    }
    else {
      $timestampped_msg = "${timestamp} ${global:logger}: ${msg}"
    }
    # If a log file is set, use it.
    if ($global:log_file) {
      Add-Content $global:log_file "$timestampped_msg"
    }
    # If COM1 exists write msg to console.
    if ($global:write_to_serial) {
      Write-SerialPort -portname 'COM1' -data "$timestampped_msg" -ErrorAction SilentlyContinue
    }
    if ($is_error) {
      Write-Host "$timestampped_msg" -foregroundcolor red
    }
    elseif ($is_warning)  {
      Write-Host "$timestampped_msg" -foregroundcolor yellow
    }
    else {
      Write-Host "$timestampped_msg"
    }
  }
  catch {
    _PrintError
    continue
  }
}


function Set-LogFile {
  param (
    [parameter(Position=0, Mandatory=$true)]
      [String]$filename
  )
  Write-Log "Initializing log file $filename."
  if (Test-Path $filename) {
    Write-Log 'Log file already exists.'
    $global:log_file = $filename
  }
  else {
    try {
      Write-Log 'Creating log file.'
      New-Item $filename -Type File -ErrorAction Stop
      $global:log_file = $filename
    }
    catch {
      _PrintError
    }
  }
  Write-Log "Log file set to $global:log_file"
}


# Export all modules.
New-Alias -Name _WriteToSerialPort -Value Write-SerialPort
New-Alias -Name _RunExternalCMD -Value Invoke-ExternalCommand
New-Alias -Name _ClearEventLogs -Value Clear-EventLogs
New-Alias -Name _ClearTempFolders -Value Clear-TempFolders
New-Alias -Name _FetchFromMetadata -Value Get-Metadata
Export-ModuleMember -Function * -Alias *

if (_GetCOMPorts -portname 'COM1') {
  $global:write_to_serial = $true
}

# Clear out any existing errors.
$error.Clear() | Out-Null
