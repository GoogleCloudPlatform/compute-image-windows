if (-not (Get-Service 'GCEAgent' -ErrorAction SilentlyContinue)) {
  New-Service -Name 'GCEAgent' -BinaryPathName 'C:\Program Files\Google\Compute Engine\agent\GCEWindowsAgent.exe' -StartupType Automatic -Description 'Google Compute Engine Agent'
}

Restart-Service GCEAgent -Verbose
