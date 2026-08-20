# 开机自启开关：已开启则关闭，已关闭则开启
# 主方式：注册表 Run 键（HKCU，无需管理员权限）；旧快捷方式/计划任务会自动清理并升级
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startup = [Environment]::GetFolderPath('Startup')
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$sites = @('deepseek', 'vibetoken')

function Test-RunValue([string]$name) {
  return [bool](Get-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue)
}
function Test-Task([string]$name) {
  try { return [bool](Get-ScheduledTask -TaskName $name -ErrorAction Stop) } catch { return $false }
}
function Install-RunValues {
  foreach ($site in $sites) {
    $vbs = Join-Path $dir "start-$site.vbs"
    if (-not (Test-Path $vbs)) { throw "缺少启动器文件：$vbs" }
    $cmd = "`"$env:WINDIR\System32\wscript.exe`" `"$vbs`""
    Set-ItemProperty -Path $runKey -Name "余额挂件-$site" -Value $cmd -ErrorAction Stop
  }
}
function Install-LnkFallback {
  foreach ($site in $sites) {
    $vbs = Join-Path $dir "start-$site.vbs"
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut((Join-Path $startup "余额挂件-$site.lnk"))
    $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $lnk.Arguments = "`"$vbs`""
    $lnk.WorkingDirectory = $dir
    $lnk.Save()
  }
}
function Remove-All {
  foreach ($site in $sites) {
    Remove-ItemProperty -Path $runKey -Name "余额挂件-$site" -ErrorAction SilentlyContinue
    try { Unregister-ScheduledTask -TaskName "余额挂件-$site" -Confirm:$false -ErrorAction SilentlyContinue } catch { }
  }
  Get-ChildItem $startup -Filter '余额挂件-*.lnk' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

$runOn = @($sites | Where-Object { Test-RunValue "余额挂件-$_" }).Count -gt 0
$taskOn = @($sites | Where-Object { Test-Task "余额挂件-$_" }).Count -gt 0
$lnkOn = @(Get-ChildItem $startup -Filter '余额挂件-*.lnk' -ErrorAction SilentlyContinue).Count -gt 0

if ($runOn) {
  # 已开启（注册表方式）→ 关闭
  Remove-All
  Write-Host '已关闭开机自启：下次开机不再自动启动挂件。' -ForegroundColor Yellow
}
elseif ($taskOn -or $lnkOn) {
  # 旧方式（快捷方式/计划任务）→ 升级为注册表 Run 键
  Remove-All
  try {
    Install-RunValues
    Write-Host '检测到旧版开机自启，已升级为注册表方式（更可靠）。' -ForegroundColor Green
  } catch {
    Write-Host "注册表写入失败：$($_.Exception.Message)，回退为启动文件夹方式。" -ForegroundColor Yellow
    Install-LnkFallback
    Write-Host '已用启动文件夹方式开启开机自启。' -ForegroundColor Green
  }
}
else {
  # 未开启 → 开启
  try {
    Install-RunValues
    Write-Host '已开启开机自启（注册表方式，无需管理员权限）：每次登录自动启动两个挂件，无任何窗口弹出。' -ForegroundColor Green
  } catch {
    Write-Host "注册表写入失败：$($_.Exception.Message)，改用启动文件夹方式。" -ForegroundColor Yellow
    Install-LnkFallback
    Write-Host '已用启动文件夹方式开启开机自启。' -ForegroundColor Green
  }
  Write-Host '再次运行本脚本可关闭；或在挂件上右键 -> 取消勾选「开机自启」。'
}
