$key = 'HKLM:\software\Microsoft\MSBuild\ToolsVersions\4.0'
$msbuild = Join-Path (Get-ItemProperty $key).MSBuildToolsPath 'msbuild.exe'

&$msbuild /t:build $args[0] /p:Configuration=Release
