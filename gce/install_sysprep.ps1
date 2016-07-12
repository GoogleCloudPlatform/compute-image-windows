# Copyright 2015 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Install script for updating sysprep scripts on Windows.
param (
  [string] $Github = 'GoogleCloudPlatform',
  [string] $Tag,
  [switch] $Head = $false
 )

function Get-LatestRelease {
  <#
    .SYNOPSIS
      Get the lastet GitHub release version.

    .DESCRIPTION
      Request the lastest GitHub release of the GCE Windows agent
      and metadata scripts executable and return the release version.

    .RETURNS
      $result: the latest GitHub release version number.
  #>

  # The latest GitHub release.
  $url = "$github_url/releases/latest"
  $request = [System.Net.WebRequest]::Create($url)
  $request.AllowAutoRedirect=$false
  try {
    $response = $request.GetResponse()
    $redirect = $response.GetResponseHeader('Location')
    return $redirect.split('/')[-1]
  }
  catch {
    $message = $Error.Exception[0].Message
    Write-Host "Error finding latest release version: $message"
    exit 2
  }
}

$github_url = "https://github.com/$Github/compute-image-windows"

if ($PSBoundParameters.ContainsKey('Tag')) {
  $zip_version = $Tag
}
elseif ($Head) {
  $zip_version = 'master'
}
else {
  $zip_version = Get-LatestRelease
}

$github_zip = "$github_url/archive/$zip_version.zip"
$local_dest = 'C:\Program Files\Google\Compute Engine'
$local_github_zip = "$local_dest\github_source.zip"
$local_github_source = "$local_dest\github_source"
$sysprep_src = "$local_github_source\compute-image-windows-$zip_version\gce\*"

Write-Host 'Starting sysprep install script...'

# Download the GitHub zip of Windows guest code.
$client = New-Object System.Net.WebClient
$client.DownloadFile($github_zip, $local_github_zip)

# Load the assembly.
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Extract the GitHub zip file.
[System.IO.Compression.ZipFile]::ExtractToDirectory($local_github_zip, $local_github_source)

Copy-Item $sysprep_src $local_dest -Recurse -Force
Remove-Item $local_github_zip -Force
Remove-Item $local_github_source -Recurse -Force

Write-Host 'Installation of sysprep scripts complete.'
