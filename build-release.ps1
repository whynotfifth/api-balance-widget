# 打包 Release zip：本地运行或由 GitHub Actions 自动运行
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$version = '1.0.0'
if ($env:GITHUB_REF_NAME -match '^v(.+)$') { $version = $Matches[1] }

$dist = Join-Path $root 'dist'
$stage = Join-Path $dist "api-balance-widget-v$version"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$files = @(
  'balance-widget.ps1',
  'start-all.vbs', 'start-deepseek.vbs', 'start-vibetoken.vbs',
  'start-all.bat', 'start-deepseek.bat', 'start-vibetoken.bat',
  '开机自启设置.bat', 'toggle-autostart.ps1',
  'probe-vibetoken.bat', 'probe-vibetoken.ps1',
  'config.example.json',
  'README.md', 'LICENSE'
)
foreach ($f in $files) {
  $src = Join-Path $root $f
  if (Test-Path $src) { Copy-Item $src $stage }
}
if (Test-Path (Join-Path $root 'screenshots')) {
  Copy-Item (Join-Path $root 'screenshots') $stage -Recurse
}

$zip = Join-Path $dist "api-balance-widget-v$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
Remove-Item $stage -Recurse -Force
Write-Host "打包完成: $zip"
