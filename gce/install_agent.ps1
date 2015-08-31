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

# Install script for the GCE agent and metadata scripts executable on Windows.

$github_url = 'https://github.com/GoogleCloudPlatform/compute-image-windows'

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
    Write-Host "Caught error finding latest release version: $message"
    exit 2
  }
}

function Install-Source {
  <#
    .SYNOPSIS
      Downloads a source URL and installs to destination location.

    .DESCRIPTION
      Attempt to download from a URL and install to a specified file.
      Print an error and exit if the download fails.

    .PARAMETER $binaries
      A list of binary names that need to be installed.

    .PARAMETER $src
      The URL to download.

    .PARAMETER $dest
      The destination where data should be written.

    .PARAMETER $service
      The service that should be started.
  #>
  param (
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String[]]$binaries,
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$src,
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$dest,
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$service
  )

  try {

    $client = New-Object System.Net.WebClient
    foreach ($binary in $binaries) {
      Write-Host "Downloading $binary..."
      $client.DownloadFile("$src/$binary", "$dest\$binary.temp")
    }

    Write-Host "Stopping $service..."
    Stop-Service $service

    foreach ($binary in $binaries) {
      $temp_dest = "$dest\$binary.temp"
      Copy-Item $temp_dest "$dest\$binary" -Force
      Remove-Item $temp_dest -Force
    }

    Start-Service $service
    Write-Host "Started $service."
    Write-Host 'Install complete.'
  }
  catch {
    Write-Host $Error.Exception[0].Message
    exit 2
  }
}

Write-Host 'Starting agent install script...'

$service_name = 'GCEAgent'
$common_assembly = 'Common.dll'
$agent_name = 'GCEWindowsAgent.exe'
$metadata_scripts_name = 'GCEMetadataScripts.exe'

# Get the latest release version.
$release_version = Get-LatestRelease
$download_path = "$github_url/releases/download/$release_version"
$destination = 'C:\Program Files\Google\Compute Engine\agent'
$binaries = @($agent_name, $metadata_scripts_name)

# Releases before 3.1.0.0 does not contain Common.dll.
# This logic need to be removed after 3.1.0.0 is released.
$common_version = '3.1.0.0'
if ([System.Version]$release_version -ge [System.Version]$common_version) {
  $binaries += $common_assembly
}

# Create the install directory if it does not exist.
if (-Not (Test-Path $destination)) {
  New-Item -ItemType directory -Path $destination
}

# Install the agent and metadata scripts.
Install-Source -binaries $binaries -src $download_path -dest $destination -service $service_name
Write-Host 'Installation of GCE Windows executables complete.'
