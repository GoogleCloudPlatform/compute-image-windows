@echo off
REM Copyright 2015 Google Inc. All Rights Reserved.
REM
REM Licensed under the Apache License, Version 2.0 (the "License");
REM you may not use this file except in compliance with the License.
REM You may obtain a copy of the License at
REM
REM     http://www.apache.org/licenses/LICENSE-2.0
REM
REM Unless required by applicable law or agreed to in writing, software
REM distributed under the License is distributed on an "AS IS" BASIS,
REM WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
REM See the License for the specific language governing permissions and
REM limitations under the License.
@echo on

REM Launch sysprep specialize phase.

%WinDir%\System32\oobe\windeploy.exe

REM Launch a powershell script to rename the computer.

%WinDir%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NoLogo -ExecutionPolicy Unrestricted -File "C:\Program Files\Google\Compute Engine\sysprep\instance_setup.ps1" -specialize
