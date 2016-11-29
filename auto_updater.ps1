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

$url = 'http://metadata.google.internal/computeMetadata/v1/instance/attributes?recursive=true&alt=json&timeout_sec=10&last_etag='

$client = New-Object System.Net.Http.HttpClient
$request = New-Object System.Net.Http.HttpRequestMessage -ArgumentList @([System.Net.Http.HttpMethod]::Get, $url)
$request.Headers.Add('Metadata-Flavor', 'Google')
$responseMsg = $client.SendAsync($request)
$responseMsg.Wait()

$response = $responseMsg.Result
if ($response.IsSuccessStatusCode) {
  $contentMsg = $responseMsg.Result.Content.ReadAsStringAsync()
  $metadata = ($contentMsg.Result).Trim() | ConvertFrom-Json
}
else {
  Write-Error "Error updating agent. Status code $($response.StatusCode)."
  exit 1
}

if ($metadata.'disable-agent-updates' -eq $true) {
  return
}

$args = @(
  '-noconfirm',
  'install',
  'googet',
  'google-compute-engine-windows',
  'google-compute-engine-sysprep',
  'google-compute-engine-metadata-scripts',
  'google-compute-engine-auto-updater',
  'google-compute-engine-powershell'
)

Start-Process 'C:\ProgramData\GooGet\googet.exe' -ArgumentList $args -Wait
