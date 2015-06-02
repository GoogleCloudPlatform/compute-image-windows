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

$github_release = 'https://github.com/GoogleCloudPlatform/compute-image-windows/releases'

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
  $url = "$github_release/latest"
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

function Get-Url {
  <#
    .SYNOPSIS
      Download the contents of a provided URL.

    .DESCRIPTION
      Attempt to download the contents of a URL.
      Print an error and exit if the download fails.

    .PARAMETER $url
      The URL to download.

    .PARAMETER $name
      The name of the contents getting downloaded.
      For logging purposes only.

    .RETURNS
      $result: the downloaded content from the URL.
  #>
  param (
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$url,
    [parameter(Mandatory=$false, ValueFromPipeline=$true)]
      [String]$name
  )

  try {
    if ($name) {
      Write-Host "Downloading $name..."
    }
    $client = New-Object System.Net.WebClient
    $result = $client.DownloadData($url)
    Write-Host 'Download complete.'
  }
  catch {
    Write-Host $Error.Exception[0].Message
    exit 2
  }

  return $result
}

function Install-Source {
  <#
    .SYNOPSIS
      Write source data to destination location.

    .DESCRIPTION
      Attempt write data to a specified file.
      Print an error and exit if the download fails.

    .PARAMETER $source
      The data to store.

    .PARAMETER $path
      The destination where the data should be written.

    .PARAMETER $service
      The service that should be started.

    .PARAMETER $name
      The name of the source getting installed.
      For logging purposes only.
  #>
  param (
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      $source,
    [parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [String]$path,
    [parameter(Mandatory=$false, ValueFromPipeline=$true)]
      [String]$service,
    [parameter(Mandatory=$false, ValueFromPipeline=$true)]
      [String]$name
  )

  try {
    if ($name) {
      Write-Host "Installing $name..."
    }
    [IO.File]::WriteAllBytes($path, $source)
    if ($service) {
      Start-Service $service
    }
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
$agent_url = "$github_release/download/$release_version/$agent_name"
$metadata_scripts_url = "$github_release/download/$release_version/$metadata_scripts_name"

# Download the agent executable.
$agent_source = Get-Url -url $agent_url -name 'GCE agent'

# Remove the agent and stop the service.
if (Test-Path $agent_path) {
  Write-Host 'Stopping GCE agent...'
  Stop-Service $service_name
  Write-Host 'Deleting old GCE agent...'
  Remove-Item $agent_path -Force
  Write-Host 'Uninstall complete.'
}

# Create the install directory if it does not exist.
if (-Not (Test-Path $agent_dir)) {
  New-Item -ItemType directory -Path $agent_dir
}

# Install the agent executable.
Install-Source -source $agent_source -path $agent_path -service $service_name -name 'GCE agent'

# Download the GCE metadata script executable.
$metadata_scripts_source = Get-Url -url $metadata_scripts_url -name 'GCE metadata scripts executable'

# Remove the metadata scripts executable
if (Test-Path $metadata_scripts_path) {
  Write-Host 'Deleting old GCE metadata scripts executable...'
  Remove-Item $metadata_scripts_path -Force
  Write-Host 'Deletion complete.'
}

# Install the metadata scripts executable.
Install-Source -source $metadata_scripts_source -path $metadata_scripts_path -name 'GCE metadata scripts executable'

Write-Host 'Installation of GCE Windows scripts complete.'
