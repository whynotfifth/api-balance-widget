# 开机自启开关：已开启则关闭，已关闭则开启；旧快捷方式自动升级为任务计划程序方式
# 任务计划程序「登录时」触发比启动文件夹更可靠（快速启动下也不易失效）
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startup = [Environment]::GetFolderPath('Startup')
$sites = @('deepseek', 'vibetoken')

function Test-Task([string]$name) {
  try { return [bool](Get-ScheduledTask -TaskName $name -ErrorAction Stop) } catch { return $false }
}
function New-Tasks {
  foreach ($site in $sites) {
    $vbs = Join-Path $dir "start-$site.vbs"
    if (-not (Test-Path $vbs)) { throw "缺少启动器文件：$vbs" }
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wscript.exe" -Argument "`"$vbs`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $null = Register-ScheduledTask -TaskName "余额挂件-$site" -Action $action -Trigger $trigger -Description "余额挂件 - $site（登录时自动启动）" -Force
  }
}

$tasks = @($sites | Where-Object { Test-Task "余额挂件-$_" })
$oldLnks = @(Get-ChildItem $startup -Filter '余额挂件-*.lnk' -ErrorAction SilentlyContinue)

if ($tasks.Count -gt 0) {
  # 已开启（任务方式）→ 关闭
  foreach ($site in $sites) {
    try { Unregister-ScheduledTask -TaskName "余额挂件-$site" -Confirm:$false -ErrorAction SilentlyContinue } catch { }
  }
  foreach ($l in $oldLnks) { Remove-Item $l.FullName -Force -ErrorAction SilentlyContinue }
  Write-Host '已关闭开机自启：下次开机不再自动启动挂件。' -ForegroundColor Yellow
}
elseif ($oldLnks.Count -gt 0) {
  # 旧版快捷方式 → 升级为任务计划程序方式（更可靠）
  foreach ($l in $oldLnks) { Remove-Item $l.FullName -Force -ErrorAction SilentlyContinue }
  try {
    New-Tasks
    Write-Host '检测到旧版开机自启，已自动升级为任务计划程序方式（更可靠，快速启动下不易失效）。' -ForegroundColor Green
  } catch {
    Write-Host "升级失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '已恢复旧方式（启动文件夹快捷方式）。' -ForegroundColor Yellow
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
}
else {
  # 未开启 → 开启（任务计划程序方式）
  try {
    New-Tasks
    Write-Host '已开启开机自启（任务计划程序方式，更可靠）：每次登录自动启动两个挂件，无任何窗口弹出。' -ForegroundColor Green
  } catch {
    Write-Host "任务注册失败：$($_.Exception.Message)，改用启动文件夹方式。" -ForegroundColor Yellow
    foreach ($site in $sites) {
      $vbs = Join-Path $dir "start-$site.vbs"
      $ws = New-Object -ComObject WScript.Shell
      $lnk = $ws.CreateShortcut((Join-Path $startup "余额挂件-$site.lnk"))
      $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
      $lnk.Arguments = "`"$vbs`""
      $lnk.WorkingDirectory = $dir
      $lnk.Save()
    }
    Write-Host '已开启开机自启（启动文件夹方式）。' -ForegroundColor Green
  }
  Write-Host '再次运行本脚本可关闭；或在挂件上右键 -> 取消勾选「开机自启」。'
}
