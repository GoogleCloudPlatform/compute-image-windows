@echo off
REM Copyright 2017 Google Inc. All Rights Reserved.
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

REM Batch script is used to call sysprep.ps1

REM Change working directory to load modules correctly.
cd "%~dp0"

REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Server\ServerLevels" /v NanoServer
IF %ERRORLEVEL% == 0 GOTO NANO

%WinDir%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Unrestricted -NonInteractive -NoProfile -NoLogo -File "%~dp0sysprep.ps1" %*
exit /b

:NANO
%WinDir%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Unrestricted -NonInteractive -NoProfile -NoLogo -File "%~dp0nano_sysprep.ps1" %*
exit /b
