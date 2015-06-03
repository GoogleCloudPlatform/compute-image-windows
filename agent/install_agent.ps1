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

    .PARAMETER $src
      The URL to download.

    .PARAMETER $dest
      The destination where data should be written.

    .PARAMETER $service
      The service that should be started.

    .PARAMETER $name
      The name of the source getting installed.
      For logging purposes only.
  #>
  param (
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$src,
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$dest,
    [parameter(Mandatory=$false, ValueFromPipeline=$true)]
      [String]$service,
    [parameter(Mandatory=$false, ValueFromPipeline=$true)]
      [String]$name
  )

  try {
    if ($name) {
      Write-Host "Installing $name..."
    }
    $temp_dest = "$dest.temp"
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($src, $temp_dest)

    if ($service) {
      Write-Host "Stopping $service..."
      Stop-Service $service
      Copy-Item $temp_dest $dest -Force
      Start-Service $service
      Write-Host "Started $service."
    }
    else {
      Copy-Item $temp_dest $dest -Force
    }

    Remove-Item $temp_dest -Force
    Write-Host 'Install complete.'
  }
  catch {
    Write-Host $Error.Exception[0].Message
    exit 2
  }
}

Write-Host 'Starting agent install script...'

$agent_dir = 'C:\Program Files\Google\Compute Engine\agent'
$agent_name = 'GCEWindowsAgent.exe'
$metadata_scripts_name = 'GCEMetadataScripts.exe'
$agent_path = "$agent_dir\$agent_name"
$metadata_scripts_path = "$agent_dir\$metadata_scripts_name"
$service_name = 'GCEAgent'

# Get the latest release version.
$release_version = Get-LatestRelease
$agent_url = "$github_url/releases/download/$release_version/$agent_name"
$metadata_scripts_url = "$github_url/releases/download/$release_version/$metadata_scripts_name"

# Create the install directory if it does not exist.
if (-Not (Test-Path $agent_dir)) {
  New-Item -ItemType directory -Path $agent_dir
}

# Install the agent executable.
Install-Source -src $agent_url -dest $agent_path -service $service_name -name 'GCE agent'

# Install the metadata scripts executable.
Install-Source -src $metadata_scripts_url -dest $metadata_scripts_path -name 'GCE metadata scripts executable'

Write-Host 'Installation of GCE Windows scripts complete.'
