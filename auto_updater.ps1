$url = "http://metadata.google.internal/computeMetadata/v1/instance/attributes?recursive=true&alt=json&timeout_sec=10&last_etag="
$headers = @{"X-Google-Metadata-Request" = "True"}
$metadata = (Invoke-WebRequest $url -Headers $headers -UseBasicParsing).Content | ConvertFrom-Json

if ($metadata.'disable-agent-updates') {
  return
}

$args = @(
  '-noconfirm',
  'install',
  'googet', 
  'google-compute-engine-windows-agent',
  'google-compute-engine-windows-agent-common',
  'google-compute-engine-sysprep',
  'google-compute-engine-metadata-scripts',
  'google-compute-engine-auto-updater',
  'google-compute-engine-powershell',
)

Start-Process 'C:\ProgramData\GooGet\googet.exe' -ArgumentList $args -Wait
