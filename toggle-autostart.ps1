# 开机自启开关：已开启则关闭，已关闭则开启（静默启动，无窗口）
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startup = [Environment]::GetFolderPath('Startup')
$ws = New-Object -ComObject WScript.Shell
$lnks = @('deepseek', 'vibetoken') | ForEach-Object { Join-Path $startup "余额挂件-$_.lnk" }
$existing = @($lnks | Where-Object { Test-Path $_ })

if ($existing.Count -gt 0) {
  foreach ($l in $existing) { Remove-Item $l -Force }
  Write-Host '已关闭开机自启：下次开机不再自动启动挂件。' -ForegroundColor Yellow
} else {
  foreach ($site in @('deepseek', 'vibetoken')) {
    $vbs = Join-Path $dir "start-$site.vbs"
    if (-not (Test-Path $vbs)) { throw "缺少启动器文件：$vbs" }
    $lnk = $ws.CreateShortcut((Join-Path $startup "余额挂件-$site.lnk"))
    $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $lnk.Arguments = "`"$vbs`""
    $lnk.WorkingDirectory = $dir
    $lnk.Description = "余额挂件 - $site"
    $lnk.Save()
  }
  Write-Host '已开启开机自启：开机后自动启动两个挂件（无任何窗口弹出）。' -ForegroundColor Green
  Write-Host '再次运行本脚本可关闭；或在挂件上右键 -> 取消勾选「开机自启」。'
}
