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

function Get-MetadataBool {
  param(
    [string]$Path
  )
  $url = 'http://metadata.google.internal/computeMetadata/v1/' + $Path
  Add-Type -AssemblyName System.Net.Http
  $client = New-Object System.Net.Http.HttpClient
  $request = New-Object System.Net.Http.HttpRequestMessage -ArgumentList @([System.Net.Http.HttpMethod]::Get, $url)
  $request.Headers.Add('Metadata-Flavor', 'Google')
  $responseMsg = $client.SendAsync($request)
  $responseMsg.Wait()

  $response = $responseMsg.Result
  if ($response.IsSuccessStatusCode) {
    $contentMsg = $response.Content.ReadAsStringAsync()
    try {
      $disable = [bool]::Parse(($contentMsg.Result).Trim())
    }
    catch [FormatException] {
      Write-Error "Error parsing metadata."
      return $true
    }
  }
  else {
    Write-Host "URL: $url, status code: $($response.StatusCode)"
    return $false
  }

  return $disable
}

$url = 'instance/attributes/disable-agent-updates'
if (Get-MetadataBool $url) {
  return
}

$url = 'project/attributes/disable-agent-updates'
if (Get-MetadataBool $url) {
  return
}

$args = @(
  '-noconfirm',
  'install',
  'googet',
  'certgen',
  'google-compute-engine-windows',
  'google-compute-engine-sysprep',
  'google-compute-engine-metadata-scripts',
  'google-compute-engine-auto-updater',
  'google-compute-engine-powershell',
  'google-compute-engine-vss'
)

Start-Process 'C:\ProgramData\GooGet\googet.exe' -ArgumentList $args -Wait
