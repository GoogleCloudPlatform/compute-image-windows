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
    Runs a script from the metadata server.

  .DESCRIPTION
    Downloads scripts of supported extensions and executes them.  Requires
    a base name, e.g. startup-script, from which it will look for metadata
    attributes of the form startup-script-cmd, startup-script-ps1, and any
    other supported extensions.

  .EXAMPLE
    run_metadata_script.ps1 -base windows-startup-script
#>
[CmdletBinding()]
param (
  [String]$base = $(Throw "-base is required.")
)

# Import modules.
Import-Module $PSScriptRoot\gce_base.psm1

_RunMetadataScript -base $base
