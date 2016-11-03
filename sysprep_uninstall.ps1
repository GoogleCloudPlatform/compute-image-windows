$install_dir = "$env:ProgramFiles\Compute Engine\sysprep"

$path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($path -like "*$install_dir*") {
  $path = $path.Replace(";$install_dir", '')
  [Environment]::SetEnvironmentVariable('Path', $path, 'Machine')
}
